#!/usr/bin/env python3
"""Convert QEMU system-mode plugin state/event streams to retire JSONL."""
import argparse
import json
import os
import sys

def iter_jsonl(path):
    """Yield JSONL records without retaining the capture in memory."""
    with open(path, encoding="ascii") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{number}: invalid JSON: {exc}") from exc


class StateWindow:
    """Three-record state window used by the streaming converter."""

    streaming = True

    def __init__(self, path):
        self._records = iter_jsonl(path)
        self.position = 0
        try:
            self.current = next(self._records)
            self.next = next(self._records)
        except StopIteration as exc:
            raise ValueError(f"state stream {path} needs at least two records") from exc
        self.previous = None

    def advance(self):
        self.previous = self.current
        self.current = self.next
        try:
            self.next = next(self._records)
        except StopIteration:
            self.next = None
        self.position += 1

    def __getitem__(self, index):
        if index == self.position:
            value = self.current
        elif index == self.position - 1:
            value = self.previous
        elif index == self.position + 1:
            value = self.next
        else:
            raise IndexError(f"streaming state window cannot access index {index}")
        if value is None:
            raise ValueError("state stream ended before events + post-state")
        return value


class EventWindow:
    """Stream events while keeping the previous/current event pair."""

    streaming = True

    def __init__(self, path, states):
        self._records = iter_jsonl(path)
        self.states = states
        self.position = -1
        self.current = None
        self.previous = None

    def __iter__(self):
        return self

    def __next__(self):
        event = next(self._records)
        self.previous = self.current
        self.current = event
        self.position += 1
        if self.position:
            self.states.advance()
        return event

    def __getitem__(self, index):
        if index == self.position:
            return self.current
        if index == self.position - 1:
            return self.previous
        raise IndexError(f"streaming event window cannot access index {index}")


def hex32(value):
    if isinstance(value, int):
        return f"{value & 0xffffffff:08x}"
    return f"{int(value, 16) & 0xffffffff:08x}"


def effective_address(instr, before):
    rs = (instr >> 21) & 0x1f
    imm = instr & 0xffff
    if imm & 0x8000:
        imm -= 0x10000
    return (int(before[f"r{rs}"], 16) + imm) & 0xffffffff


COMPACT_FPR = os.environ.get("QEMU_COMPACT_FPR") == "1"
MDU_TRACE_START = int(os.environ.get("QEMU_MDU_TRACE_START", "-1"))
MDU_TRACE_END = int(os.environ.get("QEMU_MDU_TRACE_END", "-1"))
SUPPORTED_TRACE_SCHEMAS = {"00010000", "00020000"}


def configured_trace_schema():
    schema = os.environ.get("QEMU_TRACE_SCHEMA", "00010000").lower()
    if schema not in SUPPORTED_TRACE_SCHEMAS:
        raise ValueError(f"unsupported QEMU_TRACE_SCHEMA={schema!r}")
    return schema


def fpr_state(regs):
    """Serialize FPR0..FPR31 in the same high-to-low order as RTL ctx_save_fpr."""
    if COMPACT_FPR:
        return "0"
    return "".join(hex32(regs.get(f"fpr{index}", "00000000"))
                   for index in range(31, -1, -1))


def changed_gpr(before, after):
    changes = [index for index in range(1, 32)
               if before[f"r{index}"] != after[f"r{index}"]]
    if len(changes) != 1:
        return 0, 0, "00000000"
    index = changes[0]
    return 1, index, hex32(after[f"r{index}"])


