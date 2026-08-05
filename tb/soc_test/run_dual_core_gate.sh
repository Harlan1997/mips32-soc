#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/dual_core"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/dual_core_ipi"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=dual_core_ipi OUT_DIR="${FW_DIR}" FW_BASE=firmware all
fi

FW_HEX="${FW_HEX}" \
RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="+define+SOC_ENABLE_DUAL_CORE" \
"${SCRIPT_DIR}/run.sh"

grep -q "DUAL_CORE_CORE1_ACTIVE" "${RUN_DIR}/sim.log"
grep -q "REGRESSION_TEST_SUCCESS" "${RUN_DIR}/sim.log"
echo "dual-core SoC gate: PASS"
