#!/usr/bin/env python3
"""Convert live QEMU event/state FIFOs to a live retire JSONL stream.

The regular converter keeps only a three-state window, but its file readers
open both inputs sequentially.  This wrapper opens both FIFOs before QEMU is
started and feeds the existing converter through queue-backed iterators, so a
full Linux run never materializes the event, state, or retire streams on disk.
"""
import argparse
import fcntl
import json
import os
import queue
import sys
import threading

from qemu_system_state_to_jsonl import convert


# The QEMU plugin emits small atomic records, but the state records are larger
# and the converter can be briefly CPU-bound.  Keep more bounded data in the
# kernel and reader queues so the producer is not repeatedly interrupted by
# a full default pipe while the RTL producer is active.
STREAM_PIPE_SIZE = 1 << 20
STREAM_QUEUE_SIZE = 1024
F_SETPIPE_SZ = getattr(
    fcntl, "F_SETPIPE_SZ", 1031 if sys.platform.startswith("linux") else None)


def enlarge_pipe(fd):
    if F_SETPIPE_SZ is None:
        return
    try:
        fcntl.fcntl(fd, F_SETPIPE_SZ, STREAM_PIPE_SIZE)
    except OSError:
        # F_SETPIPE_SZ is Linux-specific and may be capped by the host.  The
        # stream remains correct with the kernel default size.
        pass


class FifoLines:
    """Read one FIFO in a worker while allowing its writer to start later."""

    def __init__(self, path):
        self.path = path
        self.items = queue.Queue(maxsize=STREAM_QUEUE_SIZE)
        self.error = None
        self.done = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        fd = None
        try:
            # A blocking FIFO open waits for QEMU's plugin.  Keeping this in a
            # worker lets the event and state streams open simultaneously.
            fd = os.open(self.path, os.O_RDONLY)
            enlarge_pipe(fd)
            with os.fdopen(fd, "rb", closefd=False) as stream:
                for line_number, raw in enumerate(stream, 1):
                    if raw.strip():
                        try:
                            value = json.loads(raw.decode("ascii"))
                        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                            preview = raw[:1024].decode("ascii", errors="replace")
                            raise ValueError(
                                f"{self.path}:{line_number}: invalid JSON: {exc}; "
                                f"raw_line={preview!r}"
                            ) from exc
                        self.items.put(value)
            self.items.put(None)
        except BaseException as exc:  # propagate parser and I/O errors
            self.error = exc
            self.items.put(None)
        finally:
            if fd is not None:
                os.close(fd)
            self.done.set()

    def __iter__(self):
        return self

    def __next__(self):
        value = self.items.get()
        if value is None:
            if self.error is not None:
                raise self.error
            raise StopIteration
        return value


class StateWindow:
    streaming = True

    def __init__(self, source):
        self.source = iter(source)
        self.position = 0
        try:
            self.current = next(self.source)
            self.next = next(self.source)
        except StopIteration as exc:
            raise ValueError("state stream needs at least two records") from exc
        self.previous = None

    def advance(self):
        self.previous = self.current
        self.current = self.next
        try:
            self.next = next(self.source)
        except StopIteration:
            self.next = None
        self.position += 1

    def __getitem__(self, index):
        if index == self.position:
            value = self.current
        elif index == self.position - 1:
            value = self.previous
        elif index == self.position + 1:
            value = self.next
        else:
            raise IndexError(f"streaming state window cannot access index {index}")
        if value is None:
            raise ValueError("state stream ended before events + post-state")
        return value

    @staticmethod
    def _same_instruction(left, right):
        return (left is not None and right is not None and
                left.get("pc") == right.get("pc") and
                left.get("instr", right.get("instr")) ==
                right.get("instr", left.get("instr")))

    def align_current(self, event, limit=8):
        """Align a live state FIFO after a transient producer skew.

        QEMU emits the state boundary before the preceding event.  Under
        heavy concurrent FIFO pressure an extra boundary can occasionally be
        observed ahead of its event.  Drop only a short run of state records
        when the next boundary is an exact PC/instruction match; any other
        mismatch remains fatal.
        """
        for _ in range(limit):
            if self._same_instruction(self.current, event):
                return
            if self._same_instruction(self.next, event):
                # Keep ``position`` and ``previous`` at the logical retire
                # index; the discarded state was never an architectural
                # boundary for the event stream.
                self.current = self.next
                try:
                    self.next = next(self.source)
                except StopIteration:
                    self.next = None
                continue
            raise ValueError(
                "event/state PC misalignment "
                f"event_pc={event.get('pc')} event_instr={event.get('instr')} "
                f"state_pc={self.current.get('pc') if self.current else None} "
                f"state_instr={self.current.get('instr') if self.current else None} "
                f"next_state_pc={self.next.get('pc') if self.next else None} "
                f"next_state_instr={self.next.get('instr') if self.next else None}")
        raise ValueError("event/state PC misalignment: state resync limit exceeded")