def gpr_destination(instr, before=None):
    op = (instr >> 26) & 0x3f
    rs = (instr >> 21) & 0x1f
    rt = (instr >> 16) & 0x1f
    rd = (instr >> 11) & 0x1f
    funct = instr & 0x3f
    # PREF is a non-trapping cache hint with no architectural GPR result.
    if op == 0x33:
        return None
    # COP1 memory operations update FPRs (or only memory), never a GPR.
    # MFC1/CFC1 are the COP1 transfers that do write the integer register
    # file; the remaining COP1 arithmetic and control operations do not.
    if op == 0x11:
        return rt if rs in (0, 2) else None
    # LDC1/SDC1 are double-word memory operations; their rt field names an
    # even FPR pair and must never be interpreted as an integer destination.
    if op in (0x35, 0x3d):
        return None
    # SPECIAL2 instructions use rd, unlike the immediate opcode family below.
    # The implemented subset includes MUL plus the R2 CLZ/CLO operations.
    if op == 0x1c and funct in (0x02, 0x20, 0x21):
        return rd
    # SPECIAL3 transforms write rd, while EXT/INS write rt.  The latter use
    # rd only as the msbd field and must not be reported as an rd write.
    if op == 0x1f and funct in (0x00, 0x04):
        return rt
    if op == 0x1f and funct == 0x20:
        return rd
    # REGIMM link branches write $ra. BAL is the BGEZAL encoding with $zero.
    if op == 0x01 and rt in (0x10, 0x11, 0x12, 0x13):
        return 31
    if op in (0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
              0x18, 0x19, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25,
              0x26, 0x27, 0x30, 0x32, 0x33, 0x34, 0x35, 0x36,
              0x37, 0x38):
        return rt
    if op == 0x23 or op in (0x20, 0x21, 0x22, 0x24, 0x25, 0x26, 0x27):
        return rt
    if op == 0x03:
        return 31
    if op == 0x00 and funct in (0x00, 0x02, 0x03, 0x04, 0x06, 0x07,
                                0x0a, 0x0b, 0x10, 0x12, 0x20, 0x21, 0x22, 0x23,
                                0x24, 0x25, 0x26, 0x27, 0x2a, 0x2b):
        # MOVZ/MOVN write conditionally.  Use the pre-retire register state;
        # a static destination decoder would turn a correctly suppressed
        # conditional write into a false architectural event.
        if funct == 0x0a and before is not None and int(before[f"r{rt}"], 16) != 0:
            return None
        if funct == 0x0b and before is not None and int(before[f"r{rt}"], 16) == 0:
            return None
        return rd
    # MOVF/MOVT share SPECIAL funct=0x01.  FCC0 is FCSR[23]; FCC1..FCC7
    # occupy FCSR[25..31] (FCSR[24] is reserved) in the MIPS32 layout.
    if op == 0x00 and funct == 0x01 and (rt & 0x2) == 0:
        cc = (rt >> 2) & 0x7
        fcsr = int(before.get("fcsr", "0"), 16)
        condition = (fcsr & (1 << (23 if cc == 0 else 24 + cc))) != 0
        if (rt == 0 and condition) or (rt == 1 and not condition):
            return None
        return rd
    if op == 0x00 and funct == 0x09:
        return rd
    # MIPS32 R2 RDPGPR is encoded in the COP0 major opcode with rs=0x0a.
    # It reads the pre-exception shadow bank into rd; WRPGPR (rs=0x0e) has
    # no architectural write to the current GPR file.
    if op == 0x10 and rs == 0x0a:
        return rd
    if op == 0x10 and rs == 0:
        return rt
    # DI/EI are MFMC0 encodings. They return the previous Status value in rt.
    if op == 0x10 and rs == 0x0b and rd == 12 and ((instr >> 6) & 0x1f) == 0:
        return rt
    # SPECIAL3 RDHWR: rd is the destination in the implemented contract.
    if op == 0x1f and rs == 0 and (instr & 0x3f) == 0x3b:
        return rt
    return None


def cp0_destination(instr):
    if ((instr >> 26) & 0x3f) == 0x10 and ((instr >> 21) & 0x1f) == 4:
        return (instr >> 11) & 0x1f, (instr >> 0) & 0x7
    return None


def has_delay_slot(instr):
    op = (instr >> 26) & 0x3f
    rs = (instr >> 21) & 0x1f
    funct = instr & 0x3f
    return op in (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07) or \
           (op == 0x11 and rs == 8) or \
           (op == 0x00 and funct in (0x08, 0x09))


def taken_delay_slot(events, index):
    if index == 0 or not has_delay_slot(int(events[index - 1]["instr"], 16)):
        return False
    previous = int(events[index - 1]["instr"], 16)
    op = (previous >> 26) & 0x3f
    if op in (0x02, 0x03):
        return True
    previous_pc = int(events[index - 1]["pc"], 16)
    return int(events[index]["next_pc"], 16) != previous_pc + 8


def likely_taken(instr, state):
    """Evaluate a MIPS32 branch-likely condition at its retire boundary."""
    opcode = (instr >> 26) & 0x3f
    rs = (instr >> 21) & 0x1f
    rt = (instr >> 16) & 0x1f
    lhs = int(state["regs"][f"r{rs}"], 16)
    rhs = int(state["regs"][f"r{rt}"], 16)
    lhs_signed = lhs if lhs < 0x80000000 else lhs - 0x100000000
    if opcode == 0x14:
        return lhs == rhs
    if opcode == 0x15:
        return lhs != rhs
    if opcode == 0x16:
        return lhs_signed <= 0
    if opcode == 0x17:
        return lhs_signed > 0
    if opcode == 0x01:
        if rt in (0x02, 0x12):
            return lhs_signed < 0
        if rt in (0x03, 0x13):
            return lhs_signed >= 0
    if opcode == 0x11 and rs == 8:
        condition = bool(int(state["regs"].get("fcsr", "0"), 16) & (1 << 23))
        # Only BC1FL/BC1TL annul an untaken delay slot.  BC1F/BC1T
        # retain the ordinary MIPS branch delay slot regardless of sense.
        if rt == 2:
            return not condition
        if rt == 3:
            return condition
    return None


