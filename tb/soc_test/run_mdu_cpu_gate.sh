#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/mdu_cpu_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/mdu_cpu/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    echo "Building MDU CPU firmware..."
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=mdu_cpu OUT_DIR="${ROOT_DIR}/build/firmware/mdu_cpu" FW_BASE=firmware all
fi

FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" "${SCRIPT_DIR}/run.sh"

SIM_LOG="${RUN_DIR}/sim.log"
if [ ! -f "$SIM_LOG" ]; then
    echo "ERROR: missing simulation log: $SIM_LOG"
    exit 1
fi

if ! grep -q 'REGRESSION_TEST_SUCCESS' "$SIM_LOG"; then
    echo "ERROR: MDU CPU firmware test did not reach REGRESSION_TEST_SUCCESS"
    exit 1
fi

echo "SUCCESS: MDU CPU FIRMWARE GATE PASSED"
