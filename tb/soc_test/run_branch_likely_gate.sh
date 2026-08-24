#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/branch_likely"}
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/branch_likely"}
make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=branch_likely \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
  VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK" \
  "${ROOT_DIR}/tb/soc_test/run.sh"
if grep -aq 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"; then
    echo "Branch-likely SoC gate: PASS"
else
    echo "Branch-likely SoC gate: FAIL" >&2
    exit 1
fi