def is_annulled_likely(events, states, index):
    """Filter the QEMU plugin event for a not-taken likely delay slot."""
    if index == 0:
        return False
    branch = int(events[index - 1]["instr"], 16)
    return (likely_taken(branch, states[index - 1]) is False and
            int(events[index]["pc"], 16) == int(events[index - 1]["pc"], 16) + 4)


def is_cop1_branch(instr):
    return ((instr >> 26) & 0x3f) == 0x11 and ((instr >> 21) & 0x1f) == 8 and \
           (((instr >> 16) & 0x1f) == 3)


def is_direct_branch_to_next_pc(events, index):
    """Reject ordinary branches that happen to target an exception offset.

    The converter uses vector-shaped ``next_pc`` values to reconstruct an
    interrupt boundary. A firmware branch can legitimately target 0x200 (or
    another vector-shaped address), especially inside an exception test. Such
    a delay slot is ordinary control flow, not an asynchronously accepted
    interrupt.
    """
    if index == 0:
        return False
    instr = int(events[index - 1]["instr"], 16)
    opcode = (instr >> 26) & 0x3f
    branch_pc = int(events[index - 1]["pc"], 16)
    if opcode in (0x02, 0x03):
        target = ((branch_pc + 4) & 0xf0000000) | ((instr & 0x03ffffff) << 2)
        return target == int(events[index]["next_pc"], 16)
    if opcode not in (0x01, 0x04, 0x05, 0x06, 0x07,
                      0x14, 0x15, 0x16, 0x17):
        return False
    offset = instr & 0xffff
    if offset & 0x8000:
        offset -= 0x10000
    target = (branch_pc + 4 + (offset << 2)) & 0xffffffff
    return target == int(events[index]["next_pc"], 16)


def signed32(value):
    return value if value < 0x80000000 else value - 0x100000000


def mdu_hilo_update(instr, before, hilo):
    """Replay HI/LO values for MDU operations with defined results.

    SPECIAL2 MUL leaves HI/LO unpredictable. Invalidate the synthetic pair
    and retain QEMU's own state instead of assigning an architectural value.
    """
    opcode = (instr >> 26) & 0x3f
    funct = instr & 0x3f
    rs = (instr >> 21) & 0x1f
    rt = (instr >> 16) & 0x1f
    if opcode == 0 and funct in (0x10, 0x12):
        return hilo
    if opcode == 0 and funct == 0x11:
        if hilo is not None:
            return int(before[f"r{rs}"], 16), hilo[1]
        return None
    if opcode == 0 and funct == 0x13:
        if hilo is not None:
            return hilo[0], int(before[f"r{rs}"], 16)
        return None
    if opcode == 0x1c and funct in (0x00, 0x01, 0x02, 0x04, 0x05):
        if funct == 0x02:
            return None
        lhs = int(before[f"r{rs}"], 16)
        rhs = int(before[f"r{rt}"], 16)
        if hilo is None:
            return None
        product = ((lhs * rhs) if funct in (0x01, 0x05) else
                   (signed32(lhs) * signed32(rhs))) & 0xffffffffffffffff
        accumulator = (hilo[0] << 32) | hilo[1]
        if funct in (0x04, 0x05):
            accumulator = (accumulator - product) & 0xffffffffffffffff
        else:
            accumulator = (accumulator + product) & 0xffffffffffffffff
        return accumulator >> 32, accumulator & 0xffffffff
    if opcode == 0 and funct in (0x18, 0x19, 0x1a, 0x1b):
        lhs = int(before[f"r{rs}"], 16)
        rhs = int(before[f"r{rt}"], 16)
        if funct == 0x18:
            product = (signed32(lhs) * signed32(rhs)) & 0xffffffffffffffff
            return product >> 32, product & 0xffffffff
        if funct == 0x19:
            product = (lhs * rhs) & 0xffffffffffffffff
            return product >> 32, product & 0xffffffff
        if rhs == 0:
            return lhs, 0xffffffff
        if funct == 0x1a:
            quotient = int(signed32(lhs) / signed32(rhs))
            remainder = signed32(lhs) - quotient * signed32(rhs)
        else:
            quotient, remainder = divmod(lhs, rhs)
        return remainder & 0xffffffff, quotient & 0xffffffff
    return hilo


def is_mdu_hilo_instruction(instr):
    opcode = (instr >> 26) & 0x3f
    funct = instr & 0x3f
    return ((opcode == 0 and funct in
             (0x10, 0x11, 0x12, 0x13, 0x18, 0x19, 0x1a, 0x1b)) or
            (opcode == 0x1c and funct in (0x00, 0x01, 0x02, 0x04, 0x05)))


