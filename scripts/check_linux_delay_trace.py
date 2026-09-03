#!/usr/bin/env python3
"""Check an RTL Linux __udelay retire trace without changing simulation state."""

import argparse
import re
import sys


PC_RE = re.compile(
    r"LINUX_PC_TRACE cycle=(?P<cycle>\d+) .*?"
    r"wbpc=(?P<pc>[0-9a-fA-F]+) wbinst=(?P<inst>[0-9a-fA-F]+) "
    r"wbarch=(?P<arch>[01]) wbreg=(?P<reg_en>[01])/(?P<reg>\d+)/"
    r"(?P<wdata>[0-9a-fA-F]+) .*? v0=(?P<v0>[0-9a-fA-F]+)"
)
MODE_RE = re.compile(
    r"LINUX_MODE_TRACE cycle=(?P<cycle>\d+) .*?eret=(?P<eret>[01]) "
    r".*?cause=(?P<cause>[0-9a-fA-F]+) epc=(?P<epc>[0-9a-fA-F]+)"
)


def parse(path):
    pcs = []
    modes = []
    with open(path, encoding="ascii", errors="replace") as stream:
        for line in stream:
            match = PC_RE.search(line)
            if match:
                item = {key: int(value, 16 if key in ("pc", "inst", "wdata", "v0") else 10)
                        for key, value in match.groupdict().items()}
                pcs.append(item)
            match = MODE_RE.search(line)
            if match:
                item = {key: int(value, 16 if key in ("cause", "epc") else 10)
                        for key, value in match.groupdict().items()}
                modes.append(item)
    return pcs, modes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--branch-pc", default="0x88c43ea0", type=lambda value: int(value, 0))
    parser.add_argument("--delay-pc", default="0x88c43ea4", type=lambda value: int(value, 0))
    args = parser.parse_args()

    pcs, modes = parse(args.trace)
    retired = [item for item in pcs if item["arch"] and item["pc"] in
               (args.branch_pc, args.delay_pc)]
    if len(retired) < 4:
        raise SystemExit("LINUX_DELAY_TRACE_FAIL insufficient architectural records")

    errors = []
    expected = retired[0]["pc"]
    previous_v0 = None
    for item in retired:
        if item["pc"] != expected:
            errors.append("cycle=%d expected pc=0x%08x got=0x%08x" %
                          (item["cycle"], expected, item["pc"]))
        if item["pc"] == args.branch_pc and item["inst"] & 0xffff0000 != 0x14400000:
            errors.append("cycle=%d branch is not bnez (inst=0x%08x)" %
                          (item["cycle"], item["inst"]))
        if item["pc"] == args.delay_pc and item["inst"] & 0xffff0000 != 0x24420000:
            errors.append("cycle=%d delay slot is not addiu v0,v0,imm (inst=0x%08x)" %
                          (item["cycle"], item["inst"]))
        expected = args.branch_pc if expected == args.delay_pc else args.delay_pc
        if item["pc"] == args.delay_pc:
            if item["reg_en"] != 1 or item["reg"] != 2:
                errors.append("cycle=%d delay-slot did not write v0" % item["cycle"])
            if previous_v0 is not None and item["wdata"] != ((previous_v0 - 1) & 0xffffffff):
                errors.append("cycle=%d delay-slot v0 write is not decrement (0x%08x -> 0x%08x)" %
                              (item["cycle"], previous_v0, item["wdata"]))
            previous_v0 = item["wdata"]

    erets = [item for item in modes if item["eret"]]
    misaligned = [item for item in erets if item["epc"] & 3]
    if misaligned:
        errors.append("unaligned ERET EPC at cycle=%d" % misaligned[0]["cycle"])
    if errors:
        for error in errors[:8]:
            print("LINUX_DELAY_TRACE_ERROR " + error, file=sys.stderr)
        raise SystemExit("LINUX_DELAY_TRACE_FAIL errors=%d records=%d erets=%d" %
                         (len(errors), len(retired), len(erets)))
    print("LINUX_DELAY_TRACE_PASS records=%d erets=%d branch=0x%08x delay=0x%08x" %
          (len(retired), len(erets), args.branch_pc, args.delay_pc))


if __name__ == "__main__":
    main()
