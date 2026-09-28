#!/usr/bin/env python3
"""Strict comparator for QEMU and RTL architectural focus records.

The input logs may contain ordinary simulator output, but every line beginning
with ``QEMU_FOCUS`` or ``RTL_FOCUS`` must be a complete, well-formed record.
Records are compared in order. Truncation, gaps, duplicates, ambiguous PC
occurrences, and unrequested prefix/subsequence matching are errors.
"""

import argparse
import re
import sys
from collections import Counter

GPRS = ["a0", "a1", "t5", "t9", "v0", "v1", "sp", "ra", "r30"]
RTL_META = ["we", "exc", "bad", "epc", "bd"]
COMMON_FIELDS = ["pc", "instr", "phase", "occurrence"] + GPRS

QEMU_RE = re.compile(
    r"^QEMU_FOCUS\s+"
    r"seq=(?P<seq>\d+)\s+phase=(?P<phase>\w+)\s+"
    r"pc=(?P<pc>[0-9a-fA-F]{8})\s+instr=(?P<instr>[0-9a-fA-F]{8})\s+"
    r"a0=(?P<a0>[0-9a-fA-F]{8})\s+a1=(?P<a1>[0-9a-fA-F]{8})\s+"
    r"t5=(?P<t5>[0-9a-fA-F]{8})\s+t9=(?P<t9>[0-9a-fA-F]{8})\s+"
    r"v0=(?P<v0>[0-9a-fA-F]{8})\s+v1=(?P<v1>[0-9a-fA-F]{8})\s+"
    r"sp=(?P<sp>[0-9a-fA-F]{8})\s+ra=(?P<ra>[0-9a-fA-F]{8})\s+"
    r"r30=(?P<r30>[0-9a-fA-F]{8})"
    r"(?:\s+mem=(?P<mem>[0-9]+/[0-9]+/[0-9]+/[0-9a-fA-F]{8}/[0-9a-fA-F]{8}/[0-9]+))?"
    r"(?:\s+occ=(?P<occurrence>\d+))?$"
)

RTL_RE = re.compile(
    r"^RTL_FOCUS\s+"
    r"seq=(?P<seq>\d+)\s+cycle=(?P<cycle>\d+)\s+phase=(?P<phase>\w+)\s+"
    r"pc=(?P<pc>[0-9a-fA-F]{8})\s+inst=(?P<instr>[0-9a-fA-F]{8})\s+"
    r"a0=(?P<a0>[0-9a-fA-F]{8})\s+a1=(?P<a1>[0-9a-fA-F]{8})\s+"
    r"t5=(?P<t5>[0-9a-fA-F]{8})\s+t9=(?P<t9>[0-9a-fA-F]{8})\s+"
    r"v0=(?P<v0>[0-9a-fA-F]{8})\s+v1=(?P<v1>[0-9a-fA-F]{8})\s+"
    r"sp=(?P<sp>[0-9a-fA-F]{8})\s+ra=(?P<ra>[0-9a-fA-F]{8})\s+"
    r"r30=(?P<r30>[0-9a-fA-F]{8})\s+"
    r"we=(?P<we>[01]/[0-9]+/[0-9a-fA-F]{8})\s+"
    r"except=(?P<exc>[01]/[0-9]+)\s+bad=(?P<bad>[0-9a-fA-F]{8})\s+"
    r"epc=(?P<epc>[0-9a-fA-F]{8})\s+bd=(?P<bd>[01])"
    r"(?:\s+occ=(?P<occurrence>\d+))?$"
)


class TraceError(ValueError):
    """A trace is malformed or incomplete."""


def _normalise(record, trace_type, line_no):
    for key in ["pc", "instr", *GPRS, "bad", "epc"]:
        if key in record and record[key] is not None:
            record[key] = record[key].lower()
    record["seq"] = int(record["seq"])
    if record.get("occurrence") is not None:
        record["occurrence"] = int(record["occurrence"])
    record["trace_type"] = trace_type
    record["line_no"] = line_no
    return record


