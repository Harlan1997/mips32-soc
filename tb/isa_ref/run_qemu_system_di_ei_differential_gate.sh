#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_di_ei_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_di_ei"}

FW_TEST=qemu_system_di_ei FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DI/EI RTL Retire Differential

- Result: PASS
- Scope: MIPS32 R2 DI/EI old-Status result and atomic Status.IE update.
- Evidence: firmware_build.log, rtl_gate.log, qemu/trace_compare.log
EOF
echo "QEMU system DI/EI RTL retire differential: PASS"
