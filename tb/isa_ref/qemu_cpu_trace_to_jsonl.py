#!/usr/bin/env python3
"""Merge QEMU one-insn CPU snapshots and plugin events into retire JSONL."""
import argparse
import json
import re
import sys

SNAPSHOT_RE = re.compile(
    r"^pc=0x([0-9a-fA-F]+) HI=0x([0-9a-fA-F]+) LO=0x([0-9a-fA-F]+)"
)
GPR_RE = re.compile(r"(?:[A-Za-z0-9_$]+) ([0-9a-fA-F]{8})")
CP0_RE = re.compile(
    r"^CP0 Status\s+0x([0-9a-fA-F]+) Cause\s+0x([0-9a-fA-F]+) EPC\s+0x([0-9a-fA-F]+)"
)
CONFIG_RE = re.compile(
    r"^\s+Config0 0x([0-9a-fA-F]+).*LLAddr 0x([0-9a-fA-F]+)"
)


def parse_snapshots(path):
    snapshots = []
    current = None
    with open(path, encoding="ascii") as stream:
        for line in stream:
            match = SNAPSHOT_RE.match(line)
            if match:
                if current is not None:
                    snapshots.append(current)
                current = {
                    "pc": int(match.group(1), 16),
                    "hi": int(match.group(2), 16),
                    "lo": int(match.group(3), 16),
                    "gpr": [0] * 32,
                    "cp0": {},
                }
                continue
            if current is None:
                continue
            if line.startswith("GPR"):
                fields = GPR_RE.findall(line.split(":", 1)[1])
                base = int(line[3:5])
                for offset, value in enumerate(fields):
                    index = base + offset
                    if index < 32:
                        current["gpr"][index] = int(value, 16)
                continue
            match = CP0_RE.match(line)
            if match:
                current["cp0"].update(
                    status=int(match.group(1), 16),
                    cause=int(match.group(2), 16),
                    epc=int(match.group(3), 16),
                )
                continue
            match = CONFIG_RE.match(line)
            if match:
                current["cp0"].update(
                    config0=int(match.group(1), 16),
                    lladdr=int(match.group(2), 16),
                )
    if current is not None:
        snapshots.append(current)
    return snapshots


def parse_events(path):
    events = []
    with open(path, encoding="ascii") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
    return events


def cp0_change(before, after):
    names = (("status", 12, 0), ("cause", 13, 0), ("epc", 14, 0),
             ("config0", 16, 0), ("lladdr", 17, 0))
    for name, addr, sel in names:
        if before.get(name) != after.get(name) and name in after:
            return addr, sel, after[name]
    return None


def build_record(event, before, after):
    gpr_changes = [
        index for index in range(1, 32) if before["gpr"][index] != after["gpr"][index]
    ]
    cp0 = cp0_change(before["cp0"], after["cp0"])
    mem_valid = bool(event.get("mem_valid"))
    mem_size = int(event.get("mem_size", 0))
    mem_addr = int(event.get("mem_addr", "0"), 16)
    byte_enable = ((1 << mem_size) - 1) << (mem_addr & 3) if mem_valid else 0xF
    # QEMU's instruction plugin reports the architectural instruction and the
    # post-instruction CPU snapshot separately.  For synchronous exceptions,
    # the post-state is already at the general vector and Cause contains the
    # authoritative ExcCode/BD bits.  Preserve that information in the same
    # retire record shape used by the RTL observer.
    after_pc = after["pc"]
    cause = after["cp0"].get("cause", 0)
    at_general_vector = (after_pc & 0x1fffffff) == 0x180
    exception_taken = int(at_general_vector and ((cause >> 2) & 0x1f) != 0)
    exception_code = ((cause >> 2) & 0x1f) if exception_taken else 0
    exception_bd = int(exception_taken and ((cause >> 31) & 1))
    record = {
        "schema": "00010000",
        "pc": f"{int(event['pc'], 16):08x}",
        "instr": f"{int(event['instr'], 16):08x}",
        "next_pc": f"{after_pc:08x}",
        "gpr_we": int(len(gpr_changes) == 1),
        "gpr_addr": gpr_changes[0] if len(gpr_changes) == 1 else 0,
        "gpr_data": f"{after['gpr'][gpr_changes[0]]:08x}" if len(gpr_changes) == 1 else "00000000",
        "cp0_we": int(cp0 is not None),
        "cp0_addr": cp0[0] if cp0 else 0,
        "cp0_sel": cp0[1] if cp0 else 0,
        "cp0_data": f"{cp0[2]:08x}" if cp0 else "00000000",
        "mem_valid": int(mem_valid),
        "mem_read": int(event.get("mem_read", False)),
        "mem_write": int(event.get("mem_write", False)),
        "mem_addr": f"{mem_addr:08x}",
        "mem_wdata": event.get("mem_value", "00000000") if event.get("mem_write") else "00000000",
        "mem_be": f"{byte_enable:x}",
        "mem_rdata": event.get("mem_value", "00000000") if event.get("mem_read") else "xxxxxxxx",
        "except": exception_taken,
        "except_code": exception_code,
        "bd": exception_bd,
        "eret": 0,
    }
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("events")
    parser.add_argument("cpu_log")
    parser.add_argument("output")
    args = parser.parse_args()
    events = parse_events(args.events)
    snapshots = parse_snapshots(args.cpu_log)
    if len(snapshots) < len(events) + 1:
        raise ValueError(
            f"QEMU snapshot count {len(snapshots)} is insufficient for "
            f"{len(events)} retire events plus a post-state"
        )
    with open(args.output, "w", encoding="ascii") as output:
        for index, event in enumerate(events):
            before = snapshots[index]
            after = snapshots[index + 1]
            if int(event["pc"], 16) != before["pc"]:
                raise ValueError(
                    f"QEMU trace alignment mismatch at {index}: "
                    f"event pc {event['pc']} != cpu pc {before['pc']:08x}"
                )
            json.dump(build_record(event, before, after), output, separators=(",", ":"))
            output.write("\n")
    print(f"QEMU_RETIRE_TRACE_PASS records={len(events)}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        print(f"qemu_cpu_trace_to_jsonl: {exc}", file=sys.stderr)
        raise SystemExit(1)
