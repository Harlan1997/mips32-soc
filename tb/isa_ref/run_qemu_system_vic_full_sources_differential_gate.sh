#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/isa_ref/qemu_system_vic_full_sources_differential}
FW_DIR=${FW_DIR:-${ROOT_DIR}/build/firmware/vic_full_sources}

FW_TEST=vic_full_sources FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
  RTL_VCS_EXTRA_ARGS="${RTL_VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK" \
  "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

echo "QEMU system VIC full-source differential: PASS"
