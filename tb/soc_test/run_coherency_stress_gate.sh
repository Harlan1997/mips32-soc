#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/coherency_stress"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/coherency_stress"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
    make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=coh_diag OUT_DIR="${FW_DIR}" FW_BASE=firmware all
fi

FW_HEX=$(realpath "${FW_HEX}")
FW_HEX="${FW_HEX}" \
RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS="+define+SOC_ENABLE_DUAL_CORE +define+SOC_COHERENCY_FW_STRESS" \
"${SCRIPT_DIR}/run.sh"

grep -q 'COH_STRESS_CORE1_DONE iterations=00000008' "${RUN_DIR}/sim.log"
grep -q 'COH_STRESS_CORE0_DONE iterations=00000008' "${RUN_DIR}/sim.log"
grep -q 'COH_STRESS_SHARED_MEMORY_PASS' "${RUN_DIR}/sim.log"
if grep -q 'COH_STRESS_FAIL\|REGRESSION_TEST_FAILED' "${RUN_DIR}/sim.log"; then
    echo "ERROR: shared-memory coherency stress reported failure"
    exit 1
fi

echo "dual-core shared-memory coherency stress gate: PASS"
