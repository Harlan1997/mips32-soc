#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "scripts" / "compare_peripheral_transactions.py"


UART = [
    {"kind": "uart", "addr": "0x04000000", "data": "0x41", "write": 1, "width": 4},
    {"kind": "uart", "addr": "0x04000014", "data": "0x60", "write": 0, "width": 4},
]
VIC = [{
    "kind": "vic", "raw": 1, "pending": 1, "enable": 1, "active": 0,
    "irq": 1, "vec_id": 0, "vec_prio": 4, "uart_irq": 1,
    "uart_rx_irq": 0, "uart_tx_irq": 1, "cpu_accept": 1,
    "cause": "0x40808000", "status": "0x10008401",
}]


def run(kind: str, ref: list[dict], dut: list[dict], expect: int) -> None:
    with tempfile.TemporaryDirectory(prefix="peripheral-diff-") as tmp:
        root = Path(tmp)
        ref_path = root / "ref.jsonl"
        dut_path = root / "dut.jsonl"
        ref_path.write_text("\n".join(json.dumps(item) for item in ref) + "\n")
        dut_path.write_text("\n".join(json.dumps(item) for item in dut) + "\n")
        result = subprocess.run(
            [sys.executable, str(CHECKER), "--kind", kind, "--ref", str(ref_path), "--dut", str(dut_path)],
            text=True, capture_output=True,
        )
        assert result.returncode == expect, (result.stdout, result.stderr)


run("uart", UART, UART, 0)
run("uart", UART, UART[:1], 1)
run("uart", UART, [UART[1], UART[0]], 1)
changed_uart = [dict(item) for item in UART]
changed_uart[1]["data"] = "0x43"
run("uart", UART, changed_uart, 1)
with tempfile.TemporaryDirectory(prefix="peripheral-diff-schedule-") as tmp:
    root = Path(tmp)
    schedule = root / "rtl_uart_apb_schedule.txt"
    schedule.write_text(
        "# uart-apb-schedule-v1 cycle write address data\n"
        "10 1 04000000 00000041\n"
        "11 0 04000014 00000060\n"
    )
    parsed = subprocess.run(
        [sys.executable, str(CHECKER), "--kind", "uart",
         "--ref", str(schedule), "--dut", str(schedule)],
        text=True, capture_output=True,
    )
    assert parsed.returncode == 0, (parsed.stdout, parsed.stderr)
    malformed = root / "malformed_uart_schedule.txt"
    malformed.write_text("10 2 04000000 00000041\n")
    rejected = subprocess.run(
        [sys.executable, str(CHECKER), "--kind", "uart",
         "--ref", str(malformed), "--dut", str(schedule)],
        text=True, capture_output=True,
    )
    assert rejected.returncode == 1, (rejected.stdout, rejected.stderr)
run("vic", VIC, VIC, 0)
with tempfile.TemporaryDirectory(prefix="peripheral-diff-vic-") as tmp:
    root = Path(tmp)
    rtl_vic = root / "rtl_vic.log"
    rtl_vic.write_text(
        "LINUX_VIC_TRACE cycle=157 raw=00000300 pending=00000300 "
        "enable=00000300 active=00000000 irq=1 vec_id=09 vec_prio=b "
        "uart_irq=0 uart_rx_irq=0 uart_tx_irq=0 cpu_accept=0 "
        "cause=00000000 status=00000000\n"
    )
    qemu_vic = root / "qemu_vic.jsonl"
    qemu_vic.write_text(json.dumps({
        "kind": "vic", "raw": "0x00000300", "pending": "0x00000300",
        "enable": "0x00000300", "active": "0x00000000", "irq": 1,
        "vec_id": 9, "vec_prio": 11, "uart_irq": 0, "uart_rx_irq": 0,
        "uart_tx_irq": 0, "cpu_accept": 0, "cause": "0x00000000",
        "status": "0x00000000",
    }) + "\n")
    parsed = subprocess.run(
        [sys.executable, str(CHECKER), "--kind", "vic",
         "--ref", str(qemu_vic), "--dut", str(rtl_vic)],
        text=True, capture_output=True,
    )
    assert parsed.returncode == 0, (parsed.stdout, parsed.stderr)
with tempfile.TemporaryDirectory(prefix="peripheral-diff-vic-prefixed-") as tmp:
    root = Path(tmp)
    ref = root / "ref.jsonl"
    dut = root / "dut.jsonl"
    ref.write_text(json.dumps(VIC[0]) + "\n")
    dut.write_text(
        "UART_TX_BYTE=55LINUX_VIC_TRACE cycle=157 raw=00000001 pending=00000001 "
        "enable=00000001 active=00000000 irq=1 vec_id=00 vec_prio=4 "
        "uart_irq=1 uart_rx_irq=0 uart_tx_irq=1 cpu_accept=1 "
        "cause=40808000 status=10008401\n"
    )
    parsed = subprocess.run(
        [sys.executable, str(CHECKER), "--kind", "vic",
         "--ref", str(ref), "--dut", str(dut)],
        text=True, capture_output=True,
    )
    assert parsed.returncode == 0, (parsed.stdout, parsed.stderr)
    assert "records=1" in parsed.stdout, parsed.stdout
with tempfile.TemporaryDirectory(prefix="peripheral-diff-vic-missing-initial-") as tmp:
    root = Path(tmp)
    ref = root / "ref.jsonl"
    dut = root / "dut.jsonl"
    baseline = dict(VIC[0])
    baseline.update({"raw": 0, "pending": 0, "enable": "0x300", "active": 0,
                     "irq": 0, "vec_id": 255, "vec_prio": 0, "uart_irq": 0,
                     "uart_rx_irq": 0, "uart_tx_irq": 0, "cause": 0, "status": 0})
    ref.write_text(json.dumps(baseline) + "\n" + json.dumps(VIC[0]) + "\n")
    dut.write_text(json.dumps(VIC[0]) + "\n")
    parsed = subprocess.run(
        [sys.executable, str(CHECKER), "--kind", "vic",
         "--ref", str(ref), "--dut", str(dut)],
        text=True, capture_output=True,
    )
    assert parsed.returncode == 1, (parsed.stdout, parsed.stderr)
changed_vic = [dict(VIC[0])]
changed_vic[0]["pending"] = 0
run("vic", VIC, changed_vic, 1)
print("PERIPHERAL_DIFF_CHECKER_TEST_PASS")
