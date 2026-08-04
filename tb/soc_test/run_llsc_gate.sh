#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/llsc_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/llsc/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

mkdir -p "$RUN_DIR"
FW_HEX=$(realpath "$FW_HEX")
FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" "${SCRIPT_DIR}/run.sh"

if ! grep -q 'REGRESSION_TEST_SUCCESS' "$RUN_DIR/sim.log"; then
    echo "ERROR: LL/SC firmware did not reach success marker"
    exit 1
fi
if grep -q 'FAIL:' "$RUN_DIR/sim.log"; then
    echo "ERROR: LL/SC firmware reported failure"
    exit 1
fi
echo "SUCCESS: LL/SC FIRMWARE GATE PASSED"
