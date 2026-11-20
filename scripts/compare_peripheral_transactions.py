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
UART_APB_RE = re.compile(
    r"^(\d+)\s+([01])\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)$"
)
VIC_RE = re.compile(
    r"LINUX_VIC_TRACE\s+cycle=(\d+)\s+raw=([0-9a-fA-F]+)\s+"
    r"pending=([0-9a-fA-F]+)\s+enable=([0-9a-fA-F]+)\s+active=([0-9a-fA-F]+)\s+"
    r"irq=(\d+)\s+vec_id=([0-9a-fA-F]+)\s+vec_prio=([0-9a-fA-F]+)\s+"
    r"uart_irq=(\d+)\s+uart_rx_irq=(\d+)\s+uart_tx_irq=(\d+)\s+"
    r"cpu_accept=(\d+)\s+cause=([0-9a-fA-F]+)\s+status=([0-9a-fA-F]+)"
)

VIC_HEX_FIELDS = {
    "raw", "pending", "enable", "active", "vec_id", "vec_prio",
}

VIC_FIELDS = (
    "raw", "pending", "enable", "active", "irq", "vec_id", "vec_prio",
    "uart_irq", "uart_rx_irq", "uart_tx_irq",
)


def parse_int(value: object, *, bare_hex: bool = False) -> int:
    if not isinstance(value, str):
        return int(value)
    if bare_hex and not value.lower().startswith(("0x", "+0x", "-0x")):
        return int(value, 16)
    return int(value, 0)


def parse_record(obj: object, kind: str, source: str, line_no: int) -> dict:
    if not isinstance(obj, dict):
        raise TraceError(f"{source}:{line_no}: record is not an object")
    expected = {
        "uart": ("addr", "data", "write", "width"),
        "vic": VIC_FIELDS,
    }[kind]
    missing = [key for key in expected if key not in obj]
    if missing:
        raise TraceError(f"{source}:{line_no}: missing {','.join(missing)}")
    normalized = {key: obj[key] for key in expected}
    if kind == "uart":
        normalized["addr"] = parse_int(normalized["addr"])
        normalized["data"] = parse_int(normalized["data"])
        normalized["write"] = bool(normalized["write"])
        normalized["width"] = parse_int(normalized["width"])
    else:
        for key in expected:
            normalized[key] = parse_int(normalized[key], bare_hex=key in VIC_HEX_FIELDS)
    return normalized


def read_records(path: Path, kind: str) -> list[dict]:
    records: list[dict] = []
    for line_no, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        # RTL's UART APB schedule is intentionally cycle-free at the
        # comparison boundary, but retains cycle/write/address/data columns
        # for diagnostics.  Parse it here so the same strict comparator can
        # compare complete UART accesses, including reads.
        if kind == "uart" and not line.startswith("{") and not line.startswith("LINUX_"):
            match = UART_APB_RE.fullmatch(line)
            if match:
                records.append(parse_record({
                    "addr": "0x" + match.group(3),
                    "data": "0x" + match.group(4),
                    "write": match.group(2) == "1",
                    "width": 4,
                }, kind, str(path), line_no))
                continue
            if line.startswith("#"):
                continue
            raise TraceError(f"{path}:{line_no}: malformed UART APB schedule")
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
        if "LINUX_VIC_TRACE " in line:
            match = VIC_RE.search(line)
            if not match:
                raise TraceError(f"{path}:{line_no}: malformed VIC trace")
            if kind == "vic":
                fields = ["raw", "pending", "enable", "active", "irq", "vec_id", "vec_prio",
                          "uart_irq", "uart_rx_irq", "uart_tx_irq", "cpu_accept", "cause", "status"]
                records.append(parse_record(dict(zip(fields, match.groups()[1:])), kind, str(path), line_no))
            continue
        if line.startswith("LINUX_"):
            # A combined RTL diagnostic log may contain the other peripheral
            # kind; only the requested normalized stream is comparable here.
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
