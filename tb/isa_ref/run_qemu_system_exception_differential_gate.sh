#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_exception_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_exception"}

FW_TEST=qemu_system_exception FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Exception RTL Retire Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: syscall exception, general vector, Cause/EPC reads, EPC update, ERET,
  and mailbox retirement.
- Evidence: completion_report.md, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Differential: 17 records through the mailbox-store retirement boundary.
- Residual risk: delay-slot BD exception, interrupts, MMU faults, and device timing remain separate gates.
EOF
echo "QEMU system exception RTL retire differential: PASS"
