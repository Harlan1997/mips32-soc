#!/usr/bin/env python3
"""Adversarial tests for the strict focus differential comparator."""

import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
COMPARATOR = ROOT / "scripts" / "compare_focus_differential.py"


def gprs_blob(values=None):
    values = values or {}
    aliases = {"v0": 2, "v1": 3, "a0": 4, "a1": 5, "t5": 13,
               "t9": 25, "sp": 29, "r30": 30, "ra": 31}
    return "".join(
        values.get(f"r{idx}", values.get(next(
            (name for name, reg_idx in aliases.items() if reg_idx == idx),
            "__missing__"), "00000000"))
        for idx in range(32)
    )


def qemu(seq, pc="10000000", values=None, instr="20000000", phase="retired",
         include_gprs=True):
    values = values or {}
    regs = {name: values.get(name, "00000000") for name in
            ("a0", "a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30")}
    gprs = f" gprs={gprs_blob(values)}" if include_gprs else ""
    return (
        f"QEMU_FOCUS seq={seq} phase={phase} pc={pc} instr={instr} "
        f"a0={regs['a0']} a1={regs['a1']} t5={regs['t5']} t9={regs['t9']} "
        f"v0={regs['v0']} v1={regs['v1']} sp={regs['sp']} ra={regs['ra']} "
        f"r30={regs['r30']}{gprs}"
    )


def rtl(seq, pc="10000000", values=None, meta=None, instr="20000000",
        phase="retired", include_gprs=True):
    values = values or {}
    meta = meta or {"we": "0/0/00000000", "exc": "0/0", "bad": "00000000", "epc": "00000000", "bd": "0"}
    regs = {name: values.get(name, "00000000") for name in
            ("a0", "a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30")}
    gprs = f"gprs={gprs_blob(values)} " if include_gprs else ""
    return (
        f"RTL_FOCUS seq={seq} cycle={seq + 10} phase={phase} pc={pc} inst={instr} "
        f"a0={regs['a0']} a1={regs['a1']} t5={regs['t5']} t9={regs['t9']} "
        f"v0={regs['v0']} v1={regs['v1']} sp={regs['sp']} ra={regs['ra']} r30={regs['r30']} "
        f"{gprs}"
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
        ref.write_text(qemu(0) + "\n" + qemu(1, pc="10000004") + "\n")
        dut.write_text(ref.read_text())

        result = invoke(ref, dut)
        expect("valid full trace", result.returncode == 0, result.stdout)

        dut.write_text(qemu(0, values={"a0": "00000001"}) + "\n")
        result = invoke(ref, dut)
        expect("truncation rejection", result.returncode == 2 and "counts differ" in result.stdout, result.stdout)

        dut.write_text(qemu(0, values={"a0": "deadbeef"}) + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("selected GPR mutation rejection", result.returncode == 1 and "a0" in result.stdout, result.stdout)

        for register in ("a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30"):
            dut.write_text(qemu(0, values={register: "deadbeef"}) + "\n" + qemu(1, pc="10000004") + "\n")
            result = invoke(ref, dut)
            expect(f"{register} mutation rejection", result.returncode == 1 and register in result.stdout, result.stdout)

        dut.write_text(qemu(0, values={"r6": "deadbeef"}) + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("unselected GPR mutation rejection", result.returncode == 1 and "gprs" in result.stdout, result.stdout)

        dut.write_text(qemu(0, pc="10000008") + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("PC mutation rejection", result.returncode == 1 and "pc" in result.stdout, result.stdout)

        dut.write_text(qemu(0, instr="deadbeef") + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("instruction mutation rejection", result.returncode == 1 and "instr" in result.stdout, result.stdout)

        dut.write_text(qemu(0) + "\n" + qemu(0, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("duplicate sequence rejection", result.returncode == 2 and "duplicate" in result.stdout, result.stdout)

        dut.write_text(qemu(0, pc="10000004") + "\n" + qemu(1) + "\n")
        result = invoke(ref, dut)
        expect("reordered occurrence rejection", result.returncode == 1 and "pc" in result.stdout, result.stdout)

        dut.write_text(qemu(2) + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("non-contiguous sequence rejection", result.returncode == 2 and "non-contiguous" in result.stdout, result.stdout)

        dut.write_text(qemu(0, phase="pre") + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut)
        expect("phase mutation rejection", result.returncode == 1 and "phase" in result.stdout, result.stdout)

        dut.write_text(qemu(0) + "\n" + qemu(1, pc="10000004") + "\n" + qemu(2, pc="10000008") + "\n")
        result = invoke(ref, dut)
        expect("extra trailing record rejection", result.returncode == 2 and "counts differ" in result.stdout, result.stdout)

        ambiguous = root / "ambiguous.log"
        ambiguous.write_text(qemu(0) + "\n" + qemu(1) + "\n")
        result = invoke(ambiguous, ambiguous, "--checkpoint", "0x10000000")
        expect("ambiguous checkpoint rejection", result.returncode == 2 and "ambiguous" in result.stdout, result.stdout)

        dut.write_text(qemu(0, values={"a0": "deadbeef"}) + "\n" + qemu(1, pc="10000004") + "\n")
        result = invoke(ref, dut, "--checkpoint", "0x10000000", "--occurrence", "0")
        expect("checkpoint GPR mismatch rejection", result.returncode == 1, result.stdout)

        result = invoke(ref, dut, "--checkpoint", "0xdeadbeef", "--occurrence", "0")
        expect("missing checkpoint rejection", result.returncode == 2 and "absent" in result.stdout, result.stdout)

        missing_gprs = root / "missing-gprs.log"
        missing_gprs.write_text(qemu(0, include_gprs=False) + "\n")
        result = invoke(missing_gprs, missing_gprs, "--require-all-gprs")
        expect("required complete GPR snapshot", result.returncode == 2 and "complete GPR snapshot" in result.stdout, result.stdout)

        rtl_ref = root / "rtl_ref.log"
        rtl_dut = root / "rtl_dut.log"
        rtl_text = rtl(0) + "\n" + rtl(1, pc="10000004") + "\n"
        rtl_ref.write_text(rtl_text)
        rtl_dut.write_text(rtl_text)
        result = invoke(rtl_ref, rtl_dut)
        expect("RTL metadata full trace", result.returncode == 0, result.stdout)

        metadata_mutations = {
            "we": {"we": "1/4/deadbeef", "exc": "0/0", "bad": "00000000", "epc": "00000000", "bd": "0"},
            "exc": {"we": "0/0/00000000", "exc": "1/4", "bad": "00000000", "epc": "00000000", "bd": "0"},
            "bad": {"we": "0/0/00000000", "exc": "0/0", "bad": "deadbeef", "epc": "00000000", "bd": "0"},
            "epc": {"we": "0/0/00000000", "exc": "0/0", "bad": "00000000", "epc": "deadbeef", "bd": "0"},
            "bd": {"we": "0/0/00000000", "exc": "0/0", "bad": "00000000", "epc": "00000000", "bd": "1"},
        }
        for field, meta in metadata_mutations.items():
            rtl_dut.write_text(rtl(0, meta=meta) + "\n" + rtl(1, pc="10000004") + "\n")
            result = invoke(rtl_ref, rtl_dut)
            expect(f"RTL {field} metadata mutation rejection", result.returncode == 1 and field in result.stdout, result.stdout)

    print("FOCUS_DIFFERENTIAL_CHECKER_TEST_PASS")


if __name__ == "__main__":
    main()
