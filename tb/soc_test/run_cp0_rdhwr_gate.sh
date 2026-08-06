#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/cp0_rdhwr"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/cp0_rdhwr"}
make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=cp0_sweep \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
    rm -f "${RUN_DIR}/sim.log"
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run.sh"
grep -q '^REGRESSION_TEST_SUCCESS$' "${RUN_DIR}/sim.log"
! grep -q '^FAIL:' "${RUN_DIR}/sim.log"
! grep -q '^FAIL: RDHWR UserLocal' "${RUN_DIR}/sim.log"
echo "SUCCESS: RDHWR USERLOCAL FIRMWARE GATE PASSED"
