#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_wait_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_wait"}

FW_TEST=qemu_system_wait FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    RTL_IRQ_REPLAY=1 RTL_IRQ_SCHEDULE_OFFSET=-2 \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System WAIT RTL Retire Differential

- Result: PASS
- Scope: MIPS32 WAIT retirement, pending software interrupt wakeup, handler ERET and post-WAIT resume.
- Evidence: firmware_build.log, rtl_gate.log, qemu/trace_compare.log
EOF
echo "QEMU system WAIT RTL retire differential: PASS"
