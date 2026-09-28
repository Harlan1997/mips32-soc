#!/usr/bin/env python3
"""Classify the bounded RTL Linux timer/WAIT progress window.

This is a diagnostic classifier, not a boot pass.  It only accepts records
that carry an architectural cycle and reports the first useful boundary seen
in the current-source simulator log.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


HEX_FIELDS = {
    "pc", "ifpc", "wbpc", "resume", "epc", "status", "cause", "count",
    "compare", "badv", "data", "wdata", "inst", "rd", "cycle",
}


def fields(line: str) -> dict[str, str]:
    return dict(re.findall(r"([A-Za-z][A-Za-z0-9_]*)=([^\s]+)", line))


def number(value: str) -> int | None:
    try:
        return int(value, 0)
    except ValueError:
        try:
            return int(value, 16)
        except ValueError:
            return None


def read_records(path: Path):
    progress = []
    waits = []
    interrupts = []
    cp0_writes = []
    cp0_reads = []
    heartbeats = []
    bounded = []
    malformed = []
    for line_no, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        line = raw.replace("\r", "")
        if "LINUX_PROGRESS_TRACE " in line:
            rec = fields(line)
            if number(rec.get("cycle", "")) is None or number(rec.get("pc", "")) is None:
                malformed.append((line_no, "progress"))
            else:
                progress.append((line_no, rec))
        if "LINUX_WAIT_TRACE " in line:
            rec = fields(line)
            if number(rec.get("cycle", "")) is None:
                malformed.append((line_no, "wait"))
            else:
                waits.append((line_no, rec))
        if "LINUX_EXCEPTION_TRACE " in line:
            rec = fields(line)
            if rec.get("intr") == "1" and rec.get("accept") == "1":
                interrupts.append((line_no, rec))
        if "LINUX_CP0_TRACE " in line:
            rec = fields(line)
            if number(rec.get("cycle", "")) is None or number(rec.get("data", "")) is None:
                malformed.append((line_no, "cp0"))
            else:
                cp0_writes.append((line_no, rec))
        if "LINUX_CP0_READ_TRACE " in line:
            rec = fields(line)
            if number(rec.get("cycle", "")) is None or number(rec.get("data", "")) is None:
                malformed.append((line_no, "cp0-read"))
            else:
                cp0_reads.append((line_no, rec))
        if "LINUX_TIMER_HEARTBEAT " in line:
            rec = fields(line)
            if number(rec.get("cycle", "")) is None:
                malformed.append((line_no, "heartbeat"))
            else:
                heartbeats.append((line_no, rec))
        if "LINUX_BOUNDED_END_STATE " in line:
            bounded.append((line_no, fields(line)))
    return progress, waits, interrupts, cp0_writes, cp0_reads, heartbeats, bounded, malformed


def classify(progress, waits, interrupts, heartbeats, udelay_pcs):
    if not progress:
        return "NO_PROGRESS_TRACE"
    pcs = Counter(int(rec["pc"], 16) for _, rec in progress if re.fullmatch(r"[0-9a-fA-F]+", rec["pc"]))
    dominant = pcs.most_common(4)
    if not waits:
        if any(pc in udelay_pcs for pc, _ in dominant):
            return "PRE_WAIT_UDELAY_LOOP"
        return "PRE_WAIT_PROGRESS"
    if interrupts:
        last_wait = max(number(rec.get("cycle", "0")) or 0 for _, rec in waits)
        post = [rec for _, rec in progress if (number(rec.get("cycle", "0")) or 0) > last_wait]
        if not post:
            return "WAIT_WAKEUP_UNOBSERVED"
        return "WAIT_WAKEUP_PROGRESS"
    if heartbeats:
        return "WAIT_WITHOUT_ACCEPTED_INTERRUPT"
    return "WAIT_NO_TIMER_HEARTBEAT"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument(
        "--udelay-pc",
        default="88a436d0,88a436d4",
        help="comma-separated PC values used for the known __udelay loop",
    )
    args = parser.parse_args()
    if not args.log.is_file():
        print(f"missing log: {args.log}", file=sys.stderr)
        return 2
    try:
        udelay_pcs = {int(value, 16) for value in args.udelay_pc.split(",") if value}
    except ValueError:
        print("invalid --udelay-pc", file=sys.stderr)
        return 2

    progress, waits, interrupts, cp0_writes, cp0_reads, heartbeats, bounded, malformed = read_records(args.log)
    count_reads = [rec for _, rec in cp0_reads if rec.get("cp0rd") == "9"]
    read_mismatch = [rec for rec in count_reads if rec.get("data", "").lower() != rec.get("count", "").lower()]
    count_values = [number(rec.get("data", "")) for rec in count_reads]
    count_values = [value for value in count_values if value is not None]
    count_backsteps = sum(1 for before, after in zip(count_values, count_values[1:]) if after < before)
    status = "PASS" if progress and not malformed else "FAIL"
    classification = classify(progress, waits, interrupts, heartbeats, udelay_pcs)
    cycles = [number(rec.get("cycle", "0")) or 0 for _, rec in progress]
    pcs = Counter(rec.get("pc", "") for _, rec in progress)
    first_cycle = min(cycles) if cycles else 0
    last_cycle = max(cycles) if cycles else 0
    lines = [
        "# Linux Timer/WAIT Diagnostic",
        "",
        f"- Result: `{status}` (diagnostic only)",
        f"- Classification: `{classification}`",
        f"- Progress records: `{len(progress)}`",
        f"- WAIT records: `{len(waits)}`",
        f"- Accepted interrupt records: `{len(interrupts)}`",
        f"- CP0 write records: `{len(cp0_writes)}`",
        f"- CP0 Count/Compare read records: `{len(cp0_reads)}` (`Count` reads: `{len(count_reads)}`)",
        f"- Count read vs internal Count mismatches: `{len(read_mismatch)}`",
        f"- Count read backsteps: `{count_backsteps}` (wraparound is not expected in this bounded run)",
        f"- Timer heartbeat records: `{len(heartbeats)}`",
        f"- Bounded-end records: `{len(bounded)}`",
        f"- Progress cycle range: `{first_cycle}..{last_cycle}`",
        "- Dominant PCs: " + ", ".join(f"`0x{pc.lower().zfill(8)}` x{count}" for pc, count in pcs.most_common(6)),
        "",
        "This report classifies observability only. It does not imply generic Linux, userspace, or differential closure.",
    ]
    if malformed:
        lines.extend(["", "Malformed records:"])
        lines.extend(f"- line {line_no}: {kind}" for line_no, kind in malformed[:20])
    if read_mismatch:
        lines.extend(["", "First Count read mismatch:", f"- `{read_mismatch[0]}`"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(lines) + "\n")
    print(f"LINUX_TIMER_WAIT_ANALYSIS_{status} classification={classification} progress={len(progress)} waits={len(waits)} interrupts={len(interrupts)}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
