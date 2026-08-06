#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/isa_r2_sweep"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/isa_r2_sweep"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=isa_r2_sweep OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" "${SCRIPT_DIR}/run.sh"
grep -q "isa_r2_sweep:" "${RUN_DIR}/sim.log"
grep -q "REGRESSION_TEST_SUCCESS" "${RUN_DIR}/sim.log"
echo "ISA R2 implemented-subset gate: PASS"