class EventWindow:
    streaming = True

    def __init__(self, source, states):
        self.source = iter(source)
        self.states = states
        self.position = -1
        self.current = None
        self.previous = None
        self._pending = None

    def _next_raw(self):
        if self._pending is not None:
            event = self._pending
            self._pending = None
            return event
        return next(self.source)

    @staticmethod
    def _same_instruction(left, right):
        return (left is not None and right is not None and
                left.get("pc") == right.get("pc") and
                left.get("instr", right.get("instr")) ==
                right.get("instr", left.get("instr")))

    def __iter__(self):
        return self

    def __next__(self):
        if self.position >= 0:
            self.states.advance()
        event = self._next_raw()
        for _ in range(8):
            try:
                self.states.align_current(event)
                break
            except ValueError:
                # If the following event matches the current state boundary,
                # the current event is the transient extra record.  Preserve
                # the candidate for the same logical retire index.
                try:
                    candidate = self._next_raw()
                except StopIteration:
                    raise
                if self._same_instruction(candidate, self.states.current):
                    event = candidate
                    continue
                raise
        self.previous = self.current
        self.current = event
        self.position += 1
        return event

    def __getitem__(self, index):
        if index == self.position:
            return self.current
        if index == self.position - 1:
            return self.previous
        raise IndexError(f"streaming event window cannot access index {index}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("events")
    parser.add_argument("states")
    parser.add_argument("output")
    args = parser.parse_args()

    events = FifoLines(args.events)
    states = FifoLines(args.states)
    state_window = StateWindow(states)
    event_window = EventWindow(events, state_window)
    count = 0
    output_fd = os.open(args.output, os.O_WRONLY)
    enlarge_pipe(output_fd)
    pending = bytearray()

    def flush_pending():
        """Write complete JSON lines without exceeding FIFO atomicity."""
        nonlocal pending
        if not pending:
            return
        offset = 0
        while offset < len(pending):
            try:
                written = os.write(output_fd, pending[offset:])
            except InterruptedError:
                continue
            if written <= 0:
                raise OSError("retire FIFO write returned no progress")
            offset += written
        pending.clear()

    try:
        for record in convert(event_window, state_window):
            record["retire_seq"] = count
            # Batch only complete JSON lines. A large buffered text stream can
            # be interrupted while flushing and leave a partial line for the
            # strict comparator during peer shutdown.
            payload = (json.dumps(record, separators=(",", ":")) + "\n").encode("ascii")
            if len(payload) > 4096:
                flush_pending()
                pending.extend(payload)
                flush_pending()
            else:
                if pending and len(pending) + len(payload) > 4096:
                    flush_pending()
                pending.extend(payload)
            count += 1
        flush_pending()
    finally:
        os.close(output_fd)
    events.thread.join()
    states.thread.join()
    print(f"QEMU_SYSTEM_RETIRE_STREAM_PASS records={count}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"qemu_system_state_to_jsonl_stream: {exc}", file=sys.stderr)
        raise SystemExit(1)
