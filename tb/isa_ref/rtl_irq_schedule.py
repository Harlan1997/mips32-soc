#!/usr/bin/env python3
"""Export QEMU IRQ release points from an RTL retire trace.

Each output value is the number of completed instructions immediately before
an RTL general-exception vector fetch. The MIPS translator helper executes
once per guest instruction, matching the retire JSONL count.
"""
import argparse
import json

VECTOR_PCS = {"00000180", "80000180", "bfc00380"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("rtl_trace")
    parser.add_argument("output")
    parser.add_argument("--offset", type=int, default=1,
                        help="offset from the one-based RTL vector line")
    args = parser.parse_args()

    entries = []
    with open(args.rtl_trace, encoding="ascii") as source:
        for line_number, line in enumerate(source, 1):
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("pc", "").lower() in VECTOR_PCS:
                # The QEMU retire hook advances at the current instruction
                # boundary before delivering the replayed interrupt.  Use the
                # vector record's one-based position so the IRQ is visible
                # before the corresponding vector transition.
                value = line_number + args.offset
                if value <= 0:
                    raise SystemExit("IRQ schedule offset produced non-positive entry")
                entries.append(value)
    if not entries:
        raise SystemExit("no general-exception vector entries in RTL trace")
    with open(args.output, "w", encoding="ascii") as output:
        output.write("# completed-retire count before each IRQ vector fetch\n")
        for entry in entries:
            output.write(f"{entry}\n")


if __name__ == "__main__":
    main()