def architectural_next_pc(instr, pc, regs, fallback):
    """Return the PC after a control-transfer delay slot has executed.

    QEMU's post-instruction snapshot is taken while the delay slot is the
    current PC.  RTL retirement reports the architectural next PC instead,
    so reconstruct the latter from the pre-instruction register state.
    """
    opcode = (instr >> 26) & 0x3f
    rs = (instr >> 21) & 0x1f
    rt = (instr >> 16) & 0x1f
    funct = instr & 0x3f
    if opcode in (0x02, 0x03):
        return ((pc + 4) & 0xf0000000) | ((instr & 0x03ffffff) << 2)
    if opcode == 0x00 and funct in (0x08, 0x09):
        return int(regs[f"r{rs}"], 16) & 0xfffffffc
    condition = None
    if opcode in (0x04, 0x14):
        condition = int(regs[f"r{rs}"] , 16) == int(regs[f"r{rt}"], 16)
    elif opcode in (0x05, 0x15):
        condition = int(regs[f"r{rs}"], 16) != int(regs[f"r{rt}"], 16)
    elif opcode in (0x06, 0x16):
        condition = signed32(int(regs[f"r{rs}"], 16)) <= 0
    elif opcode in (0x07, 0x17):
        condition = signed32(int(regs[f"r{rs}"], 16)) > 0
    elif opcode == 0x01:
        value = signed32(int(regs[f"r{rs}"], 16))
        if rt in (0x00, 0x10, 0x02, 0x12):
            condition = value < 0 if rt in (0x02, 0x12) else value < 0
        elif rt in (0x01, 0x11, 0x03, 0x13):
            condition = value >= 0 if rt in (0x03, 0x13) else value >= 0
    elif opcode == 0x11 and rs == 8:
        fcsr = int(regs.get("fcsr", "0"), 16)
        cc = (rt >> 2) & 0x7
        bit = 23 if cc == 0 else 24 + cc
        condition_bit = bool(fcsr & (1 << bit))
        condition = condition_bit if (rt & 1) else not condition_bit
    if condition is not None:
        offset = int(instr & 0xffff)
        if offset & 0x8000:
            offset -= 0x10000
        target = (pc + 4 + (offset << 2)) & 0xffffffff
        # Both ordinary branches and taken branch-likely instructions execute
        # the delay slot.  An untaken branch-likely skips it and still lands at
        # PC+8, which is the same final address used here.
        return target if condition else (pc + 8) & 0xffffffff
    return fallback


def is_control_transfer_to_next_pc(events, states, index):
    """Recognize the normal target reported after a branch delay slot."""
    if index == 0:
        return False
    branch = events[index - 1]
    branch_instr = int(branch["instr"], 16)
    branch_pc = int(branch["pc"], 16)
    if (not has_delay_slot(branch_instr) or
            int(events[index]["pc"], 16) != branch_pc + 4):
        return False
    fallback = (branch_pc + 8) & 0xffffffff
    target = architectural_next_pc(
        branch_instr, branch_pc, states[index - 1]["regs"], fallback)
    return target == int(events[index]["next_pc"], 16)


def faulting_memory_access(instr, before):
    """Reconstruct a memory access when QEMU aborts before its mem callback."""
    opcode = (instr >> 26) & 0x3f
    loads = {
        0x20: 1, 0x21: 2, 0x22: 4, 0x23: 4, 0x24: 1, 0x25: 2,
        0x26: 4, 0x27: 4, 0x30: 4, 0x31: 4, 0x35: 8, 0x37: 8,
        0x1a: 8, 0x1b: 8,
    }
    stores = {
        0x28: 1, 0x29: 2, 0x2a: 4, 0x2b: 4, 0x2c: 8, 0x2d: 8,
        0x2e: 4, 0x38: 4, 0x39: 4, 0x3d: 8,
    }
    size = loads.get(opcode) or stores.get(opcode)
    if size is None:
        return None
    rt = (instr >> 16) & 0x1f
    address = effective_address(instr, before)
    is_write = opcode in stores
    value = "00000000"
    if is_write and opcode not in (0x39, 0x3d):
        value = hex32(before[f"r{rt}"])
    return is_write, address, size, value


