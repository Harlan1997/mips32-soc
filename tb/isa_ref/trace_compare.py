#!/usr/bin/env python3
"""Compare committed RTL and golden architectural traces, one JSON object/line."""
import argparse
import fcntl
import gzip
import json
import os
import stat
import sys

try:
    import orjson
except ImportError:  # pragma: no cover - standard-library fallback
    orjson = None

STREAM_PIPE_SIZE = 1 << 20
F_SETPIPE_SZ = getattr(
    fcntl, "F_SETPIPE_SZ", 1031 if sys.platform.startswith("linux") else None)

BASE_FIELDS = ("schema", "pc", "instr", "next_pc", "except", "except_code", "bd", "eret")
TRACE_FIELDS = {
    "retire_seq", "schema", "pc", "instr", "next_pc", "gpr_we",
    "gpr_addr", "gpr_data", "cp0_we", "cp0_addr", "cp0_sel", "cp0_data",
    "fpr_state", "fcsr_state", "mem_valid", "mem_read", "mem_write",
    "mem_addr", "mem_wdata", "mem_be", "mem_rdata", "except",
    "except_code", "bd", "eret",
}
TRACE_STATE_FIELDS = {"gpr_state", "hilo_state"}
SUPPORTED_TRACE_SCHEMAS = {"00010000", "00020000"}

def comparable_cp0_write(obj):
    """Return true when either producer reports a committed CP0 write."""
    try:
        return int(obj.get("cp0_we", 0)) != 0
    except (TypeError, ValueError):
        return False


def normalize_direct_map(value):
    """Normalize MIPS kseg0/kseg1 aliases to their physical 512 MiB view."""
    if not isinstance(value, str) or len(value) != 8:
        return value
    try:
        address = int(value, 16)
    except ValueError:
        return value
    if 0x80000000 <= address <= 0xbfffffff:
        return f"{address & 0x1fffffff:08x}"
    return value.lower()


def direct_map_alias_pair(left, right):
    if not isinstance(left, str) or not isinstance(right, str):
        return False
    if normalize_direct_map(left) != normalize_direct_map(right):
        return False
    try:
        left_segment = int(left, 16) >> 29
        right_segment = int(right, 16) >> 29
    except ValueError:
        return False
    return ((left_segment == 0 and right_segment in (4, 5)) or
            (right_segment == 0 and left_segment in (4, 5)))


def is_link_address_write(obj):
    try:
        instruction = int(obj.get("instr", "0"), 16)
        pc = int(obj.get("pc", "0"), 16)
        destination = int(obj.get("gpr_addr", -1))
        result = int(obj.get("gpr_data", "0"), 16)
        register_write = int(obj.get("gpr_we", 0))
    except (TypeError, ValueError):
        return False
    opcode = (instruction >> 26) & 0x3f
    if opcode == 0x03:
        link_register = 31
    elif opcode == 0 and (instruction & 0x3f) == 0x09:
        link_register = (instruction >> 11) & 0x1f
    else:
        return False
    return (register_write and link_register != 0 and
            destination == link_register and
            result == ((pc + 8) & 0xffffffff))


def is_exception_vector_alias_pair(left, right):
    return (normalize_direct_map(left) == "00000180" and
            normalize_direct_map(right) == "00000180" and
            direct_map_alias_pair(left, right))


def comparable(field, value):
    if field in ("pc", "next_pc", "mem_addr", "gpr_data", "cp0_data"):
        # These are architectural virtual values, not physical backing
        # addresses. KSEG0/KSEG1 aliases can differ in cacheability and are
        # observably distinct in PC, effective-address, and register state.
        return value.lower() if isinstance(value, str) else value
    return value


def is_mfc0_index(obj):
    """Return true for MFC0 reads of CP0 Index (register 0, select 0)."""
    try:
        instruction = int(obj.get("instr", "0"), 16)
    except (TypeError, ValueError):
        return False
    return (((instruction >> 26) & 0x3f) == 0x10 and
            ((instruction >> 21) & 0x1f) == 0 and
            ((instruction >> 11) & 0x1f) == 0 and
            (instruction & 0x7) == 0)


def comparable_record_field(field, obj, value, peer=None,
                           vector_alias_window=False):
    if (field in ("pc", "next_pc") and vector_alias_window and
            peer is not None and
            direct_map_alias_pair(value, peer.get(field))):
        return normalize_direct_map(value)
    if (field == "gpr_data" and vector_alias_window and peer is not None and
            is_link_address_write(obj) and is_link_address_write(peer) and
            direct_map_alias_pair(value, peer.get(field))):
        return normalize_direct_map(value)
    if field == "gpr_data" and is_mfc0_index(obj):
        try:
            register_value = int(value, 16)
        except (TypeError, ValueError):
            return comparable(field, value)
        if register_value & 0x80000000:
            # TLBP defines Index.P on a miss; the low index field is
            # implementation-dependent and QEMU preserves its previous value.
            return "80000000"
    if field == "gpr_state" and is_mfc0_index(obj):
        try:
            instruction = int(obj.get("instr", "0"), 16)
            destination = (instruction >> 16) & 0x1f
            register_address = int(obj.get("gpr_addr", -1))
            register_write = int(obj.get("gpr_we", 0))
            result = int(obj.get("gpr_data", "0"), 16)
            state_value = int(value[(31 - destination) * 8:
                                    (32 - destination) * 8], 16)
        except (TypeError, ValueError, IndexError):
            return comparable(field, value)
        if (register_write and destination != 0 and
                register_address == destination and
                result & 0x80000000 and state_value & 0x80000000):
            offset = (31 - destination) * 8
            return value[:offset] + "80000000" + value[offset + 8:]
    return comparable(field, value)


def gpr_write_destination(obj):
    try:
        destination = int(obj.get("gpr_addr", -1))
        register_write = int(obj.get("gpr_we", 0))
    except (TypeError, ValueError):
        return None
    return destination if register_write and 0 < destination < 32 else None


def index_miss_destination(obj):
    """Return the GPR holding an implementation-dependent Index miss value."""
    if not is_mfc0_index(obj):
        return None
    try:
        instruction = int(obj.get("instr", "0"), 16)
        destination = (instruction >> 16) & 0x1f
        result = int(obj.get("gpr_data", "0"), 16)
    except (TypeError, ValueError):
        return None
    if (destination != 0 and gpr_write_destination(obj) == destination and
            result & 0x80000000):
        return destination
    return None


def index_taint_after_write(tainted, obj):
    """Track Index miss bits until the destination GPR is overwritten."""
    updated = set(tainted)
    destination = gpr_write_destination(obj)
    if destination is not None:
        updated.discard(destination)
    miss_destination = index_miss_destination(obj)
    if miss_destination is not None:
        updated.add(miss_destination)
    return updated


def index_taint_for_state(tainted, obj):
    """Return prior taints still present after this record's GPR write."""
    updated = set(tainted)
    destination = gpr_write_destination(obj)
    if destination is not None:
        updated.discard(destination)
    return updated


def mask_index_miss_gprs(value, registers):
    """Mask only the undefined low Index bits in tainted GPR snapshot words."""
    if not isinstance(value, str) or len(value) != 256:
        return value
    normalized = value.lower()
    for register in registers:
        offset = (31 - register) * 8
        try:
            word = int(normalized[offset:offset + 8], 16)
        except ValueError:
            return value
        normalized = (normalized[:offset] + f"{word & 0x80000000:08x}" +
                      normalized[offset + 8:])
    return normalized


def load(path):
    if path.endswith(".gz"):
        trace_file = gzip.open(path, "rt", encoding="ascii")
    else:
        trace_file = open(path, encoding="ascii")
    with trace_file as f:
        if F_SETPIPE_SZ is not None:
            try:
                if stat.S_ISFIFO(os.fstat(f.fileno()).st_mode):
                    # Match the QEMU stream reader's bounded FIFO capacity.
                    fcntl.fcntl(f.fileno(), F_SETPIPE_SZ, STREAM_PIPE_SIZE)
            except OSError:
                pass
        for n, line in enumerate(f, 1):
            if line.strip():
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    raw_record = line.rstrip("\r\n")
                    raise ValueError(
                        f"{path}:{n}: invalid JSON: {e}; "
                        f"record={raw_record[:512]!r}") from e
                yield n, obj


def fast_load(path):
    """Yield JSON records with a low-overhead decoder for long RTL streams."""
    opener = gzip.open if path.endswith(".gz") else open
    open_args = (path, "rb")
    with opener(*open_args) as trace_file:
        for line in trace_file:
            if line.strip():
                yield (orjson.loads(line) if orjson is not None else
                       json.loads(line))


