#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_bd_exception_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_bd_exception"}
FW_TEST=qemu_system_bd_exception FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"
grep -q '"bd":1' "${RUN_DIR}/qemu/qemu_retire.jsonl"
grep -q '"bd":1' "${RUN_DIR}/rtl/rtl_retire.jsonl"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Branch-Delay Exception Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: syscall in a taken branch delay slot, Cause.BD/EPC capture, EPC+8 recovery, and mailbox retirement.
- Evidence: completion_report.md, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Residual risk: asynchronous interrupts, MMU faults, and nested exceptions remain open.
EOF
echo "QEMU system branch-delay exception differential: PASS"
