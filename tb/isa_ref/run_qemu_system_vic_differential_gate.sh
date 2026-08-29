#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_vic_irq_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_vic_irq"}

FW_TEST=qemu_system_vic_irq FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

[[ $(grep -c '"pc":"00000180"' "${RUN_DIR}/rtl/rtl_retire.jsonl") -eq 2 ]]
[[ $(grep -c '"pc":"80000180"' "${RUN_DIR}/qemu/qemu_retire.jsonl") -eq 2 ]]
grep -q '"mem_addr":"40004200".*"mem_rdata":"00000009"' "${RUN_DIR}/rtl/rtl_retire.jsonl"
grep -q '"mem_addr":"40004200".*"mem_rdata":"00000008"' "${RUN_DIR}/rtl/rtl_retire.jsonl"
grep -q '"mem_addr":"40004208".*"mem_wdata":"00000200"' "${RUN_DIR}/rtl/rtl_retire.jsonl"
grep -q '"mem_addr":"40004208".*"mem_wdata":"00000100"' "${RUN_DIR}/rtl/rtl_retire.jsonl"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System VIC IRQ RTL Retire Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: 48 compared retire records covering simultaneous software sources 8/9, priority 9 then 8, VEC_ID accept, ACK/SOFT_CLR, two CPU interrupt entries/ERET returns, and magic mailbox retirement.
- Evidence: completion_report.md, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Residual risk: external source timing/replay, nested asynchronous interrupt schedules, VEIC vectors, and reset-in-flight remain separate gates.
EOF
echo "QEMU system VIC IRQ RTL retire differential: PASS"
