#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/llsc_coherency_gate"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/llsc_coherency"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=llsc COHERENCY=1 OUT_DIR="${FW_DIR}" FW_BASE=firmware all
fi

mkdir -p "$RUN_DIR"
FW_HEX=$(realpath "$FW_HEX")

FW_HEX="${FW_HEX}" \
RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="+define+SOC_ENABLE_DUAL_CORE +define+SOC_COHERENCY_LL_SC" \
"${SCRIPT_DIR}/run.sh"

if ! grep -q 'REGRESSION_TEST_SUCCESS' "$RUN_DIR/sim.log"; then
    echo "ERROR: LL/SC coherency firmware did not reach success marker"
    exit 1
fi
if grep -q 'FAIL:' "$RUN_DIR/sim.log"; then
    echo "ERROR: LL/SC coherency firmware reported failure"
    exit 1
fi
grep -q 'LLSC_COHERENCY_PEER_NOTIF_INJECTED' "$RUN_DIR/sim.log" || { echo "ERROR: Missing peer notification marker"; exit 1; }
grep -q 'SC_FAILED' "$RUN_DIR/sim.log" || { echo "ERROR: Missing SC failed marker"; exit 1; }

echo "llsc coherency gate: PASS"