def fast_linux_stream_compare(rtl_path, golden_path, args):
    """Compare schema-1 Linux RTL traces without full taint bookkeeping.

    The Linux differential has no FPU or full architectural-state payload. Its
    relevant fields are the committed instruction, register/CP0 writes,
    memory transaction, and precise exception metadata. Delay-slot next-PC and
    asynchronous interrupt metadata follow the same exclusions as the full
    stream comparator.
    """
    rtl = iter(fast_load(rtl_path))
    golden = iter(fast_load(golden_path))
    previous_r = previous_g = None
    compared = 0
    mismatch = None

    def next_record(iterator):
        try:
            return next(iterator)
        except StopIteration:
            return None

    while args.limit is None or compared < args.limit:
        r = next_record(rtl)
        g = next_record(golden)
        if r is None or g is None:
            if r is None and g is None:
                break
            mismatch = (compared, "trace_length", r, g)
            break
        if r.get("schema", "").lower() != "00010000" or \
                g.get("schema", "").lower() != "00010000":
            mismatch = (compared, "schema", r.get("schema"), g.get("schema"))
            break
        if r.get("retire_seq") != compared or g.get("retire_seq") != compared:
            mismatch = (compared, "retire_seq", r.get("retire_seq"),
                        g.get("retire_seq"))
            break

        async_boundary = (is_async_interrupt_boundary(r) or
                          is_async_interrupt_boundary(g))
        delay_slot = (has_delay_slot(r.get("instr")) or
                      has_delay_slot(g.get("instr")) or
                      (previous_r is not None and
                       has_delay_slot(previous_r.get("instr"))) or
                      (previous_g is not None and
                       has_delay_slot(previous_g.get("instr"))))
        fields = ["schema", "pc", "instr"]
        if not async_boundary and not delay_slot:
            fields.append("next_pc")
        if not async_boundary:
            fields.extend(("except", "except_code", "bd", "eret"))
        if r.get("gpr_we") or g.get("gpr_we"):
            fields.extend(("gpr_we", "gpr_addr", "gpr_data"))
        if comparable_cp0_write(r) or comparable_cp0_write(g):
            fields.extend(("cp0_we", "cp0_addr", "cp0_sel", "cp0_data"))
        fields.extend(("fpr_state", "fcsr_state"))
        if r.get("mem_valid") or g.get("mem_valid"):
            fields.extend(("mem_valid", "mem_read", "mem_write", "mem_addr"))
            if r.get("mem_write") or g.get("mem_write"):
                fields.append("mem_wdata")
            if (r.get("mem_read") or g.get("mem_read")) and \
                    not (is_merge_memory_instruction(r) or
                         is_merge_memory_instruction(g) or
                         is_narrow_load(r) or is_narrow_load(g) or
                         is_double_memory_instruction(r) or
                         is_double_memory_instruction(g)) and \
                    not (is_synchronous_exception(r) or
                         is_synchronous_exception(g)):
                fields.append("mem_rdata")
        for field in fields:
            if r.get(field) != g.get(field):
                mismatch = (compared, field, r.get(field), g.get(field))
                break
        if mismatch is not None:
            break
        previous_r, previous_g = r, g
        compared += 1

    limit_reached = args.limit is not None and compared >= args.limit
    if mismatch is not None:
        idx, field, got, expected = mismatch
        print(f"MISMATCH retire={idx} field={field} rtl={got!r} golden={expected!r}",
              file=sys.stderr)
        return 1
    if not limit_reached:
        print(f"TRACE_COMPARE_ERROR: trace shorter than requested limit ({compared})",
              file=sys.stderr)
        return 1
    print("TRACE_COMPARE_UNPAIRED_SUMMARY side=rtl total=0 reasons=none")
    print("TRACE_COMPARE_UNPAIRED_SUMMARY side=golden total=0 reasons=none")
    print(f"TRACE_COMPARE_SEQUENCE_PASS rtl_first=0 rtl_last={compared - 1} "
          f"golden_first=0 golden_last={compared - 1}")
    print("TRACE_COMPARE_SYNC_EXCEPTION_PASS count=0")
    print(f"TRACE_COMPARE_PASS records={compared} mode=stream-limit "
          f"rtl_consumed={compared} golden_consumed={compared} "
          "rtl_unpaired=0 golden_unpaired=0")
    return 0


def validate_trace_record(record, side, record_number):
    if not isinstance(record, dict):
        raise ValueError(f"{side} record {record_number} is not an object")
    schema = record.get("schema")
    if not isinstance(schema, str) or schema.lower() not in SUPPORTED_TRACE_SCHEMAS:
        raise ValueError(f"{side} record {record_number} has unsupported schema: {schema!r}")
    missing = TRACE_FIELDS.difference(record)
    if schema.lower() == "00020000":
        missing.update(TRACE_STATE_FIELDS.difference(record))
    if missing:
        raise ValueError(
            f"{side} record {record_number} missing fields: "
            f"{', '.join(sorted(missing))}")
    if schema.lower() == "00020000":
        gpr_state = record["gpr_state"]
        hilo_state = record["hilo_state"]
        if not isinstance(gpr_state, str) or len(gpr_state) != 256 or \
                any(char not in "0123456789abcdefABCDEF" for char in gpr_state):
            raise ValueError(f"{side} record {record_number} has invalid gpr_state")
        if not isinstance(hilo_state, str) or len(hilo_state) != 16 or \
                any(char not in "0123456789abcdefABCDEF" for char in hilo_state):
            raise ValueError(f"{side} record {record_number} has invalid hilo_state")


class Peekable:
    """Small look-ahead wrapper used by the bounded-memory comparator."""
    def __init__(self, iterable):
        self._iter = iter(iterable)
        self._buffer = []

    def peek(self):
        if not self._buffer:
            try:
                self._buffer.append(next(self._iter))
            except StopIteration:
                return None
        return self._buffer[0]

    def peek_ahead(self, index):
        while len(self._buffer) <= index:
            try:
                self._buffer.append(next(self._iter))
            except StopIteration:
                return None
        return self._buffer[index]

    def pop(self):
        item = self.peek()
        if item is not None:
            self._buffer.pop(0)
        return item


def stream_fields(r, g, previous_r, previous_g, next_r, next_g, args):
    """Return fields comparable for one streaming trace pair.

    The long Linux differential has no FPU architectural activity, so its
    state is compared directly.  The bounded look-ahead preserves the
    producer-specific delay-slot and exception-vector rules without retaining
    the complete trace in memory.  Short traces continue using the richer
    list-based path below, including the FPU observation window.
    """
    fields = list(BASE_FIELDS)
    if (is_async_interrupt_boundary(r) or is_async_interrupt_boundary(g) or
            (previous_r is not None and
             is_async_interrupt_boundary(previous_r)) or
            (previous_g is not None and
             is_async_interrupt_boundary(previous_g))):
        fields = [field for field in fields
                  if field not in ("next_pc", "except", "except_code", "bd")]
    if ((previous_r is not None and has_delay_slot(previous_r.get("instr"))) or
            (previous_g is not None and has_delay_slot(previous_g.get("instr"))) or
            has_delay_slot(r.get("instr")) or has_delay_slot(g.get("instr")) or
            (next_r is not None and normalize_direct_map(next_r.get("pc")) == "00000180") or
            (next_g is not None and normalize_direct_map(next_g.get("pc")) == "00000180")):
        fields = [field for field in fields if field not in ("next_pc", "bd")]
    if ((r.get("gpr_we") or g.get("gpr_we"))):
        fields += ["gpr_we", "gpr_addr", "gpr_data"]
    if comparable_cp0_write(r) or comparable_cp0_write(g):
        fields += ["cp0_we", "cp0_addr", "cp0_sel", "cp0_data"]
    if r.get("fpr_state") is not None or g.get("fpr_state") is not None:
        fields += ["fpr_state", "fcsr_state"]
    if r.get("schema", "").lower() == "00020000" or \
            g.get("schema", "").lower() == "00020000":
        fields += ["gpr_state", "hilo_state"]
    if r.get("mem_valid") or g.get("mem_valid"):
        fields += ["mem_valid", "mem_read", "mem_write", "mem_addr", "mem_be"]
        if r.get("mem_write") or g.get("mem_write"):
            fields.append("mem_wdata")
            if (is_double_store_instruction(r) or
                    is_double_store_instruction(g)):
                fields.append("mem_wdata_hi")
        if r.get("mem_read") or g.get("mem_read"):
            fields.append("mem_rdata")
        fields.remove("mem_be")
        if is_synchronous_exception(r) or is_synchronous_exception(g):
                if r.get("mem_valid") and g.get("mem_valid"):
                    fields = [field for field in fields
                              if field not in ("mem_wdata", "mem_wdata_hi",
                                               "mem_rdata")]
                else:
                    fields = [field for field in fields if field not in
                              ("mem_valid", "mem_read", "mem_write", "mem_addr",
                               "mem_wdata", "mem_wdata_hi", "mem_rdata")]
    if is_merge_memory_instruction(r) or is_merge_memory_instruction(g):
        fields = [field for field in fields if field != "mem_rdata"]
    if is_narrow_load(r) or is_narrow_load(g):
        # QEMU's plugin reports the raw 8/16-bit bus value, while the RTL
        # retire bundle exposes the sign/zero-extended architectural result.
        fields = [field for field in fields if field != "mem_rdata"]
    if is_double_memory_instruction(r) or is_double_memory_instruction(g):
        fields = [field for field in fields if field != "mem_rdata"]
    return fields


