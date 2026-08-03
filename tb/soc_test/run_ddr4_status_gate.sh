#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/ddr4_status_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/ddr4_status/firmware.hex"}
if [ ! -f "${FW_HEX}" ]; then
  make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=ddr4_status OUT_DIR="${ROOT_DIR}/build/firmware/ddr4_status" FW_BASE=firmware all
fi
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" VCS_EXTRA_ARGS="+define+SOC_ENABLE_DDR4_STATUS" "${SCRIPT_DIR}/run.sh"
grep -q "REGRESSION_TEST_SUCCESS" "${RUN_DIR}/sim.log"
echo "DDR4 status SoC gate: PASS"
