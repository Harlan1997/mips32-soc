#!/usr/bin/env python3
"""Compare normalized UART/VIC transaction streams.

The comparator deliberately ignores simulation cycle numbers and compares
causal transaction order plus architectural fields.  It accepts JSONL records
or the current RTL diagnostic lines so existing logs can be used while the
QEMU producer is being added.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


class TraceError(Exception):
    pass


UART_RE = re.compile(r"LINUX_UART_TRACE\s+cycle=(\d+)\s+paddr=([0-9a-fA-F]+)\s+data=([0-9a-fA-F]+)")
VIC_RE = re.compile(
    r"LINUX_VIC_TRACE\s+cycle=(\d+)\s+raw=([0-9a-fA-F]+)\s+"
    r"pending=([0-9a-fA-F]+)\s+enable=([0-9a-fA-F]+)\s+active=([0-9a-fA-F]+)\s+"
    r"irq=(\d+)\s+vec_id=([0-9a-fA-F]+)\s+vec_prio=([0-9a-fA-F]+)\s+"
    r"uart_irq=(\d+)\s+uart_rx_irq=(\d+)\s+uart_tx_irq=(\d+)\s+"
    r"cpu_accept=(\d+)\s+cause=([0-9a-fA-F]+)\s+status=([0-9a-fA-F]+)"
)


def parse_record(obj: object, kind: str, source: str, line_no: int) -> dict:
    if not isinstance(obj, dict):
        raise TraceError(f"{source}:{line_no}: record is not an object")
    expected = {
        "uart": ("addr", "data", "write", "width"),
        "vic": (
            "raw", "pending", "enable", "active", "irq", "vec_id", "vec_prio",
            "uart_irq", "uart_rx_irq", "uart_tx_irq", "cpu_accept", "cause", "status",
        ),
    }[kind]
    missing = [key for key in expected if key not in obj]
    if missing:
        raise TraceError(f"{source}:{line_no}: missing {','.join(missing)}")
    normalized = {key: obj[key] for key in expected}
    if kind == "uart":
        normalized["addr"] = int(normalized["addr"], 0) if isinstance(normalized["addr"], str) else int(normalized["addr"])
        normalized["data"] = int(normalized["data"], 0) if isinstance(normalized["data"], str) else int(normalized["data"])
        normalized["write"] = bool(normalized["write"])
        normalized["width"] = int(normalized["width"])
    else:
        for key in expected:
            value = normalized[key]
            normalized[key] = int(value, 0) if isinstance(value, str) else int(value)
    return normalized


def read_records(path: Path, kind: str) -> list[dict]:
    records: list[dict] = []
    for line_no, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("LINUX_UART_TRACE "):
            match = UART_RE.search(line)
            if not match:
                raise TraceError(f"{path}:{line_no}: malformed UART trace")
            if kind == "uart":
                records.append(parse_record({
                    "addr": "0x" + match.group(2), "data": "0x" + match.group(3),
                    "write": True, "width": 1,
                }, kind, str(path), line_no))
            continue
        if line.startswith("LINUX_VIC_TRACE "):
            match = VIC_RE.search(line)
            if not match:
                raise TraceError(f"{path}:{line_no}: malformed VIC trace")
            if kind == "vic":
                fields = ["raw", "pending", "enable", "active", "irq", "vec_id", "vec_prio",
                          "uart_irq", "uart_rx_irq", "uart_tx_irq", "cpu_accept", "cause", "status"]
                records.append(parse_record(dict(zip(fields, match.groups()[1:])), kind, str(path), line_no))
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise TraceError(f"{path}:{line_no}: expected JSONL or {kind.upper()} trace: {exc.msg}") from exc
        record_kind = obj.get("kind") if isinstance(obj, dict) else None
        if record_kind not in (None, kind):
            continue
        records.append(parse_record(obj, kind, str(path), line_no))
    if not records:
        raise TraceError(f"{path}: no {kind} records")
    return records


def compare(ref: list[dict], dut: list[dict]) -> None:
    if len(ref) != len(dut):
        raise TraceError(f"record count mismatch ref={len(ref)} dut={len(dut)}")
    for index, (left, right) in enumerate(zip(ref, dut)):
        if left != right:
            keys = sorted(set(left) | set(right))
            detail = ", ".join(f"{key}:{left.get(key)!r}!={right.get(key)!r}" for key in keys if left.get(key) != right.get(key))
            raise TraceError(f"first mismatch index={index}: {detail}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("uart", "vic"), required=True)
    parser.add_argument("--ref", type=Path, required=True)
    parser.add_argument("--dut", type=Path, required=True)
    args = parser.parse_args()
    try:
        ref = read_records(args.ref, args.kind)
        dut = read_records(args.dut, args.kind)
        compare(ref, dut)
    except (OSError, TraceError) as exc:
        print(f"PERIPHERAL_DIFF_FAIL {exc}", file=sys.stderr)
        return 1
    print(f"PERIPHERAL_DIFF_PASS kind={args.kind} records={len(ref)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