def stream_compare(rtl_path, golden_path, args):
    """Compare traces with bounded memory, for long Linux captures."""
    rtl = Peekable(load(rtl_path))
    golden = Peekable(load(golden_path))
    sequence_state = {
        "rtl": {"first": None, "previous": None, "last": None},
        "golden": {"first": None, "previous": None, "last": None},
    }
    unpaired_records = {"rtl": 0, "golden": 0}
    unpaired_reasons = {"rtl": {}, "golden": {}}
    unpaired_samples = []
    sync_exception_samples = []
    index_taint = {"rtl": set(), "golden": set()}
    hilo_gpr_taint = {"rtl": set(), "golden": set()}
    memory_taint = {"rtl": set(), "golden": set()}
    hilo_valid_mask = {"rtl": 0x3, "golden": 0x3}

    def record_sequence(item, side, gpr_taint_before=None):
        """Validate contiguous producer sequence numbers as records are consumed."""
        if item is None:
            return
        value = item[1].get("retire_seq")
        validate_trace_record(item[1], side, item[0])
        if not isinstance(value, int) or isinstance(value, bool):
            raise ValueError(f"{side} retire_seq is not an integer: {value!r}")
        state = sequence_state[side]
        if state["first"] is None:
            state["first"] = value
        elif value != state["previous"] + 1:
            raise ValueError(
                f"{side} retire_seq is not contiguous: expected "
                f"{state['previous'] + 1}, got {value}")
        state["previous"] = value
        state["last"] = value
        if gpr_taint_before is None:
            gpr_taint_before = hilo_gpr_taint[side]
        hilo_valid_mask[side] = mips32_hilo_valid_mask_after(
            hilo_valid_mask[side], item[1], gpr_taint_before)

    def note_unpaired(item, side, reason, peer=None):
        record = item[1]
        gpr_taint_before = hilo_gpr_taint[side]
        hilo_gpr_taint_after = hilo_gpr_taint_after_write(
            gpr_taint_before, memory_taint[side], record,
            hilo_valid_mask[side])
        memory_taint_after = memory_taint_after_record(
            memory_taint[side], record, gpr_taint_before)
        record_sequence(item, side, gpr_taint_before)
        index_taint[side] = index_taint_after_write(index_taint[side], record)
        hilo_gpr_taint[side] = hilo_gpr_taint_after
        memory_taint[side] = memory_taint_after
        unpaired_records[side] += 1
        reasons = unpaired_reasons[side]
        reasons[reason] = reasons.get(reason, 0) + 1
        if len(unpaired_samples) < 32:
            record = item[1]
            peer_record = peer[1] if peer is not None else {}
            unpaired_samples.append({
                "side": side,
                "reason": reason,
                "retire_seq": record.get("retire_seq"),
                "pc": record.get("pc"),
                "instr": record.get("instr"),
                "next_pc": record.get("next_pc"),
                "except": record.get("except"),
                "except_code": record.get("except_code"),
                "bd": record.get("bd"),
                "peer_pc": peer_record.get("pc"),
                "peer_instr": peer_record.get("instr"),
            })

    if args.align_first_pc:
        first_golden = golden.pop()
        if first_golden is None:
            raise ValueError("cannot align an empty golden trace")
        wanted_pc = normalize_direct_map(
            f"{int(args.align_first_pc, 16) & 0xffffffff:08x}")
        if normalize_direct_map(first_golden[1].get("pc")) != wanted_pc:
            raise ValueError(
                "golden trace first PC does not match --align-first-pc: "
                f"{first_golden[1].get('pc')!r} != {wanted_pc!r}")
        while True:
            candidate = rtl.peek()
            if candidate is None:
                raise ValueError("RTL trace has no matching PC/instruction handoff")
            if (normalize_direct_map(candidate[1].get("pc")) == wanted_pc and
                    candidate[1].get("instr") == first_golden[1].get("instr")):
                break
            note_unpaired(rtl.pop(), "rtl", "first_pc_prefix", first_golden)
        golden._buffer.insert(0, first_golden)

    previous_r = previous_g = None
    compared = 0
    mismatches = []
    stopped_at_completion = False
    vector_alias_window = False
    while args.limit is None or compared < args.limit:
        r_item = rtl.peek()
        g_item = golden.peek()
        if r_item is None or g_item is None:
            break
        r = r_item[1]
        g = g_item[1]
        rtl_hilo_valid_after = mips32_hilo_valid_mask_after(
            hilo_valid_mask["rtl"], r, hilo_gpr_taint["rtl"])
        golden_hilo_valid_after = mips32_hilo_valid_mask_after(
            hilo_valid_mask["golden"], g, hilo_gpr_taint["golden"])
        comparable_hilo_valid = rtl_hilo_valid_after & golden_hilo_valid_after
        rtl_hilo_read_destination = undefined_hilo_read_destination(
            r, hilo_valid_mask["rtl"])
        golden_hilo_read_destination = undefined_hilo_read_destination(
            g, hilo_valid_mask["golden"])
        rtl_hilo_gpr_taint_after = hilo_gpr_taint_after_write(
            hilo_gpr_taint["rtl"], memory_taint["rtl"], r,
            hilo_valid_mask["rtl"])
        golden_hilo_gpr_taint_after = hilo_gpr_taint_after_write(
            hilo_gpr_taint["golden"], memory_taint["golden"], g,
            hilo_valid_mask["golden"])

        # Preserve the one-record general-vector alignment used by the list
        # comparator, using only one look-ahead record on either stream.
        r_next_item = rtl.peek_ahead(1)
        g_next_item = golden.peek_ahead(1)
        r_next = r_next_item[1] if r_next_item is not None else None
        g_next = g_next_item[1] if g_next_item is not None else None
        if is_exception_vector_alias_pair(r.get("pc"), g.get("pc")):
            vector_alias_window = True
        rtl_pc = normalize_direct_map(r.get("pc"))
        golden_pc = normalize_direct_map(g.get("pc"))
        if sync_exception_reaches(r, golden_pc):
            sync_exception_samples.append(
                validate_rtl_sync_exception_state(r, g))
            note_unpaired(rtl.pop(), "rtl", "rtl_sync_exception_redirect",
                          g_item)
            continue
        if sync_exception_reaches(g, rtl_pc):
            note_unpaired(golden.pop(), "golden",
                          "golden_sync_exception_redirect", r_item)
            continue
        if (g_next is not None and
                async_boundary_reaches(g_next, rtl_pc) and
                is_side_effect_free_control_transfer(g)):
            note_unpaired(golden.pop(), "golden",
                          "golden_control_transfer_before_async_boundary",
                          r_item)
            continue
        if (r_next is not None and
                async_boundary_reaches(r_next, golden_pc) and
                is_side_effect_free_control_transfer(r)):
            note_unpaired(rtl.pop(), "rtl",
                          "rtl_control_transfer_before_async_boundary",
                          g_item)
            continue
        if async_boundary_reaches(g, rtl_pc):
            note_unpaired(golden.pop(), "golden",
                          "golden_async_interrupt_boundary", r_item)
            continue
        if async_boundary_reaches(r, golden_pc):
            note_unpaired(rtl.pop(), "rtl", "rtl_async_interrupt_boundary",
                          g_item)
            continue
        if golden_pc == "00000180" and rtl_pc != golden_pc:
            if (r_next is not None and
                    normalize_direct_map(r_next.get("pc")) == golden_pc):
                note_unpaired(rtl.pop(), "rtl", "rtl_pre_exception_vector",
                              g_item)
                continue
        if rtl_pc == "00000180" and golden_pc != rtl_pc:
            if (g_next is not None and
                    normalize_direct_map(g_next.get("pc")) == rtl_pc):
                note_unpaired(golden.pop(), "golden",
                              "golden_pre_exception_vector", r_item)
                continue

        fields = stream_fields(r, g, previous_r, previous_g, r_next, g_next,
                               args)
        if (rtl_hilo_read_destination is not None or
                golden_hilo_read_destination is not None or
                gpr_write_destination(r) in rtl_hilo_gpr_taint_after or
                gpr_write_destination(g) in golden_hilo_gpr_taint_after):
            fields = [field for field in fields if field != "gpr_data"]
        rtl_mem_address_tainted = memory_address_tainted(
            r, hilo_gpr_taint["rtl"])
        golden_mem_address_tainted = memory_address_tainted(
            g, hilo_gpr_taint["golden"])
        rtl_store_value_tainted = memory_store_value_tainted(
            r, hilo_gpr_taint["rtl"])
        golden_store_value_tainted = memory_store_value_tainted(
            g, hilo_gpr_taint["golden"])
        rtl_load_value_tainted = memory_load_value_tainted(
            r, memory_taint["rtl"])
        golden_load_value_tainted = memory_load_value_tainted(
            g, memory_taint["golden"])
        if rtl_mem_address_tainted or golden_mem_address_tainted:
            fields = [field for field in fields if field != "mem_addr"]
        if (rtl_store_value_tainted or golden_store_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields
                      if field not in ("mem_wdata", "mem_wdata_hi")]
        if (rtl_load_value_tainted or golden_load_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields if field != "mem_rdata"]
        rtl_state_taint = index_taint_for_state(index_taint["rtl"], r)
        golden_state_taint = index_taint_for_state(index_taint["golden"], g)
        comparable_state_taint = rtl_state_taint & golden_state_taint
        comparable_hilo_gpr_taint = (rtl_hilo_gpr_taint_after |
                                     golden_hilo_gpr_taint_after)
        if deferred_eret_target_fetch_exception(r, g, r_next, g_next):
            fields = [field for field in fields
                      if field not in ("except", "except_code")]
        missing_double_store_hi = (
            not is_synchronous_exception(r) and
            not is_synchronous_exception(g) and
            ((is_double_store_instruction(r) and r.get("mem_write")) or
             (is_double_store_instruction(g) and g.get("mem_write"))) and
            ("mem_wdata_hi" not in r or "mem_wdata_hi" not in g))
        if missing_double_store_hi:
            mismatches.append((compared, "mem_wdata_hi",
                               r.get("mem_wdata_hi", "<missing>"),
                               g.get("mem_wdata_hi", "<missing>"),
                               r, g, previous_r, previous_g, r_next, g_next))
            fields = []
        for field in fields:
            got = comparable_record_field(
                field, r, r.get(field), peer=g,
                vector_alias_window=vector_alias_window)
            expected = comparable_record_field(
                field, g, g.get(field), peer=r,
                vector_alias_window=vector_alias_window)
            if field == "gpr_state":
                got = mask_index_miss_gprs(got, comparable_state_taint)
                expected = mask_index_miss_gprs(expected,
                                                comparable_state_taint)
                got = mask_gpr_registers(got, comparable_hilo_gpr_taint)
                expected = mask_gpr_registers(expected,
                                              comparable_hilo_gpr_taint)
            if field == "hilo_state":
                got = mask_hilo_state(got, comparable_hilo_valid)
                expected = mask_hilo_state(expected, comparable_hilo_valid)
            if got != expected:
                mismatches.append((compared, field, r.get(field), g.get(field),
                                   r, g, previous_r, previous_g, r_next, g_next))
                break
        record_sequence(rtl.pop(), "rtl")
        record_sequence(golden.pop(), "golden")
        index_taint["rtl"] = index_taint_after_write(index_taint["rtl"], r)
        index_taint["golden"] = index_taint_after_write(index_taint["golden"], g)
        memory_taint["rtl"] = memory_taint_after_record(
            memory_taint["rtl"], r, hilo_gpr_taint["rtl"])
        memory_taint["golden"] = memory_taint_after_record(
            memory_taint["golden"], g, hilo_gpr_taint["golden"])
        hilo_gpr_taint["rtl"] = rtl_hilo_gpr_taint_after
        hilo_gpr_taint["golden"] = golden_hilo_gpr_taint_after
        if r.get("eret") or g.get("eret"):
            vector_alias_window = False
        compared += 1
        if args.stop_after_mailbox and (is_completion_store(r) or
                                         is_completion_store(g)):
            stopped_at_completion = True
            break
        if mismatches or len(mismatches) >= args.max_mismatches:
            break
        previous_r, previous_g = r, g

    limit_reached = args.limit is not None and compared >= args.limit
    if (not limit_reached and not stopped_at_completion and not mismatches and
            g_item is not None and r_item is None and
            not args.truncate_golden_to_rtl):
        mismatches.append((compared, "trace_length", "rtl-eof", "golden-more"))
    if (args.limit is not None and compared < args.limit and
            not mismatches):
        mismatches.append((compared, "trace_length", "shorter-than-limit",
                           args.limit))
    if (not limit_reached and not stopped_at_completion and not mismatches and
            g_item is None):
        if not args.allow_golden_prefix:
            extra = rtl.peek()
            if extra is not None:
                mismatches.append((compared, "trace_length", "rtl-more", "golden-eof"))
    for side in ("rtl", "golden"):
        reasons = unpaired_reasons[side]
        reason_text = ",".join(
            f"{reason}:{count}" for reason, count in sorted(reasons.items()))
        print(f"TRACE_COMPARE_UNPAIRED_SUMMARY side={side} "
              f"total={unpaired_records[side]} reasons={reason_text or 'none'}")
    for sample in unpaired_samples:
        print("TRACE_COMPARE_UNPAIRED " + json.dumps(
            sample, sort_keys=True, separators=(",", ":")))

    if mismatches:
        for mismatch in mismatches:
            idx, field, got, expected = mismatch[:4]
            print(f"MISMATCH retire={idx} field={field} rtl={got!r} golden={expected!r}",
                  file=sys.stderr)
            if len(mismatch) >= 6:
                rtl_record, golden_record = mismatch[4:6]
                print(
                    "MISMATCH_CONTEXT "
                    f"rtl_pc={rtl_record.get('pc')!r} "
                    f"rtl_instr={rtl_record.get('instr')!r} "
                    f"rtl_next_pc={rtl_record.get('next_pc')!r} "
                    f"golden_pc={golden_record.get('pc')!r} "
                    f"golden_instr={golden_record.get('instr')!r} "
                    f"golden_next_pc={golden_record.get('next_pc')!r}",
                    file=sys.stderr)
                # Keep the streaming diagnostic bounded while exposing the
                # producer-specific interrupt/exception hand-off around a
                # mismatch.  The live FIFO gate cannot be replayed from a
                # materialized trace after it closes.
                print(
                    "MISMATCH_DETAIL "
                    f"rtl={json.dumps(rtl_record, sort_keys=True, separators=(',', ':'))} "
                    f"golden={json.dumps(golden_record, sort_keys=True, separators=(',', ':'))}",
                    file=sys.stderr)
                if len(mismatch) >= 10:
                    _, _, _, _, _, _, rtl_prev, golden_prev, rtl_next, golden_next = mismatch
                    print(
                        "MISMATCH_NEIGHBORS "
                        f"rtl_prev={json.dumps(rtl_prev, sort_keys=True, separators=(',', ':'))} "
                        f"golden_prev={json.dumps(golden_prev, sort_keys=True, separators=(',', ':'))} "
                        f"rtl_next={json.dumps(rtl_next, sort_keys=True, separators=(',', ':'))} "
                        f"golden_next={json.dumps(golden_next, sort_keys=True, separators=(',', ':'))}",
                        file=sys.stderr)
        return 1
    if (sequence_state["golden"]["first"] != 0 or
            sequence_state["rtl"]["first"] is None):
        raise ValueError(
            "retire sequence origin invalid: "
            f"rtl_first={sequence_state['rtl']['first']} "
            f"golden_first={sequence_state['golden']['first']}")
    rtl_consumed = (sequence_state["rtl"]["last"] -
                    sequence_state["rtl"]["first"] + 1)
    golden_consumed = (sequence_state["golden"]["last"] -
                       sequence_state["golden"]["first"] + 1)
    print("TRACE_COMPARE_SEQUENCE_PASS "
          f"rtl_first={sequence_state['rtl']['first']} "
          f"rtl_last={sequence_state['rtl']['last']} "
          f"golden_first={sequence_state['golden']['first']} "
          f"golden_last={sequence_state['golden']['last']}")
    print(f"TRACE_COMPARE_SYNC_EXCEPTION_PASS count={len(sync_exception_samples)}")
    for sample in sync_exception_samples:
        print("TRACE_COMPARE_SYNC_EXCEPTION " +
              json.dumps(sample, sort_keys=True, separators=(",", ":")))
    suffix = " mode=stream-limit" if limit_reached else " mode=stream"
    print(f"TRACE_COMPARE_PASS records={compared}{suffix} "
          f"rtl_consumed={rtl_consumed} golden_consumed={golden_consumed} "
          f"rtl_unpaired={unpaired_records['rtl']} "
          f"golden_unpaired={unpaired_records['golden']}")
    return 0

