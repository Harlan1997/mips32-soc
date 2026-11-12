#!/usr/bin/env python3
"""Consumer and validator for retire trace FIFO gate."""

import argparse
import json
import os
import sys
import time


def parse_args():
    parser = argparse.ArgumentParser(description="Retire trace FIFO validator")
    parser.add_argument("--fifo", required=True, help="Path to named FIFO")
    parser.add_argument("--expected-records", type=int, required=True,
                        help="Expected number of records")
    parser.add_argument(
        "--backpressure-mode",
        choices=["none", "sleep_burst", "slow_chunk"],
        default="none",
        help="Backpressure pattern to apply",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    fd = os.open(args.fifo, os.O_RDONLY)
    expected_seq = 0
    buffer = bytearray()
    records_seen = 0

    try:
        while True:
            if args.backpressure_mode == "slow_chunk":
                chunk = os.read(fd, 2048)
                time.sleep(0.0001)
            else:
                chunk = os.read(fd, 65536)

            if not chunk:
                break

            buffer.extend(chunk)

            while True:
                nl = buffer.find(b"\n")
                if nl < 0:
                    break
                raw = buffer[:nl]
                del buffer[:nl + 1]
                line = raw.decode("utf-8").strip()
                if not line:
                    continue

                try:
                    rec = json.loads(line)
                except Exception as e:
                    raise AssertionError(
                        f"Malformed JSON at record {records_seen}: {line[:100]}... error={e}"
                    )

                if "retire_seq" not in rec:
                    raise AssertionError(
                        f"Record {records_seen} missing retire_seq: {line[:100]}"
                    )

                seq = rec["retire_seq"]
                if not isinstance(seq, int):
                    raise AssertionError(
                        f"retire_seq {seq!r} is not int at record {records_seen}"
                    )

                if seq != expected_seq:
                    raise AssertionError(
                        f"Sequence discontinuity: expected {expected_seq}, got {seq} (record {records_seen})"
                    )

                expected_seq += 1
                records_seen += 1

                if args.backpressure_mode == "sleep_burst" and (records_seen % 2500 == 0):
                    time.sleep(0.05)

        if buffer.strip():
            raise AssertionError(
                f"Incomplete trailing data in FIFO: {buffer[:100]!r}"
            )

        if records_seen != args.expected_records:
            raise AssertionError(
                f"Record count mismatch: expected {args.expected_records}, got {records_seen}"
            )

        print(
            f"CHECK_RETIRE_TRACE_FIFO_PASS records={records_seen} mode={args.backpressure_mode}"
        )
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