def parse_trace(path):
    records = []
    trace_type = None
    with open(path, "r", encoding="utf-8", errors="replace") as stream:
        for line_no, raw in enumerate(stream, 1):
            line = raw.strip()
            if line.startswith("QEMU_FOCUS "):
                match = QEMU_RE.fullmatch(line)
                if not match:
                    raise TraceError(f"malformed QEMU_FOCUS record at {path}:{line_no}")
                if trace_type not in (None, "qemu"):
                    raise TraceError(f"mixed trace types at {path}:{line_no}")
                trace_type = "qemu"
                records.append(_normalise(match.groupdict(), trace_type, line_no))
            elif line.startswith("RTL_FOCUS "):
                match = RTL_RE.fullmatch(line)
                if not match:
                    raise TraceError(f"malformed RTL_FOCUS record at {path}:{line_no}")
                if trace_type not in (None, "rtl"):
                    raise TraceError(f"mixed trace types at {path}:{line_no}")
                trace_type = "rtl"
                records.append(_normalise(match.groupdict(), trace_type, line_no))

    if not records:
        raise TraceError(f"no focus records found in {path}")

    expected_seq = 0
    seen_seq = set()
    occurrences = Counter()
    for record in records:
        seq = record["seq"]
        if seq in seen_seq:
            raise TraceError(f"duplicate sequence number {seq} in {path}")
        if seq != expected_seq:
            raise TraceError(
                f"non-contiguous sequence in {path}: expected {expected_seq}, got {seq}"
            )
        seen_seq.add(seq)
        expected_seq += 1

        pc = record["pc"]
        derived_occurrence = occurrences[pc]
        occurrences[pc] += 1
        explicit_occurrence = record.get("occurrence")
        if explicit_occurrence is not None and explicit_occurrence != derived_occurrence:
            raise TraceError(
                f"wrong occurrence for PC 0x{pc} in {path}: "
                f"expected {derived_occurrence}, got {explicit_occurrence}"
            )
        record["occurrence"] = derived_occurrence
        if record["phase"] not in ("pre", "post", "retired"):
            raise TraceError(
                f"unsupported phase {record['phase']!r} in {path}:{record['line_no']}"
            )
    return records, trace_type


def classify_mismatch(field, ref, dut):
    pc = ref.get("pc", "????????")
    if field in ("pc", "instr", "phase", "occurrence"):
        return f"retire identity mismatch at 0x{pc}: fetch, delay-slot, flush, replay, or alignment error"
    if field == "a0":
        return f"a0 divergence at PC 0x{pc}: producer writeback/forwarding or replay error"
    if field in ("t9", "sp"):
        return f"{field} divergence at PC 0x{pc}: call/return, stack, or prior memory error"
    if field == "a1":
        if ref.get("a0") == dut.get("a0") and ref.get("t9") == dut.get("t9"):
            return "a1 differs despite equal operands: ALU or retirement path error"
        return "a1 differs after an operand divergence"
    if field == "bad":
        return f"BadVAddr mismatch at PC 0x{pc}: translation fault/replay ownership error"
    if field in ("epc", "bd", "exc"):
        return f"exception metadata mismatch at PC 0x{pc}: precise exception or delay-slot attribution error"
    return f"{field} divergence at PC 0x{pc}"


def compare_record_pair(ref, dut, compare_rtl_meta):
    for field in COMMON_FIELDS:
        if ref.get(field) != dut.get(field):
            return field
    if compare_rtl_meta:
        for field in RTL_META:
            if ref.get(field) != dut.get(field):
                return field
    return None


def _print_mismatch(index, ref, dut, field, compare_rtl_meta):
    print("\n=======================================================")
    print(f"FIRST ARCHITECTURAL DIVERGENCE at comparison index {index}:")
    print(f"REF seq={ref['seq']} pc=0x{ref['pc']} instr=0x{ref['instr']}")
    print(
        f"DUT seq={dut['seq']} cycle={dut.get('cycle', 'N/A')} "
        f"pc=0x{dut['pc']} instr=0x{dut['instr']}"
    )
    print(
        f"Mismatch on field: {field!r} "
        f"(REF={ref.get(field)} vs DUT={dut.get(field)})"
    )
    print(f"Classification: {classify_mismatch(field, ref, dut)}")
    for key in GPRS:
        state = "MATCH" if ref[key] == dut[key] else "MISMATCH"
        print(f"  {key:>3}: REF=0x{ref[key]} DUT=0x{dut[key]} [{state}]")
    if compare_rtl_meta:
        for key in RTL_META:
            state = "MATCH" if ref.get(key) == dut.get(key) else "MISMATCH"
            print(f"  {key:>3}: REF={ref.get(key)} DUT={dut.get(key)} [{state}]")
    print("=======================================================\n")