def is_mailbox_store(obj):
    return (obj.get("mem_valid") and obj.get("mem_write") and
            normalize_direct_map(obj.get("mem_addr")) == "0000fffc" and
            obj.get("mem_wdata", "").lower() == "deadbeef")

def is_completion_store(obj):
    """Accept the common exit mailbox and the MMU gate's pass marker."""
    if is_mailbox_store(obj):
        return True
    return (obj.get("mem_valid") and obj.get("mem_write") and
            normalize_direct_map(obj.get("mem_addr")) == "0000fff4" and
            obj.get("mem_wdata", "").lower() in ("4d4d5550", "c0030002"))

def is_double_memory_instruction(obj):
    """Current retire schema cannot encode LDC1/SDC1's two word beats."""
    try:
        word = int(obj.get("instr", "0"), 16)
    except (TypeError, ValueError):
        return False
    opcode = (word >> 26) & 0x3f
    if opcode in (0x35, 0x3d):
        return True
    # COP1X indexed double accesses use funct 0x01/0x09.  The plugin reports
    # one 64-bit access while RTL exposes two word beats, just like LDC1/SDC1.
    return opcode == 0x13 and (word & 0x3f) in (0x01, 0x09)


def is_double_store_instruction(obj):
    """True for SDC1 and COP1X double stores with a 64-bit data payload."""
    try:
        word = int(obj.get("instr", "0"), 16)
    except (TypeError, ValueError):
        return False
    opcode = (word >> 26) & 0x3f
    return opcode == 0x3d or (opcode == 0x13 and (word & 0x3f) == 0x09)


