#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/uart_external_rx_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/uart_external_rx/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=uart_external_rx \
        OUT_DIR="${ROOT_DIR}/build/firmware/uart_external_rx" FW_BASE=firmware all
fi

FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="+define+SOC_UART_EXTERNAL_RX_WAVEFORM" \
    "${SCRIPT_DIR}/run.sh"

if grep -q 'REGRESSION_TEST_FAILED' "${RUN_DIR}/sim.log" || \
   grep -q 'FAIL:' "${RUN_DIR}/sim.log"; then
    echo "ERROR: UART external RX SoC gate reported failure"
    exit 1
fi
grep -q 'tb_mips_soc: injecting external UART RX frame 0x5A' "${RUN_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
echo "SUCCESS: UART external RX SoC GATE PASSED"
