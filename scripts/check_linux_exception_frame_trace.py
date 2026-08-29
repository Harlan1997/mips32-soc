#!/usr/bin/env python3
"""Check bounded RTL Linux exception-frame before/after trace pairs."""

import argparse
import re
import sys

KEY_VALUE = re.compile(r"([A-Za-z_]+)=([^ ]+)")
HEX_KEYS = {
    "event_pc", "epc", "status", "cause", "errorepc", "bad", "entryhi",
    "wbpc", "wbinst",
}


def parse_line(line):
    fields = dict(KEY_VALUE.findall(line))
    if "LINUX_EXCEPTION_FRAME_BEFORE" in line:
        fields["kind"] = "before"
    elif "LINUX_EXCEPTION_FRAME_AFTER" in line:
        fields["kind"] = "after"
    else:
        return None
    return fields


def number(fields, key):
    value = fields.get(key)
    if value is None:
        raise ValueError(f"missing {key}")
    if key in HEX_KEYS:
        return int(value, 16)
    return int(value, 0)


def check(path):
    before = {}
    pairs = 0
    errors = []
    with open(path, encoding="ascii", errors="replace") as stream:
        for line_no, line in enumerate(stream, 1):
            fields = parse_line(line)
            if fields is None:
                continue
            try:
                if fields["kind"] == "before":
                    if number(fields, "int") == 0 and number(fields, "code") == 0:
                        continue
                    cycle = number(fields, "cycle")
                    before[cycle] = (line_no, fields)
                    continue
                # ERET/restore records are intentionally visible in the
                # trace but do not have a newly saved exception frame.  Their
                # zero event code and zero interrupt bit identify them.
                if number(fields, "event_int") == 0 and number(fields, "event_code") == 0:
                    continue
                event_cycle = number(fields, "event_cycle")
                if event_cycle not in before:
                    errors.append(f"line {line_no}: no BEFORE for event_cycle={event_cycle}")
                    continue
                before_line, pre = before.pop(event_cycle)
                event_pc = number(fields, "event_pc")
                event_int = number(fields, "event_int")
                event_bd = number(fields, "event_bd")
                status = number(fields, "status")
                cause = number(fields, "cause")
                epc = number(fields, "epc")
                if not (event_int or number(pre, "code")):
                    errors.append(f"lines {before_line}/{line_no}: event is neither IRQ nor exception")
                if not (status & 0x2):
                    errors.append(f"lines {before_line}/{line_no}: EXL not set after event")
                expected_epc = (event_pc - 4) & 0xFFFFFFFF if event_bd else event_pc
                if epc != expected_epc:
                    errors.append(f"lines {before_line}/{line_no}: EPC=0x{epc:08x}, expected 0x{expected_epc:08x}")
                if bool(cause & 0x80000000) != bool(event_bd):
                    errors.append(f"lines {before_line}/{line_no}: Cause.BD disagrees with event_bd")
                pairs += 1
            except (KeyError, ValueError) as exc:
                errors.append(f"line {line_no}: {exc}")
    for cycle, (line_no, _) in sorted(before.items()):
        errors.append(f"line {line_no}: missing AFTER for event_cycle={cycle}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1, pairs
    if pairs == 0:
        print("ERROR: no complete exception-frame pairs found", file=sys.stderr)
        return 1, pairs
    return 0, pairs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    args = parser.parse_args()
    status, pairs = check(args.log)
    if status == 0:
        print(f"LINUX_EXCEPTION_FRAME_CHECK_PASS pairs={pairs}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