def hilo_gpr_word(record, register):
    state = record.get("gpr_state")
    if not isinstance(state, str) or len(state) != 256:
        return None
    offset = (31 - register) * 8
    try:
        return int(state[offset:offset + 8], 16)
    except ValueError:
        return None


def mips32_hilo_valid_mask_after(valid_mask, record, gpr_taint=()):
    """Track which HI/LO halves have defined values after this instruction."""
    try:
        instruction = int(record.get("instr", ""), 16)
    except (TypeError, ValueError):
        return valid_mask
    opcode = (instruction >> 26) & 0x3f
    funct = instruction & 0x3f
    rs = (instruction >> 21) & 0x1f
    rt = (instruction >> 16) & 0x1f

    if opcode == 0x1c:
        if funct == 0x02:
            return 0
        if funct in (0x00, 0x01, 0x04, 0x05):
            return (valid_mask if valid_mask == 0x3 and
                    not ({rs, rt} & gpr_taint) else 0)
    if opcode == 0x00:
        if funct in (0x18, 0x19):
            return 0 if {rs, rt} & gpr_taint else 0x3
        if funct in (0x1a, 0x1b):
            if {rs, rt} & gpr_taint:
                return 0
            dividend = hilo_gpr_word(record, rs)
            divisor = hilo_gpr_word(record, rt)
            if divisor is None or divisor == 0:
                return 0
            if (funct == 0x1a and dividend == 0x80000000 and
                    divisor == 0xffffffff):
                return 0
            return 0x3
        if funct == 0x11:
            return ((valid_mask & ~0x2) if rs in gpr_taint else
                    valid_mask | 0x2)
        if funct == 0x13:
            return ((valid_mask & ~0x1) if rs in gpr_taint else
                    valid_mask | 0x1)
    return valid_mask


def mask_hilo_state(value, valid_mask):
    if not isinstance(value, str) or len(value) != 16:
        return value
    hi = value[:8] if valid_mask & 0x2 else "00000000"
    lo = value[8:] if valid_mask & 0x1 else "00000000"
    return hi + lo


def undefined_hilo_read_destination(record, valid_mask):
    """Return MFHI/MFLO's GPR destination when its source half is undefined."""
    try:
        instruction = int(record.get("instr", ""), 16)
    except (TypeError, ValueError):
        return None
    if (instruction >> 26) & 0x3f:
        return None
    funct = instruction & 0x3f
    if funct == 0x10 and not valid_mask & 0x2:
        destination = (instruction >> 11) & 0x1f
    elif funct == 0x12 and not valid_mask & 0x1:
        destination = (instruction >> 11) & 0x1f
    else:
        return None
    return destination or None


def mips32_gpr_sources(record):
    """Return GPR inputs that can affect this instruction's result or access."""
    try:
        instruction = int(record.get("instr", ""), 16)
    except (TypeError, ValueError):
        return set()
    opcode = (instruction >> 26) & 0x3f
    rs = (instruction >> 21) & 0x1f
    rt = (instruction >> 16) & 0x1f
    funct = instruction & 0x3f
    if opcode == 0:
        if funct in (0x00, 0x02, 0x03):
            return {rt}
        if funct in (0x04, 0x06, 0x07):
            return {rs, rt}
        if funct in (0x08, 0x09, 0x11, 0x13):
            return {rs}
        if funct in (0x10, 0x12, 0x0c, 0x0d, 0x0f):
            return set()
        return {rs, rt}
    if opcode in (0x02, 0x03, 0x0f, 0x10, 0x11, 0x12):
        if opcode in (0x10, 0x11, 0x12) and rs in (0x04, 0x06):
            return {rt}
        return set()
    if opcode == 0x01:
        return {rs}
    if opcode in (0x04, 0x05):
        return {rs, rt}
    if opcode in (0x06, 0x07):
        return {rs}
    if 0x08 <= opcode <= 0x0e:
        return {rs}
    if opcode in (0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
                  0x30, 0x31, 0x34, 0x35, 0x36):
        return {rs}
    if opcode in (0x28, 0x29, 0x2a, 0x2b, 0x2e, 0x38):
        return {rs, rt}
    if opcode in (0x1c, 0x1f):
        return {rs, rt}
    return set()


def memory_access_byte_addresses(record):
    """Return the byte addresses touched by a traced MIPS memory operation."""
    if not record.get("mem_valid") or not (record.get("mem_read") or
                                            record.get("mem_write")):
        return set()
    try:
        instruction = int(record.get("instr", ""), 16)
        address = int(normalize_direct_map(record.get("mem_addr", "")), 16)
    except (TypeError, ValueError):
        return set()
    opcode = (instruction >> 26) & 0x3f
    widths = {
        0x20: 1, 0x24: 1, 0x28: 1,
        0x21: 2, 0x25: 2, 0x29: 2,
        0x22: 4, 0x23: 4, 0x26: 4, 0x27: 4,
        0x2a: 4, 0x2b: 4, 0x2e: 4, 0x30: 4, 0x38: 4,
        0x31: 4, 0x39: 4, 0x35: 8, 0x3d: 8,
    }
    width = widths.get(opcode)
    if width is None:
        return set()
    if opcode in (0x22, 0x26, 0x2a, 0x2e):
        address &= ~0x3
        width = 4
    return {normalize_direct_map(f"{(address + offset) & 0xffffffff:08x}")
            for offset in range(width)}


def memory_store_value_tainted(record, gpr_taint):
    try:
        instruction = int(record.get("instr", ""), 16)
    except (TypeError, ValueError):
        return False
    opcode = (instruction >> 26) & 0x3f
    if opcode not in (0x28, 0x29, 0x2a, 0x2b, 0x2e, 0x38):
        return False
    return ((instruction >> 16) & 0x1f) in gpr_taint


def memory_address_tainted(record, gpr_taint):
    if not memory_access_byte_addresses(record):
        return False
    try:
        instruction = int(record.get("instr", ""), 16)
    except (TypeError, ValueError):
        return False
    return ((instruction >> 21) & 0x1f) in gpr_taint


def memory_load_value_tainted(record, memory_taint):
    return (bool(record.get("mem_read")) and
            bool(memory_access_byte_addresses(record) & memory_taint))


def memory_taint_after_record(memory_taint, record, gpr_taint):
    updated = set(memory_taint)
    if not record.get("mem_valid") or not record.get("mem_write"):
        return updated
    addresses = memory_access_byte_addresses(record)
    if not addresses:
        return updated
    if (memory_store_value_tainted(record, gpr_taint) or
            memory_address_tainted(record, gpr_taint)):
        updated.update(addresses)
    else:
        updated.difference_update(addresses)
    return updated


def hilo_gpr_taint_after_write(tainted, memory_taint, record, valid_mask):
    """Track GPR values derived from undefined HI/LO or tainted GPR/memory."""
    updated = set(tainted)
    destination = gpr_write_destination(record)
    if destination is not None:
        updated.discard(destination)
    undefined_destination = undefined_hilo_read_destination(record, valid_mask)
    if destination is not None and (
            undefined_destination is not None or
            bool(mips32_gpr_sources(record) & tainted) or
            memory_load_value_tainted(record, memory_taint)):
        updated.add(destination)
    return updated


def mask_gpr_registers(value, registers):
    """Mask full GPR words whose architectural values are undefined."""
    if not isinstance(value, str) or len(value) != 256:
        return value
    normalized = value.lower()
    for register in registers:
        offset = (31 - register) * 8
        normalized = (normalized[:offset] + "00000000" +
                      normalized[offset + 8:])
    return normalized


