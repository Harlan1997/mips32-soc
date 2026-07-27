#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/dma_cpu_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/dma_cpu/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    echo "Building DMA CPU firmware..."
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=dma_cpu OUT_DIR="${ROOT_DIR}/build/firmware/dma_cpu" FW_BASE=firmware all
fi

FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" "${SCRIPT_DIR}/run.sh"

SIM_LOG="${RUN_DIR}/sim.log"
if [ ! -f "$SIM_LOG" ]; then
    echo "ERROR: missing simulation log: $SIM_LOG"
    exit 1
fi

if grep -q 'REGRESSION_TEST_FAILED' "$SIM_LOG"; then
    echo "ERROR: DMA CPU firmware test reported REGRESSION_TEST_FAILED"
    exit 1
fi

if grep -q 'FAIL:' "$SIM_LOG"; then
    echo "ERROR: DMA CPU firmware log contains failure output (FAIL:)"
    exit 1
fi

if ! grep -q 'REGRESSION_TEST_SUCCESS' "$SIM_LOG"; then
    echo "ERROR: DMA CPU firmware test did not reach REGRESSION_TEST_SUCCESS"
    exit 1
fi

echo "SUCCESS: DMA CPU FIRMWARE GATE PASSED"


