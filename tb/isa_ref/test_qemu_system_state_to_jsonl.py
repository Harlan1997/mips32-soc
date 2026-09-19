#!/usr/bin/env python3
"""Regression tests for QEMU system retire conversion decisions."""

import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("qemu_system_state_to_jsonl.py")
SPEC = importlib.util.spec_from_file_location("qemu_system_state_to_jsonl", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def encode_special2(rs, rt, rd, funct, sa=0):
    return (0x1C << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (sa << 6) | funct


def test_special2_accumulate_has_no_gpr_destination():
    for funct in (0x00, 0x01, 0x04, 0x05):
        assert MODULE.gpr_destination(encode_special2(3, 4, 0, funct)) is None


def test_special2_rd_operations_keep_their_destination():
    for funct in (0x02, 0x20, 0x21):
        assert MODULE.gpr_destination(encode_special2(3, 4, 7, funct)) == 7


def test_replay_bd_survives_general_to_vic_vector_handoff():
    """A VIC jump delay slot must not clear BD recovered at the first vector."""
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [
        {"pc": "00000100", "instr": "00000000", "next_pc": "00000104"},
        {"pc": "00000104", "instr": "00000000", "next_pc": "80000180"},
        {"pc": "80000180", "instr": "0c0000dc", "next_pc": "80000184"},
        {"pc": "80000184", "instr": "afa20004", "next_pc": "80000370"},
        {"pc": "80000370", "instr": "40026800", "next_pc": "80000374"},
        {"pc": "80000374", "instr": "00021082", "next_pc": "80000378"},
    ]
    states = [
        {"pc": "00000100", "regs": regs()},
        {"pc": "00000104", "regs": regs()},
        {"pc": "80000180", "regs": regs(cause="80000400")},
        {"pc": "80000184", "regs": regs(cause="80000400")},
        {"pc": "80000370", "regs": regs(cause="80000400")},
        {"pc": "80000374", "regs": regs(cause="80000400", r2="00000400")},
        {"pc": "80000378", "regs": regs(cause="80000400", r2="00000100")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[4]["gpr_data"] == "80000400"
    assert result[5]["gpr_data"] == "20000100"


if __name__ == "__main__":
    test_special2_accumulate_has_no_gpr_destination()
    test_special2_rd_operations_keep_their_destination()
    test_replay_bd_survives_general_to_vic_vector_handoff()
    print("qemu_system_state_to_jsonl tests: PASS")