def is_async_interrupt_boundary(obj):
    """True when a trace producer attached an async IRQ to this retire.

    QEMU reports the accepted interrupt on the instruction immediately before
    the vector fetch. The RTL writeback trace observes that instruction's
    sequential next PC and starts the following record at the vector. Both
    streams still contain and commit the same instruction; only the redirect
    and exception metadata lack a common single-record representation.
    """
    return obj.get("except") and obj.get("except_code") == 0


def async_boundary_reaches(record, pc):
    """Whether an async exception record redirects to the peer's current PC."""
    next_pc = record.get("next_pc")
    return (is_async_interrupt_boundary(record) and
            isinstance(next_pc, str) and isinstance(pc, str) and
            normalize_direct_map(next_pc) == normalize_direct_map(pc))


def is_synchronous_exception(obj):
    return bool(obj.get("except")) and not is_async_interrupt_boundary(obj)


def sync_exception_reaches(record, pc):
    """Whether a synchronous exception redirects to the peer's current PC."""
    next_pc = record.get("next_pc")
    return (is_synchronous_exception(record) and
            isinstance(next_pc, str) and isinstance(pc, str) and
            normalize_direct_map(next_pc) == pc)


def validate_rtl_sync_exception_state(rtl_record, qemu_handler_record):
    """Check RTL exception metadata against QEMU's handler-entry CP0 state."""
    try:
        cause = int(qemu_handler_record["qemu_cause"], 16)
        qemu_epc = int(qemu_handler_record["qemu_epc"], 16)
        rtl_code = int(rtl_record["except_code"])
        rtl_bd = int(rtl_record["bd"])
        rtl_pc = int(rtl_record["pc"], 16)
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(
            "synchronous exception redirect lacks RTL or QEMU Cause/EPC "
            "evidence") from exc

    expected_epc = (rtl_pc - (4 if rtl_bd else 0)) & 0xffffffff
    checks = (
        ("except_code", (cause >> 2) & 0x1f, rtl_code),
        ("bd", (cause >> 31) & 1, rtl_bd),
        ("epc", qemu_epc, expected_epc),
    )
    mismatches = [(field, observed, expected)
                  for field, observed, expected in checks
                  if observed != expected]
    if mismatches:
        details = ", ".join(
            f"{field}:QEMU={observed:08x}/RTL={expected:08x}"
            for field, observed, expected in mismatches)
        raise ValueError(
            "synchronous exception redirect state mismatch at RTL retire "
            f"{rtl_record.get('retire_seq')}: {details}")
    return {
        "rtl_retire_seq": rtl_record.get("retire_seq"),
        "rtl_pc": f"{rtl_pc:08x}",
        "except_code": rtl_code,
        "bd": rtl_bd,
        "epc": f"{expected_epc:08x}",
        "qemu_cause": f"{cause:08x}",
        "qemu_epc": f"{qemu_epc:08x}",
    }


def deferred_eret_target_fetch_exception(r, g, r_next, g_next):
    """Match a fetch fault QEMU reports on ERET to RTL's following record."""
    if (not r.get("eret") or not g.get("eret") or
            r.get("pc") != g.get("pc") or
            r.get("instr") != g.get("instr") or
            r.get("next_pc") != g.get("next_pc") or
            bool(r.get("except")) == bool(g.get("except"))):
        return False

    exception_event = r if r.get("except") else g
    faulting_peer = g_next if r.get("except") else r_next
    handler_peer = r_next if r.get("except") else g_next
    if (not is_synchronous_exception(exception_event) or
            faulting_peer is None or handler_peer is None or
            not is_synchronous_exception(faulting_peer)):
        return False

    try:
        same_exception = (
            int(exception_event.get("except_code", -1)) ==
            int(faulting_peer.get("except_code", -2)) and
            int(exception_event.get("bd", 0)) ==
            int(faulting_peer.get("bd", 0)))
    except (TypeError, ValueError):
        return False
    return (same_exception and
            normalize_direct_map(faulting_peer.get("pc")) ==
            normalize_direct_map(r.get("next_pc")) and
            normalize_direct_map(faulting_peer.get("next_pc")) ==
            normalize_direct_map(handler_peer.get("pc")))


def enters_general_exception_vector(records, index):
    """Detect a redirect represented between two retire records.

    The two producers can attach the CP0 Cause/IP side effect to different
    instructions. The architectural invariant is instead the following
    executed instruction at the general exception vector.
    """
    if index + 1 >= len(records):
        return False
    next_pc = normalize_direct_map(records[index][1].get("next_pc"))
    following_pc = normalize_direct_map(records[index + 1][1].get("pc"))
    return following_pc == "00000180" and (
        next_pc == "00000180" or following_pc == "00000180")

def follows_async_interrupt_boundary(records, index):
    """Identify the short producer-specific interrupt redirect window.

    QEMU records an accepted level interrupt on the retirement that observes
    it.  In a branch/jump delay-slot sequence, the QEMU next-PC redirect can
    consequently be attached to either of the following two retire records.
    RTL retires that delay slot with its sequential next PC and exposes the
    vector fetch on the next record.  Both representations execute the same
    instructions and memory operations, but no single `next_pc` field is
    common across this bounded hand-off window.
    """
    first = max(0, index - 2)
    return any(is_async_interrupt_boundary(records[candidate][1])
               for candidate in range(first, index + 1))

def has_delay_slot(instr):
    """Return whether an implemented MIPS32 instruction owns a delay slot."""
    if not isinstance(instr, str):
        return False
    try:
        word = int(instr, 16)
    except ValueError:
        return False
    opcode = (word >> 26) & 0x3f
    if opcode in (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                  0x14, 0x15, 0x16, 0x17):
        return True
    if opcode == 0x00 and (word & 0x3f) in (0x08, 0x09):
        return True  # JR/JALR
    return opcode in (0x11, 0x12, 0x13) and ((word >> 21) & 0x1f) == 0x08

def is_side_effect_free_control_transfer(obj):
    """Check an async-window control transfer before allowing it to be skipped."""
    return (has_delay_slot(obj.get("instr")) and
            not obj.get("gpr_we") and
            not comparable_cp0_write(obj) and
            not obj.get("mem_valid"))

def follows_delay_slot(records, index):
    return index > 0 and has_delay_slot(records[index - 1][1].get("instr"))

def is_merge_memory_instruction(obj):
    """Merge loads expose formatted data in RTL but raw bus data in QEMU."""
    try:
        word = int(obj.get("instr", ""), 16)
    except (TypeError, ValueError):
        return False
    return ((word >> 26) & 0x3f) in (0x22, 0x26, 0x2a, 0x2e)

def is_narrow_load(obj):
    """Byte/half loads expose raw QEMU bus data but extended RTL data."""
    try:
        opcode = (int(obj.get("instr", ""), 16) >> 26) & 0x3f
    except (TypeError, ValueError):
        return False
    return opcode in (0x20, 0x21, 0x24, 0x25)

def truncate_at_mailbox(records):
    for index, record in enumerate(records):
        if is_completion_store(record[1]):
            return records[:index + 1]
    raise ValueError("completion store was not present in trace")


def align_async_vector_window(rtl, golden):
    """Align a one-retire IRQ observation window before field comparison.

    The RTL may retire the sequential instruction after enabling interrupts
    before sampling the pending line, while QEMU can redirect immediately at
    the preceding retire boundary. Both streams then contain the same vector
    and handler instructions, but one stream has one extra async boundary
    record. Drop only that record when its redirect PC is the peer's current
    PC.
    """
    aligned_rtl = []
    aligned_golden = []
    ri = gi = 0
    vector = "00000180"
    while ri < len(rtl) and gi < len(golden):
        rtl_pc = normalize_direct_map(rtl[ri][1].get("pc"))
        golden_pc = normalize_direct_map(golden[gi][1].get("pc"))
        if (gi + 1 < len(golden) and
                async_boundary_reaches(golden[gi + 1][1], rtl_pc) and
                is_side_effect_free_control_transfer(golden[gi][1])):
            gi += 1
            continue
        if (ri + 1 < len(rtl) and
                async_boundary_reaches(rtl[ri + 1][1], golden_pc) and
                is_side_effect_free_control_transfer(rtl[ri][1])):
            ri += 1
            continue
        if async_boundary_reaches(golden[gi][1], rtl_pc):
            gi += 1
            continue
        if async_boundary_reaches(rtl[ri][1], golden_pc):
            ri += 1
            continue
        if golden_pc == vector and rtl_pc != vector and ri + 1 < len(rtl):
            if normalize_direct_map(rtl[ri + 1][1].get("pc")) == vector:
                ri += 1
                continue
        if rtl_pc == vector and golden_pc != vector and gi + 1 < len(golden):
            if normalize_direct_map(golden[gi + 1][1].get("pc")) == vector:
                gi += 1
                continue
        aligned_rtl.append(rtl[ri])
        aligned_golden.append(golden[gi])
        ri += 1
        gi += 1
    aligned_rtl.extend(rtl[ri:])
    aligned_golden.extend(golden[gi:])
    return aligned_rtl, aligned_golden


