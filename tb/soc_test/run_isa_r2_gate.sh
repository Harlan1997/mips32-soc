#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/isa_r2_sweep"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/isa_r2_sweep"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=isa_r2_sweep OUT_DIR="${FW_DIR}" FW_BASE=firmware all
SKIP_URG_EXCLUSION_CHECK=1 FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" "${SCRIPT_DIR}/run.sh"
grep -a -q "isa_r2_" "${RUN_DIR}/sim.log"
if grep -a -q "ISA_R2_EXT_INS_FAIL" "${RUN_DIR}/sim.log"; then
    echo "ISA R2 EXT/INS: FAIL" >&2
    exit 1
fi
grep -a -q "REGRESSION_TEST_SUCCESS" "${RUN_DIR}/sim.log"
grep -a -q "CPU_CP0_SUMMARY.*ri=0" "${RUN_DIR}/sim.log"
echo "ISA R2 implemented-subset gate: PASS"
