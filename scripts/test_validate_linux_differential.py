#!/usr/bin/env python3
"""Negative and positive tests for the Linux differential contract checker."""

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts/validate_linux_differential.py"


def run(*args):
    return subprocess.run(["python3", str(CHECKER), *args],
                          text=True, capture_output=True)


def manifest_args():
    return [
        "--set", "git_commit=test",
        "--set", "git_dirty_status_hash=dirty",
        "--set", "entropy_mode=deterministic",
        "--set", "entropy_seed_id=seed-a",
        "--set", "entropy_seed_width=256",
        "--set", "entropy_contract_version=uhi-rng-v1",
        "--set", "qemu_machine=mips32-soc-ref",
        "--set", "rtl_defines=SOC_MMU_ENABLE=1",
        "--set", "linux_cmdline=console=null",
        "--set", "retire_bound=3",
        "--set", "cycle_bound=100",
        "--set", "timeout_bound=2s",
        "--set", "terminal_condition=record_bound",
        "--set", "qemu_sha256=qemu",
        "--set", "qemu_plugin_sha256=plugin",
        "--set", "rtl_simulator_sha256=sim",
        "--set", "rtl_source_identity_sha256=rtl",
        "--set", "kernel_sha256=kernel",
        "--set", "dtb_sha256=dtb",
        "--set", "bootrom_sha256=bootrom",
        "--set", "ddr_image_sha256=ddr",
        "--set", "root_image_sha256=unused",
    ]


def record(sequence):
    return {
        "retire_seq": sequence, "schema": "00010000", "pc": "80000000",
        "instr": "00000000", "next_pc": "80000004", "gpr_we": 0,
        "gpr_addr": 0, "gpr_data": "00000000", "cp0_we": 0, "cp0_addr": 0,
        "cp0_sel": 0, "cp0_data": "00000000", "fpr_state": "0" * 256,
        "fcsr_state": "00000000", "mem_valid": 0, "mem_read": 0,
        "mem_write": 0, "mem_addr": "00000000", "mem_wdata": "00000000",
        "mem_be": "f", "mem_rdata": "xxxxxxxx", "except": 0,
        "except_code": 0, "bd": 0, "eret": 0,
    }


def main():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        manifest = root / "manifest.json"
        result = run("create", "--output", str(manifest), *manifest_args())
        assert result.returncode == 0, result.stderr
        assert run("validate-manifest", str(manifest)).returncode == 0

        valid = root / "valid.jsonl"
        valid.write_text("\n".join(json.dumps(record(i)) for i in range(3)) + "\n")
        assert run("validate-trace", str(valid), "--max-records", "3",
                   "--exact-records", "3").returncode == 0

        for name, records in {
            "reordered": [record(0), record(2)],
            "duplicate": [record(0), record(0)],
            "missing": [dict(record(0), **{"pc": "bad"})],
        }.items():
            fixture = root / f"{name}.jsonl"
            fixture.write_text("\n".join(json.dumps(item) for item in records) + "\n")
            assert run("validate-trace", str(fixture), "--max-records", "3").returncode != 0

        malformed = root / "malformed.jsonl"
        malformed.write_text("{\n")
        assert run("validate-trace", str(malformed), "--max-records", "3").returncode != 0
    print("validate_linux_differential tests: PASS")


if __name__ == "__main__":
    main()