def align_synchronous_exception_window(rtl, golden):
    """Drop only the producer-specific fault record at a matching redirect.

    RTL emits the faulting instruction with exception metadata. QEMU's retire
    plugin resumes at the first handler instruction, so the common boundary
    is established when the RTL exception's next PC equals QEMU's current PC.
    """
    aligned_rtl = []
    aligned_golden = []
    ri = gi = 0
    while ri < len(rtl) and gi < len(golden):
        if (ri + 1 < len(rtl) and gi + 1 < len(golden) and
                deferred_eret_target_fetch_exception(
                    rtl[ri][1], golden[gi][1], rtl[ri + 1][1],
                    golden[gi + 1][1])):
            rtl_line, rtl_record = rtl[ri]
            golden_line, golden_record = golden[gi]
            rtl_record = dict(rtl_record)
            golden_record = dict(golden_record)
            rtl_record["_deferred_eret_fetch_exception"] = True
            golden_record["_deferred_eret_fetch_exception"] = True
            aligned_rtl.append((rtl_line, rtl_record))
            aligned_golden.append((golden_line, golden_record))
            ri += 1
            gi += 1
            continue
        rtl_pc = normalize_direct_map(rtl[ri][1].get("pc"))
        golden_pc = normalize_direct_map(golden[gi][1].get("pc"))
        if sync_exception_reaches(rtl[ri][1], golden_pc):
            ri += 1
            continue
        if sync_exception_reaches(golden[gi][1], rtl_pc):
            gi += 1
            continue
        aligned_rtl.append(rtl[ri])
        aligned_golden.append(golden[gi])
        ri += 1
        gi += 1
    aligned_rtl.extend(rtl[ri:])
    aligned_golden.extend(golden[gi:])
    return aligned_rtl, aligned_golden


def align_first_retire(rtl, golden, pc):
    """Drop a producer-specific prefix at an explicit architectural handoff.

    A boot-ROM-backed RTL run retires its ROM instructions before entering a
    kernel that QEMU receives through ``-kernel``.  Prefix removal is allowed
    only when the first golden record and an RTL record have the same PC and
    instruction, so this option cannot turn an arbitrary mismatch into an
    alignment.  All records after the handoff remain subject to normal
    comparison, including the length check.
    """
    if not golden:
        raise ValueError("cannot align an empty golden trace")
    try:
        wanted_pc = normalize_direct_map(f"{int(pc, 16) & 0xffffffff:08x}")
    except ValueError as exc:
        raise ValueError(f"invalid alignment PC: {pc!r}") from exc
    golden_first = golden[0][1]
    if normalize_direct_map(golden_first.get("pc")) != wanted_pc:
        raise ValueError(
            "golden trace first PC does not match --align-first-pc: "
            f"{golden_first.get('pc')!r} != {wanted_pc!r}")
    for index, (_, record) in enumerate(rtl):
        if (normalize_direct_map(record.get("pc")) == wanted_pc and
                record.get("instr") == golden_first.get("instr")):
            return rtl[index:], golden
    raise ValueError(
        "RTL trace has no matching PC/instruction handoff for "
        f"{wanted_pc} / {golden_first.get('instr')}")


