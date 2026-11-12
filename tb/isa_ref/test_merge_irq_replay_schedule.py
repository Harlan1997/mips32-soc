#!/usr/bin/env python3
"""Focused tests for merging the RTL timer/IRQ replay boundary."""

import tempfile
import unittest
from pathlib import Path

from merge_irq_replay_schedule import merge_schedules


class MergeIRQReplayScheduleTest(unittest.TestCase):
    def test_timer_release_follows_captured_retirement(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            irq_path = Path(temp_dir) / "irq.txt"
            timer_path = Path(temp_dir) / "timer.txt"
            irq_path.write_text("12 00808000 80001000\n", encoding="ascii")
            timer_path.write_text("10 88001674\n", encoding="ascii")

            self.assertEqual(
                merge_schedules(irq_path, timer_path),
                "11 ti 88001674\n12 irq 00808000 80001000\n",
            )

    def test_timer_precedes_irq_at_shared_replay_boundary(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            irq_path = Path(temp_dir) / "irq.txt"
            timer_path = Path(temp_dir) / "timer.txt"
            irq_path.write_text("11 40808020 88016540\n", encoding="ascii")
            timer_path.write_text("10 88001674\n", encoding="ascii")

            self.assertEqual(
                merge_schedules(irq_path, timer_path),
                "11 ti 88001674\n11 irq 40808020 88016540\n",
            )

    def test_timer_and_ti_irq_keep_the_same_source_boundary(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            irq_path = Path(temp_dir) / "irq.txt"
            timer_path = Path(temp_dir) / "timer.txt"
            irq_path.write_text("10 c0808000 88a5ddd4\n", encoding="ascii")
            timer_path.write_text("10 882a5f20\n", encoding="ascii")

            self.assertEqual(
                merge_schedules(irq_path, timer_path),
                "10 ti 882a5f20\n10 irq c0808000 88a5ddd4\n",
            )

    def test_timer_after_shared_irq_without_ti_in_captured_cause(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            irq_path = Path(temp_dir) / "irq.txt"
            timer_path = Path(temp_dir) / "timer.txt"
            irq_path.write_text("10 00800400 88a5ddd4\n", encoding="ascii")
            timer_path.write_text("10 882a5f20\n", encoding="ascii")

            self.assertEqual(
                merge_schedules(irq_path, timer_path),
                "10 irq 00800400 88a5ddd4\n11 ti 882a5f20\n",
            )


if __name__ == "__main__":
    unittest.main()
