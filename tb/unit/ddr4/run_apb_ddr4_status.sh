#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/apb_ddr4_status"}
source /etc/profile.d/modules.sh
module load vcs
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/apb_ddr4_status.v" "${SCRIPT_DIR}/tb_apb_ddr4_status.sv" -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS apb_ddr4_status" sim.log
echo "DDR4 status contract gate: PASS"