def fpu_state_matches_window(rtl, golden, index, field, radius=12):
    """Match FPU state across the bounded ID-to-WB observation latency.

    The RTL commits FPR/FCSR in ID while the common retire record is sampled
    from MEM/WB. Cache and exception stalls can move that observation by a few
    retire records. FPR writes can be observed independently because adjacent
    ID commits can overtake the later WB observation by one instruction, so
    each 32-bit FPR lane is matched to the corresponding lane in the bounded
    RTL window. FCSR remains a complete packed-state match. This is not a
    general trace resynchronization mechanism.
    """
    expected = golden[index][1].get(field)
    if expected is None:
        return True
    start = max(0, index - radius)
    stop = min(len(rtl), index + radius + 1)
    if field == "fcsr_state":
        return any(rtl[candidate][1].get(field) == expected
                   for candidate in range(start, stop))
    if field != "fpr_state" or len(expected) != 256:
        return any(rtl[candidate][1].get(field) == expected
                   for candidate in range(start, stop))
    for lane_start in range(0, 256, 8):
        lane = expected[lane_start:lane_start + 8]
        if not any((rtl[candidate][1].get(field) or "")[lane_start:lane_start + 8] == lane
                   for candidate in range(start, stop)):
            return False
    return True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rtl")
    ap.add_argument("golden")
    ap.add_argument("--max-mismatches", type=int, default=1)
    ap.add_argument("--stop-after-mailbox", action="store_true")
    ap.add_argument("--align-first-pc", metavar="PC",
                    help="align the first golden retire at an exact RTL PC/instruction")
    ap.add_argument("--allow-golden-prefix", action="store_true",
                    help="accept a fully matching golden prefix when RTL has extra records")
    ap.add_argument("--truncate-golden-to-rtl", action="store_true",
                    help="after alignment, compare only the golden prefix available in the RTL trace")
    ap.add_argument("--stream", action="store_true",
                    help="compare line-by-line with bounded memory for long traces")
    ap.add_argument("--fast-linux", action="store_true",
                    help="use the optimized schema-1 Linux stream comparator")
    ap.add_argument("--limit", type=int,
                    help="compare exactly this many records from each stream")
    args = ap.parse_args()
    if args.limit is not None and args.limit <= 0:
        ap.error("--limit must be a positive integer")
    if args.stream:
        try:
            if args.fast_linux:
                return fast_linux_stream_compare(args.rtl, args.golden, args)
            return stream_compare(args.rtl, args.golden, args)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"TRACE_COMPARE_ERROR: {exc}", file=sys.stderr)
            return 2
    try:
        rtl = list(load(args.rtl))
        golden = list(load(args.golden))
        for side, records in (("rtl", rtl), ("golden", golden)):
            for number, record in records:
                validate_trace_record(record, side, number)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"TRACE_COMPARE_ERROR: {exc}", file=sys.stderr)
        return 2
    if args.stop_after_mailbox:
        rtl = truncate_at_mailbox(rtl)
        golden = truncate_at_mailbox(golden)
    if args.align_first_pc:
        rtl, golden = align_first_retire(rtl, golden, args.align_first_pc)
    rtl, golden = align_synchronous_exception_window(rtl, golden)
    rtl, golden = align_async_vector_window(rtl, golden)
    if args.truncate_golden_to_rtl:
        # Linux RTL runs are cycle-bounded while QEMU capture is wall-clock
        # bounded.  The handoff alignment above may also remove a producer
        # prefix, so derive the common compare length after both operations.
        golden = golden[:len(rtl)]
    mismatches = []
    index_taint = {"rtl": set(), "golden": set()}
    hilo_gpr_taint = {"rtl": set(), "golden": set()}
    memory_taint = {"rtl": set(), "golden": set()}
    hilo_valid_mask = {"rtl": 0x3, "golden": 0x3}
    vector_alias_window = False
    for idx, (r, g) in enumerate(zip(rtl, golden)):
        rtl_hilo_valid_after = mips32_hilo_valid_mask_after(
            hilo_valid_mask["rtl"], r[1], hilo_gpr_taint["rtl"])
        golden_hilo_valid_after = mips32_hilo_valid_mask_after(
            hilo_valid_mask["golden"], g[1], hilo_gpr_taint["golden"])
        comparable_hilo_valid = rtl_hilo_valid_after & golden_hilo_valid_after
        rtl_hilo_read_destination = undefined_hilo_read_destination(
            r[1], hilo_valid_mask["rtl"])
        golden_hilo_read_destination = undefined_hilo_read_destination(
            g[1], hilo_valid_mask["golden"])
        rtl_hilo_gpr_taint_after = hilo_gpr_taint_after_write(
            hilo_gpr_taint["rtl"], memory_taint["rtl"], r[1],
            hilo_valid_mask["rtl"])
        golden_hilo_gpr_taint_after = hilo_gpr_taint_after_write(
            hilo_gpr_taint["golden"], memory_taint["golden"], g[1],
            hilo_valid_mask["golden"])
        comparable_hilo_gpr_taint = (rtl_hilo_gpr_taint_after |
                                     golden_hilo_gpr_taint_after)
        if is_exception_vector_alias_pair(r[1].get("pc"), g[1].get("pc")):
            vector_alias_window = True
        rtl_state_taint = index_taint_for_state(index_taint["rtl"], r[1])
        golden_state_taint = index_taint_for_state(index_taint["golden"], g[1])
        comparable_state_taint = rtl_state_taint & golden_state_taint
        fields = list(BASE_FIELDS)
        if is_async_interrupt_boundary(r[1]) or is_async_interrupt_boundary(g[1]):
            fields = [field for field in fields
                      if field not in ("next_pc", "except", "except_code", "bd")]
        if enters_general_exception_vector(rtl, idx) or \
           enters_general_exception_vector(golden, idx) or \
           follows_async_interrupt_boundary(rtl, idx) or \
           follows_async_interrupt_boundary(golden, idx) or \
           follows_delay_slot(rtl, idx) or \
           follows_delay_slot(golden, idx) or \
           has_delay_slot(r[1].get("instr")) or \
           has_delay_slot(g[1].get("instr")):
            fields = [field for field in fields if field not in ("next_pc", "bd")]
        if r[1].get("gpr_we") or g[1].get("gpr_we"):
            fields += ["gpr_we", "gpr_addr", "gpr_data"]
        if (rtl_hilo_read_destination is not None or
                golden_hilo_read_destination is not None or
                gpr_write_destination(r[1]) in rtl_hilo_gpr_taint_after or
                gpr_write_destination(g[1]) in golden_hilo_gpr_taint_after):
            fields = [field for field in fields if field != "gpr_data"]
        rtl_mem_address_tainted = memory_address_tainted(
            r[1], hilo_gpr_taint["rtl"])
        golden_mem_address_tainted = memory_address_tainted(
            g[1], hilo_gpr_taint["golden"])
        rtl_store_value_tainted = memory_store_value_tainted(
            r[1], hilo_gpr_taint["rtl"])
        golden_store_value_tainted = memory_store_value_tainted(
            g[1], hilo_gpr_taint["golden"])
        rtl_load_value_tainted = memory_load_value_tainted(
            r[1], memory_taint["rtl"])
        golden_load_value_tainted = memory_load_value_tainted(
            g[1], memory_taint["golden"])
        if rtl_mem_address_tainted or golden_mem_address_tainted:
            fields = [field for field in fields if field != "mem_addr"]
        if (rtl_store_value_tainted or golden_store_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields
                      if field not in ("mem_wdata", "mem_wdata_hi")]
        if (rtl_load_value_tainted or golden_load_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields if field != "mem_rdata"]
        if (r[1].get("_deferred_eret_fetch_exception") and
                g[1].get("_deferred_eret_fetch_exception")):
            fields = [field for field in fields
                      if field not in ("except", "except_code")]
        if comparable_cp0_write(r[1]) or comparable_cp0_write(g[1]):
            fields += ["cp0_we", "cp0_addr", "cp0_sel", "cp0_data"]
        if r[1].get("fpr_state") is not None or g[1].get("fpr_state") is not None:
            fields += ["fpr_state", "fcsr_state"]
        if r[1].get("schema", "").lower() == "00020000" or \
                g[1].get("schema", "").lower() == "00020000":
            fields += ["gpr_state", "hilo_state"]
        if r[1].get("mem_valid") or g[1].get("mem_valid"):
            fields += ["mem_valid", "mem_read", "mem_write", "mem_addr", "mem_be"]
            if r[1].get("mem_write") or g[1].get("mem_write"):
                fields.append("mem_wdata")
                if (is_double_store_instruction(r[1]) or
                        is_double_store_instruction(g[1])):
                    fields.append("mem_wdata_hi")
            if r[1].get("mem_read") or g[1].get("mem_read"):
                fields.append("mem_rdata")
            # RTL observes the cache-line word enable while QEMU reports the
            # guest access lane/size mask (for example f versus 1/2/4).  The
            # architectural address, direction, and data are compared above;
            # this producer-specific bus encoding is not a differential field.
            fields.remove("mem_be")
            # A synchronous fault is reported at different observation
            # points: RTL retains the attempted bus request, while QEMU's
            # plugin suppresses the faulting access callback.  The common
            # architectural evidence is the retired instruction and
            # exception payload, so do not require producer-specific memory
            # fields on the exception boundary.
            if (is_synchronous_exception(r[1]) or
                    is_synchronous_exception(g[1])):
                if r[1].get("mem_valid") and g[1].get("mem_valid"):
                    fields = [field for field in fields
                              if field not in ("mem_wdata", "mem_wdata_hi",
                                               "mem_rdata")]
                else:
                    fields = [field for field in fields if field not in
                              ("mem_valid", "mem_read", "mem_write", "mem_addr",
                               "mem_wdata", "mem_wdata_hi", "mem_rdata")]
        if is_merge_memory_instruction(r[1]) or is_merge_memory_instruction(g[1]):
            # The architectural result is gpr_data.  The RTL observation
            # reports merge-formatted data, while QEMU reports the raw aligned
            # bus word for this instruction class.
            fields = [field for field in fields if field != "mem_rdata"]
        if is_narrow_load(r[1]) or is_narrow_load(g[1]):
            # QEMU exposes raw byte/halfword data; RTL exposes the formatted
            # sign/zero-extended load result. Compare that result via gpr_data.
            fields = [field for field in fields if field != "mem_rdata"]
        if is_double_memory_instruction(r[1]) or is_double_memory_instruction(g[1]):
            # The loaded pair is checked through FPR state; store data is
            # compared as the low/high words above.
            fields = [field for field in fields if field != "mem_rdata"]
        if rtl_mem_address_tainted or golden_mem_address_tainted:
            fields = [field for field in fields if field != "mem_addr"]
        if (rtl_store_value_tainted or golden_store_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields
                      if field not in ("mem_wdata", "mem_wdata_hi")]
        if (rtl_load_value_tainted or golden_load_value_tainted or
                rtl_mem_address_tainted or golden_mem_address_tainted):
            fields = [field for field in fields if field != "mem_rdata"]
        missing_double_store_hi = (
            not is_synchronous_exception(r[1]) and
            not is_synchronous_exception(g[1]) and
            ((is_double_store_instruction(r[1]) and r[1].get("mem_write")) or
             (is_double_store_instruction(g[1]) and g[1].get("mem_write"))) and
            ("mem_wdata_hi" not in r[1] or "mem_wdata_hi" not in g[1]))
        if missing_double_store_hi:
            mismatches.append((idx, "mem_wdata_hi",
                               r[1].get("mem_wdata_hi", "<missing>"),
                               g[1].get("mem_wdata_hi", "<missing>")))
            break
        for field in fields:
            got = comparable_record_field(
                field, r[1], r[1].get(field), peer=g[1],
                vector_alias_window=vector_alias_window)
            expected = comparable_record_field(
                field, g[1], g[1].get(field), peer=r[1],
                vector_alias_window=vector_alias_window)
            if field == "gpr_state":
                got = mask_index_miss_gprs(got, comparable_state_taint)
                expected = mask_index_miss_gprs(expected,
                                                comparable_state_taint)
                got = mask_gpr_registers(got, comparable_hilo_gpr_taint)
                expected = mask_gpr_registers(expected,
                                              comparable_hilo_gpr_taint)
            if field == "hilo_state":
                got = mask_hilo_state(got, comparable_hilo_valid)
                expected = mask_hilo_state(expected, comparable_hilo_valid)
            if field in ("fpr_state", "fcsr_state"):
                if fpu_state_matches_window(rtl, golden, idx, field):
                    continue
            if got != expected:
                mismatches.append((idx, field, r[1].get(field), g[1].get(field)))
                break
        index_taint["rtl"] = index_taint_after_write(index_taint["rtl"], r[1])
        index_taint["golden"] = index_taint_after_write(index_taint["golden"], g[1])
        memory_taint["rtl"] = memory_taint_after_record(
            memory_taint["rtl"], r[1], hilo_gpr_taint["rtl"])
        memory_taint["golden"] = memory_taint_after_record(
            memory_taint["golden"], g[1], hilo_gpr_taint["golden"])
        hilo_gpr_taint["rtl"] = rtl_hilo_gpr_taint_after
        hilo_gpr_taint["golden"] = golden_hilo_gpr_taint_after
        hilo_valid_mask["rtl"] = rtl_hilo_valid_after
        hilo_valid_mask["golden"] = golden_hilo_valid_after
        if r[1].get("eret") or g[1].get("eret"):
            vector_alias_window = False
        if len(mismatches) >= args.max_mismatches:
            break
    if (len(rtl) != len(golden) and not
            (args.allow_golden_prefix and len(rtl) >= len(golden)) and
            len(mismatches) < args.max_mismatches):
        mismatches.append((min(len(rtl), len(golden)), "trace_length", len(rtl), len(golden)))
    if mismatches:
        for idx, field, got, expected in mismatches:
            print(f"MISMATCH retire={idx} field={field} rtl={got!r} golden={expected!r}", file=sys.stderr)
        return 1
    compared_records = min(len(rtl), len(golden))
    if args.allow_golden_prefix and len(rtl) != len(golden):
        print(f"TRACE_COMPARE_PASS records={compared_records} "
              f"rtl_records={len(rtl)} golden_records={len(golden)} "
              "mode=golden-prefix")
    else:
        print(f"TRACE_COMPARE_PASS records={compared_records}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
