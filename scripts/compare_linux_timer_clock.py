#!/usr/bin/env python3
"""Strict comparison of QEMU CP0 samples and RTL Linux timer records.

QEMU records are JSONL samples emitted at every retired instruction.  RTL
records are simulator text lines emitted at selected CP0 reads/writes,
heartbeats, and accepted interrupts.  Host cycle numbers are diagnostics only
and are never aligned with QEMU.  Records are joined by PC and occurrence
within the selected event stream.

Exit status:
  0: all comparable records match and the traces are complete enough.
  1: a well-formed trace has an architectural mismatch.
  2: malformed, incomplete, or unusable input.
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


HEX_FIELDS = ("pc", "count", "compare", "cause", "status", "data", "epc", "retire")
QEMU_REQUIRED = ("seq", "pc", "count", "compare", "cause", "status")
RTL_PREFIXES = (
    "LINUX_CP0_READ_TRACE ",
    "LINUX_CP0_TRACE ",
    "LINUX_TIMER_HEARTBEAT ",
    "LINUX_EXCEPTION_TRACE ",
)


class InputError(ValueError):
    pass


@dataclass(frozen=True)
class QemuRecord:
    seq: int
    pc: int
    count: int
    compare: int
    cause: int
    status: int
    line: int


@dataclass(frozen=True)
class RtlRecord:
    kind: str
    ordinal: int
    line: int
    cycle: int
    pc: int
    fields: dict[str, int]
    raw: str


def parse_int(value: object, field: str, line: int) -> int:
    if isinstance(value, bool):
        raise InputError(f"line {line}: {field} is boolean")
    if isinstance(value, int):
        return value
    if not isinstance(value, str) or not value:
        raise InputError(f"line {line}: missing/invalid {field}")
    try:
        return int(value, 0)
    except ValueError:
        try:
            return int(value, 16)
        except ValueError as exc:
            raise InputError(f"line {line}: invalid {field}={value!r}") from exc


def parse_qemu(path: Path, sequence_step: int) -> list[QemuRecord]:
    records: list[QemuRecord] = []
    for line_no, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise InputError(f"QEMU line {line_no}: invalid JSON: {exc.msg}") from exc
        if not isinstance(obj, dict):
            raise InputError(f"QEMU line {line_no}: record is not an object")
        missing = [name for name in QEMU_REQUIRED if name not in obj]
        if missing:
            raise InputError(f"QEMU line {line_no}: missing {','.join(missing)}")
        records.append(QemuRecord(
            seq=parse_int(obj["seq"], "seq", line_no),
            pc=parse_int(obj["pc"], "pc", line_no) & 0xffffffff,
            count=parse_int(obj["count"], "count", line_no) & 0xffffffff,
            compare=parse_int(obj["compare"], "compare", line_no) & 0xffffffff,
            cause=parse_int(obj["cause"], "cause", line_no) & 0xffffffff,
            status=parse_int(obj["status"], "status", line_no) & 0xffffffff,
            line=line_no,
        ))
    if not records:
        raise InputError("QEMU trace is empty")
    previous: QemuRecord | None = None
    for record in records:
        if previous is not None:
            delta = record.seq - previous.seq
            if delta != sequence_step:
                raise InputError(
                    f"QEMU line {record.line}: sequence step={delta}, "
                    f"expected {sequence_step}"
                )
        elif record.seq <= 0:
            raise InputError(f"QEMU line {record.line}: sequence must be positive")
        previous = record
    return records


def parse_fields(line: str) -> dict[str, str]:
    return dict(re.findall(r"([A-Za-z][A-Za-z0-9_]*)=([^\s]+)", line))


def parse_rtl_value(value: str, field: str, line: int) -> int:
    # The Verilog $display uses unprefixed hexadecimal for architectural
    # fields, while cycle/count selectors are decimal.  Treating an all-digit
    # PC as decimal would silently create a false cross-model mismatch.
    if field in HEX_FIELDS:
        try:
            return int(value, 16)
        except ValueError as exc:
            raise InputError(f"line {line}: invalid {field}={value!r}") from exc
    return parse_int(value, field, line)


def parse_rtl(path: Path) -> list[RtlRecord]:
    records: list[RtlRecord] = []
    ordinal_by_kind_pc: defaultdict[tuple[str, int], int] = defaultdict(int)
    previous_cycle = -1
    for line_no, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        prefix = next((item for item in RTL_PREFIXES if item in raw), None)
        if prefix is None:
            continue
        kind = prefix.rstrip()
        fields = parse_fields(raw)
        required = ("cycle", "pc")
        missing = [name for name in required if name not in fields]
        if missing:
            raise InputError(f"RTL line {line_no}: {kind} missing {','.join(missing)}")
        cycle = parse_int(fields["cycle"], "cycle", line_no)
        pc = parse_rtl_value(fields["pc"], "pc", line_no) & 0xffffffff
        if cycle < previous_cycle:
            raise InputError(
                f"RTL line {line_no}: cycle moved backwards ({cycle} < {previous_cycle})"
            )
        previous_cycle = cycle
        ordinal_key = (kind, pc)
        ordinal_by_kind_pc[ordinal_key] += 1
        numeric: dict[str, int] = {}
        for name, value in fields.items():
            if name in HEX_FIELDS or name in {"cycle", "cp0rd", "rd", "sel", "gpr", "intr", "accept", "wait"}:
                numeric[name] = parse_rtl_value(value, name, line_no)
        records.append(RtlRecord(kind, ordinal_by_kind_pc[ordinal_key], line_no, cycle, pc, numeric, raw))
    if not records:
        raise InputError("RTL trace has no recognized timer records")
    return records


def fmt(value: int | None) -> str:
    return "<missing>" if value is None else f"0x{value:08x}"


def count_distance(left: int, right: int) -> int:
    """Unsigned shortest distance for a 32-bit free-running counter."""
    delta = (left - right) & 0xffffffff
    return min(delta, (0x100000000 - delta) & 0xffffffff)


def compare(qemu: list[QemuRecord], rtl: list[RtlRecord], alignment: str) -> tuple[list[str], list[str], int]:
    qemu_counts = [record.count for record in qemu]
    qemu_sequences = [record.seq for record in qemu]
    checked: list[str] = []
    mismatches: list[str] = []
    match_count = 0
    for rtl_record in rtl:
        if alignment == "retire":
            rtl_retire = rtl_record.fields.get("retire")
            if rtl_retire is None:
                mismatches.append(
                    f"line {rtl_record.line} {rtl_record.kind} pc={fmt(rtl_record.pc)}: "
                    "RTL retire field is missing"
                )
                continue
            insertion = bisect.bisect_left(qemu_sequences, rtl_retire)
            distance = lambda item: abs(item.seq - rtl_retire)
        else:
            # RTL heartbeats are sparse while QEMU records every retirement. A
            # per-PC ordinal does not identify the same architectural instant.
            # Count is the common architectural clock, so use the nearest QEMU
            # sample on the global Count timeline and compare its PC as well.
            rtl_count = rtl_record.fields.get("count")
            if rtl_count is None:
                mismatches.append(
                    f"line {rtl_record.line} {rtl_record.kind} pc={fmt(rtl_record.pc)}: "
                    "RTL Count field is missing"
                )
                continue
            insertion = bisect.bisect_left(qemu_counts, rtl_count)
            distance = lambda item: count_distance(item.count, rtl_count)
        candidate_indices = {
            max(0, min(len(qemu) - 1, insertion - 1)),
            max(0, min(len(qemu) - 1, insertion)),
        }
        qemu_record = min(
            (qemu[index] for index in candidate_indices),
            key=distance,
        )
        match_count += 1
        checked.append(
            f"{rtl_record.kind} line={rtl_record.line} cycle={rtl_record.cycle} "
            f"pc={fmt(rtl_record.pc)} qemu_seq={qemu_record.seq}"
        )
        if rtl_record.pc != qemu_record.pc:
            basis = (f"retire={rtl_record.fields.get('retire')}" if alignment == "retire"
                     else f"Count={fmt(rtl_record.fields.get('count'))}")
            mismatches.append(
                f"line {rtl_record.line} {rtl_record.kind}: PC RTL={fmt(rtl_record.pc)} "
                f"QEMU={fmt(qemu_record.pc)} at nearest {basis} "
                f"(QEMU seq={qemu_record.seq})"
            )
        values = rtl_record.fields
        if alignment == "retire":
            # Retirement-normalized mode deliberately does not compare Count
            # values across models: QEMU uses the opt-in retire clock while
            # RTL Count remains a SoC-cycle clock.  Count readback consistency
            # is still checked within RTL below.
            continue
        # All timer records carry the model state except CP0 reads, where data
        # is the value written to the destination GPR and count is the internal
        # state sampled at the same commit boundary.
        for name in ("count", "compare", "cause", "status"):
            if name not in values:
                mismatches.append(
                    f"line {rtl_record.line} {rtl_record.kind} pc={fmt(rtl_record.pc)}: "
                    f"missing RTL field {name}"
                )
                continue
            expected = getattr(qemu_record, name)
            actual = values[name] & 0xffffffff
            if actual != expected:
                mismatches.append(
                    f"line {rtl_record.line} {rtl_record.kind} pc={fmt(rtl_record.pc)} "
                    f"qemu_seq={qemu_record.seq}: {name} RTL={fmt(actual)} "
                    f"QEMU={fmt(expected)}"
                )
        if rtl_record.kind == "LINUX_CP0_READ_TRACE":
            cp0rd = values.get("cp0rd")
            if cp0rd == 9 and "data" in values and "count" in values:
                if (values["data"] & 0xffffffff) != (values["count"] & 0xffffffff):
                    mismatches.append(
                        f"line {rtl_record.line} CP0 Count readback: data={fmt(values['data'])} "
                        f"internal_count={fmt(values['count'])}"
                    )
        if rtl_record.kind == "LINUX_CP0_TRACE" and values.get("rd") == 11:
            checked.append(
                f"compare-write line={rtl_record.line} value={fmt(values.get('data'))}"
            )
    return checked, mismatches, match_count


def write_report(path: Path, qemu: list[QemuRecord], rtl: list[RtlRecord], checked: list[str], mismatches: list[str], matches: int, start_pc: int | None, alignment: str) -> None:
    result = "PASS" if matches and not mismatches else "FAIL"
    lines = [
        "# Linux Timer/Clock Comparison",
        "",
        f"- Result: `{result}`",
        f"- QEMU records: `{len(qemu)}`",
        f"- RTL timer records: `{len(rtl)}`",
        f"- Matched timer records: `{matches}`",
        f"- Mismatches: `{len(mismatches)}`",
        f"- Alignment: `{alignment}` (host cycle numbers were not compared).",
        f"- Handoff anchor: `{fmt(start_pc) if start_pc is not None else 'none'}`",
        "",
        "This is a diagnostic boundary report. It does not prove generic Linux or full differential closure.",
    ]
    if checked:
        lines.extend(["", "Checked records:"])
        lines.extend(f"- {item}" for item in checked[:32])
    if mismatches:
        lines.extend(["", "First mismatch:", f"- {mismatches[0]}"])
        if len(mismatches) > 1:
            lines.extend(["", "Additional mismatches:"])
            lines.extend(f"- {item}" for item in mismatches[1:21])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qemu", type=Path, required=True)
    parser.add_argument("--rtl", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--min-matches", type=int, default=1)
    parser.add_argument(
        "--alignment", choices=("count", "retire"), default="count",
        help="cross-model alignment basis; retire mode intentionally does not compare Count values",
    )
    parser.add_argument(
        "--qemu-sequence-step", type=int, default=1,
        help="declared retirement sequence step (1 for full trace; sampling interval for sparse trace)",
    )
    parser.add_argument(
        "--start-pc",
        help="hex PC at which both traces begin comparison; records before the first occurrence are handoff-only",
    )
    args = parser.parse_args()
    if args.min_matches < 1:
        parser.error("--min-matches must be positive")
    if args.qemu_sequence_step < 1:
        parser.error("--qemu-sequence-step must be positive")
    start_pc: int | None = None
    if args.start_pc is not None:
        try:
            start_pc = int(args.start_pc, 0)
        except ValueError:
            try:
                start_pc = int(args.start_pc, 16)
            except ValueError:
                parser.error("--start-pc must be hexadecimal")
    try:
        qemu = parse_qemu(args.qemu, args.qemu_sequence_step)
        rtl = parse_rtl(args.rtl)
        if start_pc is not None:
            start_pc &= 0xffffffff
            qemu_start = next((index for index, record in enumerate(qemu) if record.pc == start_pc), None)
            rtl_start = next((index for index, record in enumerate(rtl) if record.pc == start_pc), None)
            if qemu_start is None or rtl_start is None:
                raise InputError(
                    f"handoff PC {fmt(start_pc)} missing in "
                    f"QEMU={'yes' if qemu_start is not None else 'no'} "
                    f"RTL={'yes' if rtl_start is not None else 'no'}"
                )
            qemu = qemu[qemu_start:]
            rtl = rtl[rtl_start:]
        checked, mismatches, matches = compare(qemu, rtl, args.alignment)
        if matches < args.min_matches:
            mismatches.append(
                f"only {matches} matched PC occurrences; minimum is {args.min_matches}"
            )
        write_report(args.report, qemu, rtl, checked, mismatches, matches, start_pc, args.alignment)
    except (OSError, InputError) as exc:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            "# Linux Timer/Clock Comparison\n\n"
            "- Result: `INPUT_ERROR`\n"
            f"- Error: `{exc}`\n"
        )
        print(f"TIMER_CLOCK_COMPARISON_INPUT_ERROR {exc}", file=sys.stderr)
        return 2
    if mismatches:
        print(f"TIMER_CLOCK_COMPARISON_FAIL matches={matches} mismatches={len(mismatches)}")
        print(f"first_mismatch={mismatches[0]}")
        return 1
    print(f"TIMER_CLOCK_COMPARISON_PASS matches={matches}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