def convert(events, states):
    trace_schema = configured_trace_schema()
    if (not getattr(states, "streaming", False) and
            len(states) < len(events) + 1):
        raise ValueError(f"state records {len(states)} < events + post-state {len(events) + 1}")
    # QEMU accepts a replayed external interrupt at the end of a delay-slot
    # translation block, after the branch/delay-slot instructions have
    # retired.  The MIPS architectural Cause.BD bit still describes that
    # interrupted delay slot, but the generic QEMU state snapshot does not
    # retain it for the handler's subsequent MFC0 Cause.  Carry this one
    # architectural bit into the first Cause read and into the following GPR
    # data-flow without changing ordinary synchronous exceptions.
    replay_bd_pending = False
    replay_bd_seen = False
    replay_cause_pending = False
    replay_gpr_overrides = {}
    replay_mdu_hilo = None
    replay_memory_bytes = {}
    for index, event in enumerate(events):
        if is_annulled_likely(events, states, index):
            continue
        before = dict(states[index]["regs"])
        before.update(replay_gpr_overrides)
        after = dict(states[index + 1]["regs"])
        if int(event["pc"], 16) != int(states[index]["pc"], 16):
            raise ValueError(f"retire {index}: event/state PC misalignment")
        instr = int(event["instr"], 16)
        opcode = (instr >> 26) & 0x3f
        is_merge_memory = opcode in (0x22, 0x26, 0x2a, 0x2e)
        is_merge_store_access = opcode in (0x2a, 0x2e)
        is_double_store = (opcode == 0x3d or
                           (opcode == 0x13 and (instr & 0x3f) == 0x09))
        mdu_funct = instr & 0x3f
        mdu_read = ((instr >> 26) & 0x3f) == 0 and mdu_funct in (0x10, 0x12)
        if replay_mdu_hilo is not None and mdu_read:
            destination_reg = (instr >> 11) & 0x1f
            if destination_reg:
                value = replay_mdu_hilo[0 if mdu_funct == 0x10 else 1]
                after[f"r{destination_reg}"] = hex32(value)
                replay_gpr_overrides[f"r{destination_reg}"] = hex32(value)
        # The RTL retire observation currently commits the COP1 branch
        # control through the normal delay-slot path but does not expose the
        # branch instruction as a WB record. Keep its architectural effect in
        # the following target/delay-slot sequence and omit this QEMU-only
        # control event for alignment.
        if is_cop1_branch(instr):
            continue
        destination = gpr_destination(instr, before)
        if ((instr >> 26) & 0x3f) == 0x01 and \
                ((instr >> 16) & 0x1f) in (0x12, 0x13) and \
                likely_taken(instr, states[index]) is False:
            destination = None
        if destination is None or destination == 0:
            gpr_we, gpr_addr, gpr_data = 0, 0, "00000000"
        else:
            gpr_we, gpr_addr, gpr_data = 1, destination, hex32(
                after[f"r{destination}"])
        cp0_write = cp0_destination(instr)
        if cp0_write:
            cp0_addr, cp0_sel = cp0_write
            rt = (instr >> 16) & 0x1f
            cp0_we = 1
            cp0_data = hex32(before[f"r{rt}"])
        else:
            cp0_we, cp0_addr, cp0_sel, cp0_data = 0, 0, 0, "00000000"
        mem_valid = int(bool(event.get("mem_valid")))
        mem_addr = int(event.get("mem_addr", "0"), 16)
        mem_size = int(event.get("mem_size", 0))
        mem_be = ((1 << mem_size) - 1) << (mem_addr & 3) if mem_valid else 0xF
        load_rdata = event.get("mem_value", "00000000")
        replayed_memory_load = False
        if event.get("mem_read") and destination and mem_size:
            load_bytes = [replay_memory_bytes.get(mem_addr + offset)
                          for offset in range(mem_size)]
            if all(value is not None for value in load_bytes):
                load_value = sum(value << (8 * offset)
                                 for offset, value in enumerate(load_bytes))
                load_rdata = hex32(load_value)
                after[f"r{destination}"] = load_rdata
                gpr_data = load_rdata
                replay_gpr_overrides[f"r{destination}"] = load_rdata
                replayed_memory_load = True
        # QEMU's atomic callback reports the old memory value for a failed
        # SC, whereas the RTL retire contract reports the attempted store.
        # Reconstruct the latter from the SC source register pre-state.
        is_sc = ((instr >> 26) & 0x3f) == 0x38
        sc_store_data = hex32(before[f"r{(instr >> 16) & 0x1f}"]) if is_sc else None
        if is_sc:
            rs = (instr >> 21) & 0x1f
            imm = instr & 0xffff
            if imm & 0x8000:
                imm -= 0x10000
            mem_valid = 1
            mem_read = 0
            mem_write = 1
            mem_addr = (int(before[f"r{rs}"], 16) + imm) & 0xffffffff
            mem_size = 4
            mem_be = 0xF
        store_wdata = event.get("mem_value", "00000000")
        store_opcode = (instr >> 26) & 0x3f
        if event.get("mem_write") and store_opcode in (0x28, 0x29, 0x2a, 0x2b):
            store_rt = (instr >> 16) & 0x1f
            store_value = int(before[f"r{store_rt}"], 16)
            if store_opcode == 0x28:
                store_wdata = f"{store_value & 0xff:08x}"
            elif store_opcode == 0x29:
                store_wdata = f"{store_value & 0xffff:08x}"
            else:
                store_wdata = hex32(store_value)
        store_rt_key = f"r{(instr >> 16) & 0x1f}"
        if event.get("mem_write"):
            replay_store_size = (1 if store_opcode == 0x28 else
                                 2 if store_opcode == 0x29 else
                                 mem_size or 4)
            if store_rt_key in replay_gpr_overrides:
                replay_store = int(sc_store_data or store_wdata, 16)
                for offset in range(replay_store_size):
                    replay_memory_bytes[mem_addr + offset] = \
                        (replay_store >> (8 * offset)) & 0xff
            else:
                # A real QEMU store supersedes any synthetic value retained
                # for the same bytes, even though the plugin reports the old
                # memory value for that store.
                for offset in range(replay_store_size):
                    replay_memory_bytes.pop(mem_addr + offset, None)
        # Cause is sticky across exception entry.  Comparing before/after
        # Cause therefore misses a second synchronous exception (for example
        # a trap after the handler has returned).  The retire event's next PC
        # is the architectural indication that this instruction redirected to
        # the general exception vector; decode the latched Cause from the
        # post-state for the exception payload.
        event_next_pc = int(event["next_pc"], 16)
        sequential_next_pc = (int(event["pc"], 16) + 4) & 0xffffffff
        # Software-managed boot-ROM guests use the physical BFC00200 vector,
        # while Linux programs EBase to a nonzero 4-KiB-aligned address and
        # enters EBase+0x180. Use the aligned low-12-bit offset so the latter
        # is recognized without requiring EBase in the compact plugin state.
        entered_general_vector = (event_next_pc != sequential_next_pc and
                                  ((event_next_pc & 0x1fffffff) == 0x180 or
                                   (event_next_pc & 0xfff) == 0x180 or
                                   event_next_pc == 0xbfc00200))
        cause_value = int(after.get("cause", "0"), 16)
        cause_code = (cause_value >> 2) & 0x1f
        # Include the project's bounded IP-based/VIC vectors.  The normal
        # general vector is 0x180; the vic_cpu corpus uses EBase+0x1f0,
        # represented as 0x370 after the firmware's configured EBase.
        vector_offset = event_next_pc & 0xfff
        vector_pc = (event_next_pc != sequential_next_pc and
                     (vector_offset in (0x180, 0x200, 0x300, 0x370, 0x380) or
                      event_next_pc == 0xbfc00200))
        ordinary_vector_branch = (
            is_direct_branch_to_next_pc(events, index) or
            is_control_transfer_to_next_pc(events, states, index))
        interrupt_pending = bool(cause_value & (0xff << 8) or
                                 cause_value & (1 << 30))
        # The SoC's vectored interrupt slot is EBase+0x200.  TI/IP bits
        # identify that asynchronous boundary even if other Cause bits are
        # retained from an earlier exception in the RTL-visible state.
        vectored_async_interrupt = (
            vector_pc and not ordinary_vector_branch and interrupt_pending and
            (cause_code == 0 or vector_offset == 0x200))
        if vectored_async_interrupt:
            # BD replay is scoped to one interrupt's first Cause read.
            replay_bd_seen = False
        if (vector_pc and not ordinary_vector_branch and index > 0 and
                has_delay_slot(int(events[index - 1]["instr"], 16)) and
                int(event["pc"], 16) ==
                int(events[index - 1]["pc"], 16) + 4 and
                ((cause_value >> 2) & 0x1f) == 0 and not replay_bd_seen):
            # The event stream is the architectural retire contract.  A
            # vector reached from a translated delay-slot TB is not by
            # itself sufficient evidence for Cause.BD: the RTL can accept a
            # replayed asynchronous IRQ at that boundary with bd=0.
            # The plugin does not emit ``bd`` for a replayed external IRQ.
            # Preserve a BD bit recovered from the preceding general vector
            # while the handler's branch reaches the configured VIC vector;
            # a missing/false field must not erase that architectural state.
            if event.get("bd", 0) or ((cause_value >> 31) & 1):
                replay_bd_pending = True
            replay_cause_pending = True
        elif (vector_pc and not ordinary_vector_branch and index > 0 and
              has_delay_slot(int(events[index - 1]["instr"], 16)) and
              int(event["pc"], 16) ==
              int(events[index - 1]["pc"], 16) + 4):
            replay_bd_pending = bool(cause_value & (1 << 31))
            replay_cause_pending = True
        elif (vector_pc and not ordinary_vector_branch and
              ((cause_value >> 31) & 1)):
            # A scheduled RTL IRQ may be accepted while the branch is still
            # in the pipeline, before QEMU retires its branch/delay-slot
            # events. In that representation the post-state Cause.BD is the
            # only producer-independent evidence available at the vector.
            replay_bd_pending = True
            replay_cause_pending = True
        # MFC0 Cause is normally the first handler instruction that exposes
        # the replayed interrupt state.  Update the post-state register so
        # later arithmetic observes the same BD bit as RTL.
        is_mfc0_cause = (((instr >> 26) & 0x3f) == 0x10 and
                         ((instr >> 21) & 0x1f) == 0 and
                         ((instr >> 11) & 0x1f) == 13 and
                         (instr & 0x7) == 0)
        if replay_cause_pending and is_mfc0_cause:
            if not replay_bd_seen and replay_bd_pending:
                cause_value |= 1 << 31
            else:
                cause_value &= ~(1 << 31)
            destination_reg = (instr >> 16) & 0x1f
            if destination_reg:
                after[f"r{destination_reg}"] = hex32(cause_value)
                replay_gpr_overrides[f"r{destination_reg}"] = hex32(cause_value)
                if destination == destination_reg:
                    gpr_data = hex32(cause_value)
            replay_bd_pending = False
            replay_bd_seen = True
            replay_cause_pending = False
        # Propagate a corrected Cause value through the bounded VIC handler's
        # immediate shift/logic sequence.  The plugin snapshot is QEMU's
        # unmodified architectural state, so without this small data-flow
        # correction the next instruction would still consume the stale
        # native Cause value.
        if replay_gpr_overrides and ((instr >> 26) & 0x3f) == 0 and \
                (instr & 0x3f) in (0x00, 0x02, 0x03):
            rs = (instr >> 21) & 0x1f
            rt = (instr >> 16) & 0x1f
            rd = (instr >> 11) & 0x1f
            sa = (instr >> 6) & 0x1f
            if (instr & 0x3f) in (0x02, 0x03):
                rs = rt
            if f"r{rs}" in replay_gpr_overrides and rd:
                source = int(replay_gpr_overrides[f"r{rs}"], 16)
                if (instr & 0x3f) == 0x00:
                    shifted = (source << sa) & 0xffffffff
                elif (instr & 0x3f) == 0x02:
                    shifted = source >> sa
                else:
                    signed = source if source < 0x80000000 else source - 0x100000000
                    shifted = (signed >> sa) & 0xffffffff
                after[f"r{rd}"] = hex32(shifted)
                replay_gpr_overrides[f"r{rd}"] = hex32(shifted)
                if destination == rd:
                    gpr_data = hex32(shifted)
        previous_mdu_hilo = replay_mdu_hilo
        replay_mdu_hilo = mdu_hilo_update(instr, before, replay_mdu_hilo)
        if (MDU_TRACE_START >= 0 and MDU_TRACE_END >= MDU_TRACE_START and
                MDU_TRACE_START <= index <= MDU_TRACE_END and
                is_mdu_hilo_instruction(instr)):
            rs = (instr >> 21) & 0x1f
            rt = (instr >> 16) & 0x1f
            print(
                "QEMU_MDU_TRACE "
                f"index={index} pc={event['pc']} instr={event['instr']} "
                f"rs=r{rs}:{before[f'r{rs}']} rt=r{rt}:{before[f'r{rt}']} "
                f"synthetic_before={previous_mdu_hilo} "
                f"synthetic_after={replay_mdu_hilo} "
                f"qemu_before={before.get('hi')}:{before.get('lo')} "
                f"qemu_after={after.get('hi')}:{after.get('lo')}",
                file=sys.stderr,
            )
        # A refill uses EBase+0x000 rather than the general EBase+0x180
        # vector.  QEMU's compact state stream does not retain the Cause code
        # for this pre-memory-callback boundary, but the non-branch redirect
        # and decoded access identify it unambiguously.
        entered_tlb_refill = ((event_next_pc & 0xfff) == 0 and
                              not ordinary_vector_branch and
                              instr != 0x42000018 and
                              event_next_pc != ((int(event["pc"], 16) + 4) &
                                                0xffffffff))
        synchronous_exception_taken = int(
            ((entered_general_vector and not ordinary_vector_branch) and
             cause_code != 0) or entered_tlb_refill)
        exception_taken = int(synchronous_exception_taken or
                              vectored_async_interrupt)
        exception_code = (cause_code if entered_general_vector and
                          not ordinary_vector_branch else 0)
        if entered_tlb_refill:
            access = faulting_memory_access(instr, before)
            exception_code = 3 if access and access[0] else 2
            if access and not mem_valid:
                mem_write, mem_addr, mem_size, mem_value = access
                mem_valid = 1
                mem_read = int(not mem_write)
                mem_be = ((1 << mem_size) - 1) << (mem_addr & 3)
                event["mem_value"] = mem_value
                event["mem_read"] = mem_read
                event["mem_write"] = int(mem_write)
                if mem_write:
                    store_wdata = mem_value
        if synchronous_exception_taken and not mem_valid:
            access = faulting_memory_access(instr, before)
            if access and access[2] <= 4:
                mem_write, mem_addr, mem_size, mem_value = access
                mem_valid = 1
                mem_read = int(not mem_write)
                mem_be = ((1 << mem_size) - 1) << (mem_addr & 3)
                event["mem_value"] = mem_value
                event["mem_read"] = mem_read
                event["mem_write"] = int(mem_write)
                if mem_write:
                    store_wdata = mem_value
        if not exception_taken:
            exception_code = 0
        exception_bd = ((cause_value >> 31) & 1) if exception_taken else 0
        # A synchronous exception is taken instead of committing the
        # faulting instruction. QEMU's post-state snapshot can still expose
        # a transient register delta, so it must not become a retire write.
        if synchronous_exception_taken:
            gpr_we, gpr_addr, gpr_data = 0, 0, "00000000"
            cp0_we = 0
        # A Cause replay override models only the value flowing through the
        # bounded interrupt handler.  Once an ordinary architectural write
        # commits the same GPR, the override must be retired as well; keeping
        # it alive would corrupt a later source operand (notably MTC0 data).
        if (destination and not synchronous_exception_taken and
                not is_mfc0_cause and not mdu_read and
                not replayed_memory_load):
            replay_gpr_overrides.pop(f"r{destination}", None)
        # The event stream's next_pc is the immediate post-instruction PC.
        # For a control transfer this is the delay-slot PC; the comparator
        # handles the producer-specific delay-slot boundary explicitly.
        event_next_pc = int(event["next_pc"], 16)
        if instr == 0x42000018:
            # The plugin samples ERET before the custom MIPS exception path
            # has restored the precise EPC.  The post-state is authoritative
            # for the architectural return boundary.
            event_next_pc = int(after["epc"], 16)
        trace_mem_valid = mem_valid
        trace_mem_read = (mem_read if is_sc else
                          int(bool(event.get("mem_read"))))
        trace_mem_write = (mem_write if is_sc else
                           int(bool(event.get("mem_write"))))
        trace_mem_addr = mem_addr
        trace_mem_wdata = (sc_store_data if sc_store_data is not None else
                           store_wdata) if trace_mem_write else "00000000"
        trace_mem_wdata_hi = "00000000"
        if trace_mem_write and is_double_store:
            if mem_size != 8 or "mem_value_hi" not in event:
                raise ValueError(
                    f"retire {index}: double store lacks a complete 64-bit "
                    "QEMU memory value")
            trace_mem_wdata_hi = hex32(event["mem_value_hi"])
        if is_merge_memory:
            # QEMU lowers merge operations into helper byte callbacks. Report
            # the original architectural effective address instead of the
            # final aligned/byte callback address.
            trace_mem_valid = 1
            trace_mem_addr = effective_address(instr, before)
            trace_mem_read = int(opcode in (0x22, 0x26))
            trace_mem_write = int(is_merge_store_access)
            if is_merge_store_access:
                rt = (instr >> 16) & 0x1f
                trace_mem_wdata = hex32(before[f"r{rt}"])
        record = {
            "schema": trace_schema,
            "pc": hex32(event["pc"]),
            "instr": hex32(event["instr"]),
            "next_pc": hex32(event_next_pc),
            "qemu_cause": hex32(before.get("cause", "00000000")),
            "qemu_epc": hex32(before.get("epc", "00000000")),
            "gpr_we": gpr_we,
            "gpr_addr": gpr_addr,
            "gpr_data": gpr_data,
            "cp0_we": cp0_we,
            "cp0_addr": cp0_addr,
            "cp0_sel": cp0_sel,
            "cp0_data": cp0_data,
            "fpr_state": fpr_state(after),
            "fcsr_state": hex32(after.get("fcsr", "00000000")),
            "mem_valid": trace_mem_valid,
            "mem_read": trace_mem_read,
            "mem_write": trace_mem_write,
            "mem_addr": hex32(trace_mem_addr),
            "mem_wdata": trace_mem_wdata,
            "mem_wdata_hi": trace_mem_wdata_hi,
            "mem_be": f"{mem_be:x}",
            "mem_rdata": ("00000000" if synchronous_exception_taken else
                          (load_rdata if event.get("mem_read") else
                           "xxxxxxxx")),
            "except": exception_taken,
            "except_code": exception_code,
            "bd": exception_bd,
            "eret": int(instr == 0x42000018),
        }
        if trace_schema == "00020000":
            architectural_gprs = dict(after)
            architectural_gprs.update(replay_gpr_overrides)
            architectural_gprs["r0"] = "00000000"
            record["gpr_state"] = "".join(
                hex32(architectural_gprs[f"r{reg}"])
                for reg in range(31, -1, -1))
            if replay_mdu_hilo is None:
                hilo_hi = hex32(after.get("hi", "00000000"))
                hilo_lo = hex32(after.get("lo", "00000000"))
            else:
                hilo_hi, hilo_lo = (hex32(replay_mdu_hilo[0]),
                                    hex32(replay_mdu_hilo[1]))
            record["hilo_state"] = hilo_hi + hilo_lo
        yield record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("events")
    parser.add_argument("states")
    parser.add_argument("output")
    args = parser.parse_args()
    states = StateWindow(args.states)
    events = EventWindow(args.events, states)
    count = 0
    with open(args.output, "w", encoding="ascii") as stream:
        for record in convert(events, states):
            record["retire_seq"] = count
            json.dump(record, stream, separators=(",", ":"))
            stream.write("\n")
            count += 1
    print(f"QEMU_SYSTEM_RETIRE_CONVERT_PASS records={count}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        print(f"qemu_system_state_to_jsonl: {exc}", file=sys.stderr)
        raise SystemExit(1)
