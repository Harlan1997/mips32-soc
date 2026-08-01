#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/wdt_boot_failure_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/wdt_boot_failure/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    echo "Building WDT boot-failure firmware..."
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=wdt_boot_failure \
        OUT_DIR="${ROOT_DIR}/build/firmware/wdt_boot_failure" FW_BASE=firmware all
fi

FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" "${SCRIPT_DIR}/run.sh"

SIM_LOG="${RUN_DIR}/sim.log"
if [ ! -f "$SIM_LOG" ]; then
    echo "ERROR: missing simulation log: $SIM_LOG"
    exit 1
fi
if grep -q 'REGRESSION_TEST_FAILED' "$SIM_LOG" || grep -q 'FAIL:' "$SIM_LOG"; then
    echo "ERROR: WDT boot-failure firmware reported failure"
    exit 1
fi
if ! grep -q 'wdt_boot_failure: REGRESSION_TEST_SUCCESS' "$SIM_LOG"; then
    echo "ERROR: WDT boot-failure firmware did not complete after reset"
    exit 1
fi
if ! grep -q 'REGRESSION_TEST_SUCCESS' "$SIM_LOG"; then
    echo "ERROR: WDT boot-failure SoC gate did not reach mailbox success"
    exit 1
fi
echo "SUCCESS: WDT BOOT-FAILURE FIRMWARE GATE PASSED"
