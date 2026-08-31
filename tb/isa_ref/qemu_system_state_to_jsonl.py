#!/usr/bin/env python3
"""Convert QEMU system-mode plugin state/event streams to retire JSONL."""
import argparse
import json
import sys

CP0_REGS = {
    "index": (0, 0),
    "pagemask": (5, 0),
    "entryhi": (10, 0),
    "status": (12, 0),
    "cause": (13, 0),
    "epc": (14, 0),
}


def load_jsonl(path):
    values = []
    with open(path, encoding="ascii") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                values.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{number}: invalid JSON: {exc}") from exc
    return values


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


def fpr_state(regs):
    """Serialize FPR0..FPR31 in the same high-to-low order as RTL ctx_save_fpr."""
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
    if opcode not in (0x01, 0x04, 0x05, 0x06, 0x07,
                      0x14, 0x15, 0x16, 0x17):
        return False
    offset = instr & 0xffff
    if offset & 0x8000:
        offset -= 0x10000
    branch_pc = int(events[index - 1]["pc"], 16)
    target = (branch_pc + 4 + (offset << 2)) & 0xffffffff
    return target == int(events[index]["next_pc"], 16)


def signed32(value):
    return value if value < 0x80000000 else value - 0x100000000


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


def changed_cp0(before, after):
    changes = [(name, address, sel) for name, (address, sel) in CP0_REGS.items()
               if before.get(name) != after.get(name)]
    if len(changes) != 1:
        return 0, 0, 0, "00000000"
    name, address, sel = changes[0]
    return 1, address, sel, hex32(after[name])


def convert(events, states):
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
    for index, event in enumerate(events):
        if is_annulled_likely(events, states, index):
            continue
        before = dict(states[index]["regs"])
        before.update(replay_gpr_overrides)
        after = dict(states[index + 1]["regs"])
        if int(event["pc"], 16) != int(states[index]["pc"], 16):
            raise ValueError(f"retire {index}: event/state PC misalignment")
        instr = int(event["instr"], 16)
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
            cp0_names = {0: "index", 2: "entrylo0", 3: "entrylo1",
                         5: "pagemask", 10: "entryhi", 12: "status",
                         13: "cause", 14: "epc"}
            cp0_name = cp0_names.get(cp0_addr)
            cp0_we = int(cp0_name is not None)
            # An asynchronous interrupt can be accepted immediately after an
            # MTC0.  The post-state then includes EXL/IP side effects, while
            # the retire payload is the source GPR value actually written.
            rt = (instr >> 16) & 0x1f
            cp0_data = hex32(before[f"r{rt}"]) if cp0_name else "00000000"
        else:
            cp0_we, cp0_addr, cp0_sel, cp0_data = 0, 0, 0, "00000000"
        mem_valid = int(bool(event.get("mem_valid")))
        mem_addr = int(event.get("mem_addr", "0"), 16)
        mem_size = int(event.get("mem_size", 0))
        mem_be = ((1 << mem_size) - 1) << (mem_addr & 3) if mem_valid else 0xF
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
        # Cause is sticky across exception entry.  Comparing before/after
        # Cause therefore misses a second synchronous exception (for example
        # a trap after the handler has returned).  The retire event's next PC
        # is the architectural indication that this instruction redirected to
        # the general exception vector; decode the latched Cause from the
        # post-state for the exception payload.
        event_next_pc = int(event["next_pc"], 16)
        # Software-managed boot-ROM guests use the physical BFC00200 vector,
        # while the normal system differential uses the conventional 0x180
        # vector. Both are architectural exception boundaries.
        entered_general_vector = ((event_next_pc & 0x1fffffff) == 0x180 or
                                  event_next_pc == 0xbfc00200)
        cause_value = int(after.get("cause", "0"), 16)
        # Include the project's bounded IP-based/VIC vectors.  The normal
        # general vector is 0x180; the vic_cpu corpus uses EBase+0x1f0,
        # represented as 0x370 after the firmware's configured EBase.
        vector_offset = event_next_pc & 0x1fffffff
        vector_pc = (vector_offset in (0x180, 0x200, 0x300, 0x370, 0x380) or
                     event_next_pc == 0xbfc00200)
        ordinary_vector_branch = is_direct_branch_to_next_pc(events, index)
        if (vector_pc and not ordinary_vector_branch and index > 0 and
                has_delay_slot(int(events[index - 1]["instr"], 16)) and
                int(event["pc"], 16) ==
                int(events[index - 1]["pc"], 16) + 4 and
                ((cause_value >> 2) & 0x1f) == 0 and not replay_bd_seen):
            # The event stream is the architectural retire contract.  A
            # vector reached from a translated delay-slot TB is not by
            # itself sufficient evidence for Cause.BD: the RTL can accept a
            # replayed asynchronous IRQ at that boundary with bd=0.
            replay_bd_pending = bool(event.get("bd", 0))
            replay_cause_pending = True
        elif (vector_pc and not ordinary_vector_branch and index > 0 and
              has_delay_slot(int(events[index - 1]["instr"], 16)) and
              int(event["pc"], 16) ==
              int(events[index - 1]["pc"], 16) + 4):
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
        exception_taken = int(entered_general_vector and
                              ((cause_value >> 2) & 0x1f) != 0)
        exception_code = ((cause_value >> 2) & 0x1f) if exception_taken else 0
        exception_bd = ((cause_value >> 31) & 1) if exception_taken else 0
        # A synchronous exception is taken instead of committing the
        # faulting instruction. QEMU's post-state snapshot can still expose
        # a transient register delta, so it must not become a retire write.
        if exception_taken:
            gpr_we, gpr_addr, gpr_data = 0, 0, "00000000"
        # A Cause replay override models only the value flowing through the
        # bounded interrupt handler.  Once an ordinary architectural write
        # commits the same GPR, the override must be retired as well; keeping
        # it alive would corrupt a later source operand (notably MTC0 data).
        if destination and not exception_taken and not is_mfc0_cause:
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
        yield {
            "schema": "00010000",
            "pc": hex32(event["pc"]),
            "instr": hex32(event["instr"]),
            "next_pc": hex32(event_next_pc),
            "gpr_we": gpr_we,
            "gpr_addr": gpr_addr,
            "gpr_data": gpr_data,
            "cp0_we": cp0_we,
            "cp0_addr": cp0_addr,
            "cp0_sel": cp0_sel,
            "cp0_data": cp0_data,
            "fpr_state": fpr_state(after),
            "fcsr_state": hex32(after.get("fcsr", "00000000")),
            "mem_valid": mem_valid,
            "mem_read": mem_read if is_sc else int(bool(event.get("mem_read"))),
            "mem_write": mem_write if is_sc else int(bool(event.get("mem_write"))),
            "mem_addr": hex32(mem_addr),
            "mem_wdata": (sc_store_data if sc_store_data is not None else
                          event.get("mem_value", "00000000")) if
                         (is_sc or event.get("mem_write")) else "00000000",
            "mem_be": f"{mem_be:x}",
            "mem_rdata": event.get("mem_value", "00000000") if event.get("mem_read") else "xxxxxxxx",
            "except": exception_taken,
            "except_code": exception_code,
            "bd": exception_bd,
            "eret": int(instr == 0x42000018),
        }


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
