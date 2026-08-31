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


if __name__ == "__main__":
    test_special2_accumulate_has_no_gpr_destination()
    test_special2_rd_operations_keep_their_destination()
    print("qemu_system_state_to_jsonl tests: PASS")
