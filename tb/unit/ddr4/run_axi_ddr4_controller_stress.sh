#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/axi_ddr4_controller_stress"}
source /etc/profile.d/modules.sh
module load vcs
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/perips/axi_ddr4_controller.v" \
    "${SCRIPT_DIR}/tb_axi_ddr4_controller_stress.sv" \
    +incdir+"${ROOT_DIR}/rtl/include" -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS axi_ddr4_controller_stress" sim.log
echo "DDR4 controller stress/checker gate: PASS"
