#!/usr/bin/env python3
"""Abort when an unexpected process opens a retire FIFO for reading."""

import argparse
import os
import stat
import sys
import time


def _fifo_readers(path):
    """Yield ``(pid, fd, flags)`` for read-capable descriptors on *path*."""
    try:
        if not stat.S_ISFIFO(os.stat(path).st_mode):
            return
        wanted = os.path.realpath(path)
    except OSError:
        return

    try:
        proc_entries = os.scandir("/proc")
    except OSError:
        return
    with proc_entries:
        for proc_entry in proc_entries:
            if not proc_entry.name.isdigit():
                continue
            pid = int(proc_entry.name)
            fd_root = os.path.join("/proc", proc_entry.name, "fd")
            try:
                fd_entries = os.scandir(fd_root)
            except OSError:
                continue
            with fd_entries:
                for fd_entry in fd_entries:
                    try:
                        target = os.path.realpath(fd_entry.path)
                        if target != wanted:
                            continue
                        with open(
                            os.path.join(
                                "/proc", proc_entry.name, "fdinfo", fd_entry.name
                            ),
                            encoding="ascii",
                        ) as info:
                            flags = next(
                                int(line.split(":", 1)[1].strip(), 8)
                                for line in info
                                if line.startswith("flags:")
                            )
                    except (OSError, StopIteration, ValueError):
                        continue
                    # O_RDONLY and O_RDWR descriptors can consume FIFO data.
                    if (flags & os.O_ACCMODE) in (os.O_RDONLY, os.O_RDWR):
                        yield pid, int(fd_entry.name), flags


def _process_name(pid):
    try:
        with open(f"/proc/{pid}/comm", encoding="ascii") as comm:
            return comm.read().strip()
    except OSError:
        return "?"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fifo", action="append", required=True)
    parser.add_argument("--expected-reader", action="append", type=int, default=[])
    parser.add_argument("--until-pid", type=int, required=True)
    parser.add_argument("--status-path", required=True)
    parser.add_argument("--interval", type=float, default=0.05)
    args = parser.parse_args()
    expected = set(args.expected_reader)
    status_path = os.path.abspath(args.status_path)

    while os.path.exists(f"/proc/{args.until_pid}"):
        for fifo in args.fifo:
            for pid, fd, flags in _fifo_readers(fifo):
                if pid in expected or pid == os.getpid():
                    continue
                message = (
                    "FIFO_READER_GUARD_VIOLATION "
                    f"fifo={fifo} pid={pid} comm={_process_name(pid)} "
                    f"fd={fd} flags={flags:o}"
                )
                try:
                    with open(status_path, "w", encoding="ascii") as status:
                        status.write(message + "\n")
                except OSError:
                    pass
                print(message, file=sys.stderr, flush=True)
                return 1
        time.sleep(max(args.interval, 0.01))

    # The comparator has closed both FIFOs.  A final scan catches a reader
    # that raced the comparator's exit without treating normal writer FDs as
    # violations.
    for fifo in args.fifo:
        for pid, fd, flags in _fifo_readers(fifo):
            if pid in expected or pid == os.getpid():
                continue
            message = (
                "FIFO_READER_GUARD_VIOLATION "
                f"fifo={fifo} pid={pid} comm={_process_name(pid)} "
                f"fd={fd} flags={flags:o}"
            )
            try:
                with open(status_path, "w", encoding="ascii") as status:
                    status.write(message + "\n")
            except OSError:
                pass
            print(message, file=sys.stderr, flush=True)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
