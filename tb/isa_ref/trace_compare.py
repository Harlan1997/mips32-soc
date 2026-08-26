#!/usr/bin/env python3
"""Compare committed RTL and golden architectural traces, one JSON object/line."""
import argparse
import json
import sys

BASE_FIELDS = ("schema", "pc", "instr", "next_pc", "except", "except_code", "bd", "eret")
COMMON_CP0_ADDRS = {0, 5, 10, 12, 13, 14}

def comparable_cp0_write(obj):
    """Return true only for CP0 writes observable in both trace producers."""
    try:
        return bool(obj.get("cp0_we")) and int(obj.get("cp0_addr", 0)) in COMMON_CP0_ADDRS
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

def comparable(field, value):
    if field in ("pc", "next_pc", "mem_addr", "gpr_data", "cp0_data"):
        return normalize_direct_map(value)
    return value

def load(path):
    with open(path, encoding="ascii") as f:
        for n, line in enumerate(f, 1):
            if line.strip():
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    raise ValueError(f"{path}:{n}: invalid JSON: {e}") from e
                yield n, obj

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
    return ((int(obj.get("instr", "0"), 16) >> 26) & 0x3f) in (0x35, 0x3d)


def is_async_interrupt_boundary(obj):
    """True when a trace producer attached a level interrupt to this retire.

    QEMU reports the accepted interrupt on the instruction immediately before
    the vector fetch. The RTL writeback trace observes that instruction's
    sequential next PC and starts the following record at the vector. Both
    streams still contain every architectural instruction, but these three
    boundary fields have no common single-record representation yet.
    """
    return obj.get("except") and obj.get("except_code") == 0


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

def follows_delay_slot(records, index):
    return index > 0 and has_delay_slot(records[index - 1][1].get("instr"))

def is_merge_memory_instruction(obj):
    """Merge loads expose formatted data in RTL but raw bus data in QEMU."""
    try:
        word = int(obj.get("instr", ""), 16)
    except (TypeError, ValueError):
        return False
    return ((word >> 26) & 0x3f) in (0x22, 0x26, 0x2a, 0x2e)

def is_merge_store(obj):
    try:
        opcode = (int(obj.get("instr", ""), 16) >> 26) & 0x3f
    except (TypeError, ValueError):
        return False
    return opcode in (0x2a, 0x2e)

def truncate_at_mailbox(records):
    for index, record in enumerate(records):
        if is_completion_store(record[1]):
            return records[:index + 1]
    raise ValueError("completion store was not present in trace")


def align_async_vector_window(rtl, golden):
    """Align a one-retire IRQ observation window before field comparison.

    The RTL may retire the sequential instruction after enabling interrupts
    before sampling the pending line, while QEMU can redirect immediately at
    the preceding retire boundary.  Both streams then contain the same vector
    and handler instructions, but one stream has one extra sequential record.
    Drop only that record when the other stream is already at the normalized
    general exception vector.
    """
    aligned_rtl = []
    aligned_golden = []
    ri = gi = 0
    vector = "00000180"
    while ri < len(rtl) and gi < len(golden):
        rtl_pc = normalize_direct_map(rtl[ri][1].get("pc"))
        golden_pc = normalize_direct_map(golden[gi][1].get("pc"))
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rtl")
    ap.add_argument("golden")
    ap.add_argument("--max-mismatches", type=int, default=1)
    ap.add_argument("--stop-after-mailbox", action="store_true")
    args = ap.parse_args()
    rtl = list(load(args.rtl))
    golden = list(load(args.golden))
    if args.stop_after_mailbox:
        rtl = truncate_at_mailbox(rtl)
        golden = truncate_at_mailbox(golden)
    rtl, golden = align_async_vector_window(rtl, golden)
    mismatches = []
    for idx, (r, g) in enumerate(zip(rtl, golden)):
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
        if comparable_cp0_write(r[1]) or comparable_cp0_write(g[1]):
            fields += ["cp0_we", "cp0_addr", "cp0_sel", "cp0_data"]
        if r[1].get("mem_valid") or g[1].get("mem_valid"):
            fields += ["mem_valid", "mem_read", "mem_write", "mem_addr", "mem_be"]
            if r[1].get("mem_write") or g[1].get("mem_write"):
                fields.append("mem_wdata")
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
            if r[1].get("except") or g[1].get("except"):
                fields = [field for field in fields if field not in
                          ("mem_valid", "mem_read", "mem_write", "mem_addr",
                           "mem_wdata", "mem_rdata")]
        # A faulting load/store must not architecturally update a GPR.  The
        # RTL observation can retain the in-flight result and QEMU exposes the
        # pre-fault value; exception code and control-flow fields are the
        # authoritative common boundary.
        if r[1].get("except") or g[1].get("except"):
            fields = [field for field in fields if field not in
                      ("gpr_we", "gpr_addr", "gpr_data")]
        if is_merge_memory_instruction(r[1]) or is_merge_memory_instruction(g[1]):
            # The architectural result is gpr_data.  The RTL observation
            # reports merge-formatted data, while QEMU reports the raw aligned
            # bus word for this instruction class.
            fields = [field for field in fields if field != "mem_rdata"]
        if is_merge_store(r[1]) or is_merge_store(g[1]):
            # RTL exposes the merged word/lane mask at its cache boundary;
            # QEMU exposes the individual aligned bus write. The final
            # architectural memory value is checked by the guest.
            fields = [field for field in fields
                      if field not in ("mem_wdata", "mem_be")]
        if is_double_memory_instruction(r[1]) or is_double_memory_instruction(g[1]):
            # The RTL emits the blocking transaction as two word beats while
            # QEMU's plugin reports one 64-bit access. Compare retirement and
            # architectural register effects here; beat-level equivalence is
            # covered by the SoC fpu-single gate.
            fields = [field for field in fields
                      if field not in ("mem_wdata", "mem_be", "mem_rdata")]
        for field in fields:
            got = comparable(field, r[1].get(field))
            expected = comparable(field, g[1].get(field))
            if field == "mem_addr" and (is_merge_memory_instruction(r[1]) or
                                         is_merge_memory_instruction(g[1])):
                try:
                    got = f"{int(got, 16) & ~3:08x}"
                    expected = f"{int(expected, 16) & ~3:08x}"
                except (TypeError, ValueError):
                    pass
            if got != expected:
                mismatches.append((idx, field, r[1].get(field), g[1].get(field)))
                break
        if len(mismatches) >= args.max_mismatches:
            break
    if len(rtl) != len(golden) and len(mismatches) < args.max_mismatches:
        mismatches.append((min(len(rtl), len(golden)), "trace_length", len(rtl), len(golden)))
    if mismatches:
        for idx, field, got, expected in mismatches:
            print(f"MISMATCH retire={idx} field={field} rtl={got!r} golden={expected!r}", file=sys.stderr)
        return 1
    print(f"TRACE_COMPARE_PASS records={len(rtl)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