def compare_traces(ref_path, dut_path, max_compare=None, allow_subsequence=False):
    try:
        ref_records, ref_type = parse_trace(ref_path)
        dut_records, dut_type = parse_trace(dut_path)
    except (OSError, TraceError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    print(f"Reference trace: {ref_path} ({len(ref_records)} records, type={ref_type})")
    print(f"DUT trace:       {dut_path} ({len(dut_records)} records, type={dut_type})")

    ref_offset = dut_offset = 0
    if allow_subsequence:
        first = dut_records[0]
        candidates = [
            index for index, record in enumerate(ref_records)
            if record["pc"] == first["pc"]
            and record["instr"] == first["instr"]
            and record["occurrence"] == first["occurrence"]
        ]
        if len(candidates) != 1:
            print(
                "ERROR: --subsequence requires one unambiguous identity match; "
                f"found {len(candidates)}",
                file=sys.stderr,
            )
            return 2
        ref_offset = candidates[0]

    ref_remaining = len(ref_records) - ref_offset
    dut_remaining = len(dut_records) - dut_offset
    if max_compare is None:
        if ref_remaining != dut_remaining:
            print(
                "ERROR: incomplete differential: record counts differ "
                f"(REF={ref_remaining}, DUT={dut_remaining})",
                file=sys.stderr,
            )
            return 2
        count = ref_remaining
    else:
        if max_compare <= 0:
            print("ERROR: --max-compare must be positive", file=sys.stderr)
            return 2
        if max_compare > ref_remaining or max_compare > dut_remaining:
            print(
                "ERROR: requested comparison prefix exceeds one trace "
                f"(requested={max_compare}, REF={ref_remaining}, DUT={dut_remaining})",
                file=sys.stderr,
            )
            return 2
        count = max_compare
        print(f"Explicit bounded prefix comparison: {count} records")

    compare_rtl_meta = ref_type == "rtl" and dut_type == "rtl"
    for index in range(count):
        ref = ref_records[ref_offset + index]
        dut = dut_records[dut_offset + index]
        mismatch = compare_record_pair(ref, dut, compare_rtl_meta)
        if mismatch:
            _print_mismatch(index, ref, dut, mismatch, compare_rtl_meta)
            return 1

    scope = "RTL-to-RTL" if compare_rtl_meta else "reference-to-RTL/common architectural fields"
    print(f"\nDIFFERENTIAL PASS: {count} complete records match ({scope}).")
    return 0


def _select_occurrence(records, pc, selector):
    matches = [record for record in records if record["pc"] == pc]
    if not matches:
        raise TraceError(f"checkpoint 0x{pc} is absent")
    if selector == "last":
        return matches[-1]
    try:
        occurrence = int(selector, 0)
    except ValueError as error:
        raise TraceError(f"invalid occurrence selector {selector!r}") from error
    selected = [record for record in matches if record["occurrence"] == occurrence]
    if len(selected) != 1:
        raise TraceError(f"checkpoint 0x{pc} occurrence {occurrence} is not unique")
    return selected[0]


def compare_checkpoint(ref_path, dut_path, checkpoint_pc, expected_v1=None, occurrence=None):
    try:
        ref_records, ref_type = parse_trace(ref_path)
        dut_records, dut_type = parse_trace(dut_path)
        pc = checkpoint_pc.lower().replace("0x", "").zfill(8)
        if occurrence is None:
            ref_matches = [record for record in ref_records if record["pc"] == pc]
            dut_matches = [record for record in dut_records if record["pc"] == pc]
            if len(ref_matches) != 1 or len(dut_matches) != 1:
                raise TraceError(
                    f"checkpoint 0x{pc} is ambiguous; pass --occurrence "
                    f"(REF={len(ref_matches)}, DUT={len(dut_matches)})"
                )
            ref, dut = ref_matches[0], dut_matches[0]
        else:
            ref = _select_occurrence(ref_records, pc, occurrence)
            dut = _select_occurrence(dut_records, pc, occurrence)
    except (OSError, TraceError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    compare_rtl_meta = ref_type == "rtl" and dut_type == "rtl"
    mismatch = compare_record_pair(ref, dut, compare_rtl_meta)
    if mismatch:
        _print_mismatch(0, ref, dut, mismatch, compare_rtl_meta)
        return 1
    if expected_v1 is not None:
        expected = f"{int(str(expected_v1), 0) & 0xffffffff:08x}"
        if ref["v1"] != expected or dut["v1"] != expected:
            print(
                f"ERROR: expected v1=0x{expected}, "
                f"REF=0x{ref['v1']} DUT=0x{dut['v1']}",
                file=sys.stderr,
            )
            return 1
    print(
        f"CHECKPOINT PASS: 0x{pc} occurrence={ref['occurrence']} "
        f"matched across REF ({ref_type}) and DUT ({dut_type}); all common fields agree."
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", help="reference focus log")
    parser.add_argument("--dut", help="device-under-test focus log")
    parser.add_argument("--qemu", help="legacy alias for --ref")
    parser.add_argument("--rtl", help="legacy alias for --dut")
    parser.add_argument("--max-compare", type=int, help="explicit bounded prefix length")
    parser.add_argument(
        "--subsequence", action="store_true",
        help="explicitly align DUT at one unique identity in the reference",
    )
    parser.add_argument("--checkpoint", help="checkpoint PC")
    parser.add_argument("--occurrence", help="checkpoint occurrence number or 'last'")
    parser.add_argument("--expected-v1", help="optional expected v1 value")
    args = parser.parse_args()

    ref = args.ref or args.qemu
    dut = args.dut or args.rtl
    if not ref or not dut:
        parser.error("must specify --ref and --dut (or --qemu and --rtl)")
    if args.occurrence is not None and not args.checkpoint:
        parser.error("--occurrence requires --checkpoint")

    if args.checkpoint:
        result = compare_checkpoint(
            ref, dut, args.checkpoint, args.expected_v1, args.occurrence
        )
    else:
        result = compare_traces(
            ref, dut, max_compare=args.max_compare, allow_subsequence=args.subsequence
        )
    sys.exit(result)


if __name__ == "__main__":
    main()
