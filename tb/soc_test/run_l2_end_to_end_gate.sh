#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l2_end_to_end"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/l2_e2e/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=l2_e2e \
        OUT_DIR="${ROOT_DIR}/build/firmware/l2_e2e" FW_BASE=firmware all
fi

FW_HEX=$(realpath "${FW_HEX}")
RUN_DIR=$(realpath -m "${RUN_DIR}")
mkdir -p "${RUN_DIR}"

FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:+${VCS_EXTRA_ARGS} }+define+SOC_L2_E2E" \
"${SCRIPT_DIR}/run.sh"

if ! grep -q 'L2_E2E_TEST_SUCCESS' "${RUN_DIR}/sim.log"; then
    echo "ERROR: L2 end-to-end success marker missing"
    exit 1
fi
if grep -Eq 'L2_E2E_COUNTER_MISMATCH|REGRESSION_TEST_FAILED|SoC Simulation Timeout' \
    "${RUN_DIR}/sim.log"; then
    echo "ERROR: L2 end-to-end counter or simulation failure"
    exit 1
fi

echo "SUCCESS: L2 END-TO-END GATE PASSED"
