#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_break_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_break"}

FW_TEST=qemu_system_break FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System BREAK RTL Retire Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: BREAK instruction, ExcCode 9, Cause/EPC handler check, ERET and mailbox retirement.
- Evidence: firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Residual risk: other trap instructions, complete privileged ISA, full FPU/ISA compliance and Linux boot remain open.
EOF
echo "QEMU system BREAK RTL retire differential: PASS"
