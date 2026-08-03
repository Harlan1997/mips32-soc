#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/uart_cts_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/uart_cts/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=uart_cts \
        OUT_DIR="${ROOT_DIR}/build/firmware/uart_cts" FW_BASE=firmware all
fi

FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="+define+SOC_UART_CTS_FLOW_CONTROL" \
    "${SCRIPT_DIR}/run.sh"

if grep -q 'REGRESSION_TEST_FAILED' "${RUN_DIR}/sim.log" || \
   grep -q 'FAIL:' "${RUN_DIR}/sim.log"; then
    echo "ERROR: UART CTS SoC gate reported failure"
    exit 1
fi
grep -q 'tb_mips_soc: UART CTS inactive held TX idle' "${RUN_DIR}/sim.log"
grep -q 'tb_mips_soc: UART CTS release allowed TX frame' "${RUN_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
echo "SUCCESS: UART CTS SoC GATE PASSED"
