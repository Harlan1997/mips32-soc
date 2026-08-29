#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_trap_imm_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_trap_imm"}

FW_TEST=qemu_system_trap_imm FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Immediate Trap RTL Retire Differential

- Result: PASS
- Scope: TGEI/TGEIU/TLTI/TLTIU/TEQI/TNEI, immediate sign extension, ExcCode 13 and ERET.
- Evidence: firmware_build.log, rtl_gate.log, qemu/trace_compare.log
EOF
echo "QEMU system immediate trap RTL retire differential: PASS"
