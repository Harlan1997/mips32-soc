#!/usr/bin/env python3
"""
Auditor for QEMU focus trace logs.
Validates monotonic sequence numbers, absence of duplicate sequences,
expected phase labels, and presence of mandatory target PCs.
"""
import argparse
import re
import sys

LINE_RE = re.compile(
    r'^QEMU_FOCUS\s+'
    r'seq=(?P<seq>\d+)\s+'
    r'phase=(?P<phase>\w+)\s+'
    r'pc=(?P<pc>[0-9a-fA-F]{8})\s+'
    r'instr=(?P<instr>[0-9a-fA-F]{8})\s+'
    r'a0=(?P<a0>[0-9a-fA-F]{8})\s+'
    r'a1=(?P<a1>[0-9a-fA-F]{8})\s+'
    r't5=(?P<t5>[0-9a-fA-F]{8})\s+'
    r't9=(?P<t9>[0-9a-fA-F]{8})\s+'
    r'v0=(?P<v0>[0-9a-fA-F]{8})\s+'
    r'v1=(?P<v1>[0-9a-fA-F]{8})\s+'
    r'sp=(?P<sp>[0-9a-fA-F]{8})\s+'
    r'ra=(?P<ra>[0-9a-fA-F]{8})\s+'
    r'r30=(?P<r30>[0-9a-fA-F]{8})'
    r'(?:\s+mem=(?P<mem>[0-9]+/[0-9]+/[0-9]+/[0-9a-fA-F]{8}/[0-9a-fA-F]{8}/[0-9]+))?$'
)

MANDATORY_PCS = [
    "88a38c1c", "88a38c24",
    "88a38978", "88a3897c", "88a38980", "88a38984",
    "88a3898c", "88a38998"
]

def check_trace(log_path, require_mandatory_pcs=True):
    seen_seqs = set()
    observed_pcs = set()
    expected_seq = 0
    records = 0

    with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line.startswith("QEMU_FOCUS "):
                continue
            m = LINE_RE.match(line)
            if not m:
                print(f"ERROR: malformed QEMU_FOCUS line at {log_path}:{line_num}: {line}", file=sys.stderr)
                return 1

            seq = int(m.group("seq"))
            phase = m.group("phase")
            pc = m.group("pc").lower()

            if phase != "retired":
                print(f"ERROR: ambiguous or unexpected phase='{phase}' at {log_path}:{line_num}", file=sys.stderr)
                return 1

            if seq in seen_seqs:
                print(f"ERROR: duplicate sequence number {seq} at {log_path}:{line_num}", file=sys.stderr)
                return 1
            seen_seqs.add(seq)

            if seq != expected_seq:
                print(f"ERROR: non-monotonic or gapped sequence: expected {expected_seq}, got {seq} at {log_path}:{line_num}", file=sys.stderr)
                return 1
            expected_seq += 1

            observed_pcs.add(pc)
            records += 1

    if records == 0:
        print(f"ERROR: no QEMU_FOCUS records found in {log_path}", file=sys.stderr)
        return 1

    if require_mandatory_pcs:
        missing = [pc for pc in MANDATORY_PCS if pc not in observed_pcs]
        if missing:
            print(f"ERROR: missing mandatory target PCs in {log_path}: {missing}", file=sys.stderr)
            return 1

    print(f"QEMU focus trace check PASS: {records} valid records, {len(observed_pcs)} distinct PCs")
    return 0

def main():
    parser = argparse.ArgumentParser(description="Check QEMU focus trace format and completeness")
    parser.add_argument("log", help="Path to QEMU focus log")
    parser.add_argument("--no-require-mandatory", action="store_true", help="Do not require all mandatory checkpoint PCs")
    args = parser.parse_args()

    ret = check_trace(args.log, require_mandatory_pcs=not args.no_require_mandatory)
    sys.exit(ret)

if __name__ == "__main__":
    main()
