#!/usr/bin/env python3
"""Validate compact evidence for the declared QEMU Linux terminal workload."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


MARKERS = [
    "MIPS32_SOC_LINUX_BOOT_SUCCESS",
    "MIPS32_SOC_LINUX_GPIO_SUCCESS",
    "MIPS32_SOC_LINUX_MPROTECT_FAULT_SUCCESS",
    "MIPS32_SOC_LINUX_MPROTECT_SUCCESS",
    "MIPS32_SOC_LINUX_BRK_SUCCESS",
    "MIPS32_SOC_LINUX_SLEEP_SUCCESS",
    "MIPS32_SOC_LINUX_MMAP_SUCCESS",
    "MIPS32_SOC_LINUX_YIELD_SUCCESS",
    "MIPS32_SOC_LINUX_EXEC_SUCCESS",
    "MIPS32_SOC_LINUX_WAIT_STATUS_SUCCESS",
    "MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS",
    "MIPS32_SOC_LINUX_TERMINAL",
]
TERMINAL = MARKERS[-1]
FATAL = re.compile(
    r"Kernel panic|Oops:|BUG:|REGRESSION_TEST_FAILED|SIGABRT|"
    r"MIPS32_SOC_LINUX_[A-Z0-9_]+_FAILURE",
    re.IGNORECASE,
)


def uart_bytes(path: Path) -> bytes:
    data = bytearray()
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"invalid peripheral JSON at line {line_number}: {exc}") from exc
            if record.get("kind") != "uart":
                continue
            if not record.get("write"):
                continue
            value = record.get("data")
            if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]+", value):
                raise ValueError(f"invalid UART data at line {line_number}: {value!r}")
            data.append(int(value, 16) & 0xFF)
    return bytes(data)


def normalize(data: bytes) -> str:
    return data.replace(b"\r\n", b"\n").decode("utf-8", errors="replace")


def marker_offsets(stream: str) -> dict[str, int]:
    offsets: dict[str, int] = {}
    previous = -1
    for marker in MARKERS:
        offset = stream.find(marker, previous + 1)
        if offset < 0:
            raise ValueError(f"missing or out-of-order marker: {marker}")
        offsets[marker] = offset
        previous = offset
    return offsets


def validate(name: str, stream: str) -> dict[str, object]:
    if FATAL.search(stream):
        match = FATAL.search(stream)
        raise ValueError(f"fatal diagnostic in {name}: {match.group(0)}")
    offsets = marker_offsets(stream)
    terminal_count = stream.count(TERMINAL)
    if terminal_count != 1:
        raise ValueError(f"{name} terminal marker count={terminal_count}, expected 1")
    return {
        "bytes": len(stream.encode("utf-8")),
        "terminal_count": terminal_count,
        "marker_offsets": offsets,
        "marker_counts": {marker: stream.count(marker) for marker in MARKERS},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stdout", type=Path, required=True)
    parser.add_argument("--peripheral", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    stdout = args.stdout.read_bytes()
    uart = uart_bytes(args.peripheral)
    stdout_evidence = validate("QEMU stdout", normalize(stdout))
    uart_evidence = validate("QEMU UART", normalize(uart))
    if normalize(stdout).count(TERMINAL) != normalize(uart).count(TERMINAL):
        raise ValueError("stdout and UART terminal marker counts differ")
    result = {
        "result": "PASS",
        "terminal_marker": TERMINAL,
        "stdout": stdout_evidence,
        "uart": uart_evidence,
        "required_markers": MARKERS,
        "uart_record_bytes": len(uart),
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("QEMU Linux terminal evidence: PASS")
    print(f"required_markers={len(MARKERS)} terminal_count=1 uart_bytes={len(uart)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        print(f"QEMU Linux terminal evidence: FAIL: {exc}")
        raise SystemExit(1)
