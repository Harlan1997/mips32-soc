#!/usr/bin/env python3
"""Validate bounded Linux cache-owner diagnostic records."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


PREFIX = "LINUX_MEMORY_OWNER_"
HEX32 = re.compile(r"^[0-9a-fA-F]{8}$")
DECIMAL = re.compile(r"^[0-9]+$")
KINDS = {"L2", "L2_ARRAY", "DDR", "STORE"}
REQUIRED = {
    "L2": {"cycle", "line", "state", "s_ar", "s_r", "m_ar", "m_r"},
    "L2_ARRAY": {"cycle", "line", "valid", "tag", "words"},
    "DDR": {"cycle", "line", "backend", "word_index", "s_ar", "s_r", "words"},
    "STORE": {"cycle", "line", "cpu_req", "we", "addr", "data", "be"},
}


def parse_record(line: str, line_no: int) -> tuple[str, dict[str, str]] | None:
    if not line.startswith(PREFIX):
        return None
    fields = line.split()
    if len(fields) < 2:
        raise ValueError(f"line {line_no}: owner record has no fields")
    kind = fields[0][len(PREFIX) :]
    if kind not in KINDS:
        raise ValueError(f"line {line_no}: unknown owner record {kind!r}")
    record: dict[str, str] = {}
    for field in fields[1:]:
        if "=" not in field:
            raise ValueError(f"line {line_no}: malformed field {field!r}")
        key, value = field.split("=", 1)
        if not key or not value or value == "<NIL>" or "<NIL>" in value:
            raise ValueError(f"line {line_no}: invalid field {field!r}")
        if key in record:
            raise ValueError(f"line {line_no}: duplicate field {key!r}")
        record[key] = value
    missing = REQUIRED[kind] - record.keys()
    if missing:
        raise ValueError(f"line {line_no}: {kind} missing {sorted(missing)}")
    if not DECIMAL.fullmatch(record["cycle"]):
        raise ValueError(f"line {line_no}: cycle is not decimal")
    if not HEX32.fullmatch(record["line"]):
        raise ValueError(f"line {line_no}: line is not an 8-digit hex value")
    if kind == "DDR" and record["backend"] != "ddr_controller":
        raise ValueError(f"line {line_no}: unexpected backend {record['backend']!r}")
    return kind, record


def validate(path: Path) -> tuple[int, int]:
    counts = {kind: 0 for kind in KINDS}
    cycles: set[str] = set()
    lines: set[str] = set()
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line_no, line in enumerate(stream, 1):
            parsed = parse_record(line.rstrip("\n"), line_no)
            if parsed is None:
                continue
            kind, record = parsed
            counts[kind] += 1
            cycles.add(record["cycle"])
            lines.add(record["line"])
    if not any(counts.values()):
        raise ValueError("no Linux memory-owner records found")
    absent = [kind for kind, count in counts.items() if count == 0]
    if absent:
        raise ValueError(f"record groups absent: {', '.join(absent)}")
    if len(lines) != 1:
        raise ValueError(f"multiple target lines found: {sorted(lines)}")
    return sum(counts.values()), len(cycles)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        records, cycles = validate(args.log)
    except (OSError, ValueError) as exc:
        print(f"LINUX_MEMORY_OWNER_TRACE_FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"LINUX_MEMORY_OWNER_TRACE_PASS records={records} cycles={cycles}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
