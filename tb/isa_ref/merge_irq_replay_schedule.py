#!/usr/bin/env python3
"""Merge RTL IRQ and timer schedules for the QEMU replay boundary."""

import argparse
from pathlib import Path


def _read_events(path, event_kind):
    events = []
    with open(path, encoding="ascii") as schedule:
        for line_number, raw_line in enumerate(schedule, 1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            expected_fields = 3 if event_kind == "irq" else 2
            if len(fields) != expected_fields:
                raise ValueError(
                    f"{path}:{line_number}: expected {expected_fields} fields")
            try:
                sequence = int(fields[0], 10)
                if sequence < 0:
                    raise ValueError
                for value in fields[1:]:
                    int(value, 16)
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{line_number}: invalid schedule value") from exc

            if event_kind == "irq":
                _, cause, epc = fields
                priority = 1
            else:
                _, pc = fields
                priority = 0
                cause = pc
                epc = None
            events.append((sequence, priority, event_kind, cause, epc))
    if not events:
        raise ValueError(f"{path}: no {event_kind} schedule entries")
    return events


def merge_schedules(irq_path, timer_path):
    irq_events = _read_events(irq_path, "irq")
    timer_events = _read_events(timer_path, "ti")
    timer_irq_boundaries = {
        sequence
        for sequence, _, _, cause, _ in irq_events
        if int(cause, 16) & (1 << 30)
    }
    # A standalone TI edge follows the retiring instruction, so replay it
    # before the next one. If an accepted IRQ captured TI at that same RTL
    # boundary, assert TI at the boundary itself so IRQ acceptance observes it.
    timer_events = [
        (sequence if sequence in timer_irq_boundaries else sequence + 1,
         priority, event_kind, cause, epc)
        for sequence, priority, event_kind, cause, epc in timer_events
    ]
    events = irq_events + timer_events
    events.sort(key=lambda event: (event[0], event[1]))
    for previous, current in zip(events, events[1:]):
        if previous[0] == current[0] and not (
                previous[2] == "ti" and current[2] == "irq"):
            raise ValueError(
                f"multiple replay events share sequence {current[0]}")
    lines = []
    for sequence, _, event_kind, cause_or_pc, epc in events:
        if event_kind == "ti":
            lines.append(f"{sequence} ti {cause_or_pc}")
        else:
            lines.append(f"{sequence} irq {cause_or_pc} {epc}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--irq-schedule", required=True)
    parser.add_argument("--timer-schedule", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        merged = merge_schedules(args.irq_schedule, args.timer_schedule)
        Path(args.output).write_text(merged, encoding="ascii")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
