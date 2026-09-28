#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "scripts" / "compare_peripheral_transactions.py"


UART = [
    {"kind": "uart", "addr": "0x40000000", "data": "0x41", "write": 1, "width": 1},
    {"kind": "uart", "addr": "0x40000000", "data": "0x42", "write": 1, "width": 1},
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
run("vic", VIC, VIC, 0)
changed_vic = [dict(VIC[0])]
changed_vic[0]["pending"] = 0
run("vic", VIC, changed_vic, 1)
print("PERIPHERAL_DIFF_CHECKER_TEST_PASS")
