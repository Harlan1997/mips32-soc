#!/usr/bin/env python3
"""Adversarial tests for the strict focus differential comparator."""

import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
COMPARATOR = ROOT / "scripts" / "compare_focus_differential.py"


def qemu(seq, pc="10000000", values=None):
    values = values or {}
    regs = {name: values.get(name, "00000000") for name in
            ("a0", "a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30")}
    return (
        f"QEMU_FOCUS seq={seq} phase=retired pc={pc} instr=20000000 "
        f"a0={regs['a0']} a1={regs['a1']} t5={regs['t5']} t9={regs['t9']} "
        f"v0={regs['v0']} v1={regs['v1']} sp={regs['sp']} ra={regs['ra']} "
        f"r30={regs['r30']}"
    )


def rtl(seq, pc="10000000", values=None, meta=None):
    values = values or {}
    meta = meta or {"we": "0/0/00000000", "exc": "0/0", "bad": "00000000", "epc": "00000000", "bd": "0"}
    regs = {name: values.get(name, "00000000") for name in
            ("a0", "a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30")}
    return (
        f"RTL_FOCUS seq={seq} cycle={seq + 10} phase=retired pc={pc} inst=20000000 "
        f"a0={regs['a0']} a1={regs['a1']} t5={regs['t5']} t9={regs['t9']} "
        f"v0={regs['v0']} v1={regs['v1']} sp={regs['sp']} ra={regs['ra']} r30={regs['r30']} "
        f"we={meta['we']} except={meta['exc']} bad={meta['bad']} epc={meta['epc']} bd={meta['bd']}"
    )


def invoke(ref_path, dut_path, *extra):
    return subprocess.run(
        [sys.executable, str(COMPARATOR), "--ref", str(ref_path), "--dut", str(dut_path), *extra],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def expect(name, condition, output):
    if not condition:
        raise AssertionError(f"{name} failed\n{output}")


def main():
    with tempfile.TemporaryDirectory(prefix="focus-comparator-") as temp:
        root = pathlib.Path(temp)
        ref = root / "ref.log"
        dut = root / "dut.log"
        ref.write_text(qemu(0, values={"a0": "00000001"}) + "\n" + qemu(1, pc="10000004") + "\n")
        dut.write_text(ref.read_text())

        result = invoke(ref, dut)
        expect("valid full trace", result.returncode == 0, result.stdout)

        dut.write_text(qemu(0, values={"a0": "00000001"}) + "\n")
        result = invoke(ref, dut)
        expect("truncation rejection", result.returncode == 2 and "counts differ" in result.stdout, result.stdout)

        dut.write_text(qemu(0, values={"a0": "deadbeef"}) + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("selected GPR mutation rejection", result.returncode == 1 and "a0" in result.stdout, result.stdout)

        dut.write_text(qemu(0) + "\n" + qemu(0, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("duplicate sequence rejection", result.returncode == 2 and "duplicate" in result.stdout, result.stdout)

        dut.write_text(qemu(0, pc="10000004") + "\n" + qemu(1) + "\n")
        result = invoke(ref, dut)
        expect("reordered occurrence rejection", result.returncode == 1 and "pc" in result.stdout, result.stdout)

        ambiguous = root / "ambiguous.log"
        ambiguous.write_text(qemu(0) + "\n" + qemu(1) + "\n")
        result = invoke(ambiguous, ambiguous, "--checkpoint", "0x10000000")
        expect("ambiguous checkpoint rejection", result.returncode == 2 and "ambiguous" in result.stdout, result.stdout)

        result = invoke(ref, dut, "--checkpoint", "0x10000000", "--occurrence", "0")
        expect("checkpoint GPR mismatch rejection", result.returncode == 1, result.stdout)

        rtl_ref = root / "rtl_ref.log"
        rtl_dut = root / "rtl_dut.log"
        rtl_text = rtl(0) + "\n" + rtl(1, pc="10000004") + "\n"
        rtl_ref.write_text(rtl_text)
        rtl_dut.write_text(rtl_text)
        result = invoke(rtl_ref, rtl_dut)
        expect("RTL metadata full trace", result.returncode == 0, result.stdout)

    print("FOCUS_DIFFERENTIAL_CHECKER_TEST_PASS")


if __name__ == "__main__":
    main()
