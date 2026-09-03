#!/usr/bin/env python3
"""Audit precise WAIT interrupt wakeup state in an RTL Linux trace."""

import argparse
import re
import sys

WAIT_RE = re.compile(
    r"LINUX_WAIT_TRACE cycle=(?P<cycle>\d+) .*?"
    r"wbinst=(?P<wbinst>[0-9a-fA-F]+) wait=(?P<wait>[01]) "
    r"resume=(?P<resume>[0-9a-fA-F]+) intr=(?P<intr>[01]) req=(?P<req>[01])"
)
CP0_RE = re.compile(
    r"LINUX_CP0_EXCEPTION_EDGE cycle=(?P<cycle>\d+) phase=(?P<phase>pre|post) "
    r".*?except_pc=(?P<except_pc>[0-9a-fA-F]+) "
    r"except_bd=(?P<except_bd>[01]).*?epc=(?P<epc>[0-9a-fA-F]+)"
)
MODE_RE = re.compile(
    r"LINUX_MODE_TRACE cycle=(?P<cycle>\d+) .*?eret=(?P<eret>[01]) "
    r".*?epc=(?P<epc>[0-9a-fA-F]+)"
)


def parse(path):
    waits, cp0, modes = [], [], []
    with open(path, encoding="ascii", errors="replace") as stream:
        for line in stream:
            match = WAIT_RE.search(line)
            if match:
                item = match.groupdict()
                for key in ("cycle", "wbinst", "wait", "resume", "intr", "req"):
                    item[key] = int(item[key], 16 if key in ("wbinst", "resume") else 10)
                waits.append(item)
            match = CP0_RE.search(line)
            if match:
                item = match.groupdict()
                for key in ("cycle", "except_pc", "except_bd", "epc"):
                    item[key] = int(item[key], 16 if key in ("except_pc", "epc") else 10)
                cp0.append(item)
            match = MODE_RE.search(line)
            if match:
                item = match.groupdict()
                for key in ("cycle", "eret", "epc"):
                    item[key] = int(item[key], 16 if key == "epc" else 10)
                modes.append(item)
    return waits, cp0, modes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    args = parser.parse_args()
    waits, cp0, modes = parse(args.trace)
    retired = [item for item in waits if item["wbinst"] == 0x42000020]
    wakeups = [item for item in waits if item["wait"] and item["intr"] and item["req"]]
    errors = []
    if not retired:
        errors.append("no architectural WAIT retirement record")
    if not wakeups:
        errors.append("no interrupt accepted while WAIT was active")
    for wake in wakeups:
        same = [item for item in cp0 if item["cycle"] == wake["cycle"]]
        pre = next((item for item in same if item["phase"] == "pre"), None)
        post = next((item for item in same if item["phase"] == "post"), None)
        if pre is None or post is None:
            errors.append("cycle=%d missing CP0 pre/post records" % wake["cycle"])
            continue
        if pre["except_pc"] != wake["resume"]:
            errors.append("cycle=%d except_pc does not equal WAIT resume PC" % wake["cycle"])
        if pre["except_bd"] != 0:
            errors.append("cycle=%d WAIT wake asserted Cause.BD" % wake["cycle"])
        if post["epc"] != wake["resume"]:
            errors.append("cycle=%d CP0 EPC does not equal WAIT resume PC" % wake["cycle"])
        erets = [item for item in modes if item["cycle"] > wake["cycle"] and item["eret"]]
        if not erets:
            errors.append("cycle=%d has no following ERET" % wake["cycle"])
        elif erets[0]["epc"] != wake["resume"]:
            errors.append("cycle=%d ERET EPC does not equal WAIT resume PC" % erets[0]["cycle"])
    if errors:
        for error in errors[:8]:
            print("LINUX_WAIT_TRACE_ERROR " + error, file=sys.stderr)
        raise SystemExit("LINUX_WAIT_TRACE_FAIL errors=%d waits=%d wakeups=%d" %
                         (len(errors), len(retired), len(wakeups)))
    print("LINUX_WAIT_TRACE_PASS waits=%d wakeups=%d" % (len(retired), len(wakeups)))


if __name__ == "__main__":
    main()
