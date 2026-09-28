#!/usr/bin/env python3
"""Positive and adversarial tests for compare_linux_timer_clock.py."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
COMPARATOR = ROOT / "scripts" / "compare_linux_timer_clock.py"


def qemu(seq: int, pc: str = "10000000", count: str = "00000010") -> str:
    return json.dumps({
        "seq": seq, "pc": "0x" + pc, "count": "0x" + count,
        "compare": "0x00000020", "cause": "0x00000000",
        "status": "0x00400004",
    })


def rtl(kind: str = "LINUX_TIMER_HEARTBEAT", pc: str = "10000000", count: str = "00000010", line: int = 1, retire: str | None = None) -> str:
    retire_field = "" if retire is None else f"retire={retire} "
    return (f"{kind} cycle={line} pc={pc} {retire_field}count={count} compare=00000020 "
            "cause=00000000 status=00400004 intr=0 wait=0")


def run(qemu_text: str, rtl_text: str, step: int = 1, alignment: str = "count") -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory(prefix="timer-clock-comparator-") as temp:
        root = pathlib.Path(temp)
        qemu_path = root / "qemu.jsonl"
        rtl_path = root / "rtl.log"
        report = root / "report.md"
        qemu_path.write_text(qemu_text)
        rtl_path.write_text(rtl_text)
        return subprocess.run(
            [sys.executable, str(COMPARATOR), "--qemu", str(qemu_path),
             "--rtl", str(rtl_path), "--report", str(report),
             "--alignment", alignment,
             "--qemu-sequence-step", str(step)],
            text=True, capture_output=True, check=False,
        )


def main() -> int:
    good_qemu = qemu(1) + "\n" + qemu(2, pc="10000004", count="00000011") + "\n"
    good_rtl = rtl(line=1) + "\n" + rtl(pc="10000004", count="00000011", line=2) + "\n"
    result = run(good_qemu, good_rtl)
    assert result.returncode == 0, result.stdout + result.stderr

    changed = run(good_qemu, rtl(count="00000012") + "\n")
    assert changed.returncode == 1 and ("PC" in changed.stdout or "count" in changed.stdout), changed.stdout

    missing = run(good_qemu, rtl(pc="deadbeef") + "\n")
    assert missing.returncode == 1 and "PC" in missing.stdout, missing.stdout

    malformed = run(good_qemu, "LINUX_TIMER_HEARTBEAT cycle=1 pc=10000000 count=zzzz\n")
    assert malformed.returncode == 2 and "invalid count" in malformed.stdout + malformed.stderr, malformed.stdout

    gap = run(qemu(1) + "\n" + qemu(3, pc="10000004", count="00000011") + "\n",
              rtl() + "\n", step=1)
    assert gap.returncode == 2 and "sequence step" in gap.stdout + gap.stderr, gap.stdout

    retire_qemu = qemu(1000) + "\n" + qemu(2000, pc="10000004", count="00000011") + "\n"
    retire_rtl = rtl(retire="000003e8") + "\n" + rtl(pc="10000004", count="00000011", line=2, retire="000007d0") + "\n"
    result = run(retire_qemu, retire_rtl, step=1000, alignment="retire")
    assert result.returncode == 0, result.stdout + result.stderr

    missing_retire = run(retire_qemu, rtl() + "\n", step=1000, alignment="retire")
    assert missing_retire.returncode == 1 and "retire field" in missing_retire.stdout, missing_retire.stdout

    print("TIMER_CLOCK_COMPARISON_TEST_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
