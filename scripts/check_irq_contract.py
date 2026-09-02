#!/usr/bin/env python3
"""Audit the CPU/PIC/UART interrupt mapping shared by RTL and QEMU."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
rtl = (ROOT / "rtl/soc_peripheral_subsystem.v").read_text()
qemu = (ROOT / "scripts/qemu/mips32_soc_ref.c").read_text()
dts_paths = (
    ROOT / "tb/linux_boot/mips32_soc_ref.dts",
    ROOT / "tb/linux_boot/mips32_soc_ref_rtl.dts",
)

errors = []

if not re.search(
    r'irq_sources\s*=\s*\{26\'d0,\s*ddr4_ecc_irq,\s*qspi_irq,\s*dma_int,\s*'
    r'timer_int,\s*uart_tx_int,\s*uart_rx_int\}',
    rtl,
):
    errors.append("RTL VIC source ordering does not match source 0..5 contract")
if not re.search(r'\.ext_int\s*\(\{5\'d0,\s*cpu_int\}\)',
                 (ROOT / "rtl/soc_core_subsystem.v").read_text()):
    errors.append("RTL VIC aggregate is not connected to CPU ext_int[0]/IP2")

uart_fn = re.search(
    r'static void soc_ref_uart_update_irq\(.*?\n\}', qemu, re.S
)
if not uart_fn:
    errors.append("QEMU UART IRQ update function is missing")
else:
    body = uart_fn.group(0)
    if "pic_raw |= 1U << 1" not in body or "pic_raw &= ~(1U << 1)" not in body:
        errors.append("QEMU UART does not drive mirrored VIC source 1")
    if "env->irq[4]" in body:
        errors.append("QEMU UART still directly drives CPU IP4")
if not re.search(r'qemu_set_irq\(s->cpu->env\.irq\[2\]', qemu):
    errors.append("QEMU VIC aggregate is not connected to CPU IP2")

for path in dts_paths:
    text = path.read_text()
    uart = re.search(r'(?s)uart0: serial@40000000\s*\{.*?\n\s*\};', text)
    if not uart or not re.search(r'\binterrupts\s*=\s*<4>\s*;', uart.group(0)):
        errors.append(f"{path.relative_to(ROOT)} does not declare Linux direct UART CPU IP4")

if "if (soc_ref_linux_guest)" not in qemu or "s->cpu->env.irq[4]" not in qemu:
    errors.append("QEMU Linux compatibility direct UART IP4 path is missing")

if errors:
    for error in errors:
        print(f"IRQ_CONTRACT_AUDIT_FAIL {error}", file=sys.stderr)
    sys.exit(1)

print("IRQ_CONTRACT_AUDIT_PASS uart_vic_source=1 cpu_ip=2")
