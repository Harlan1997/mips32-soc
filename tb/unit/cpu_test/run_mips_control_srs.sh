#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_control_srs"}
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_SRS_ENABLE=1 +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cpu/mips_control.v" \
    "${ROOT_DIR}/tb/unit/cpu_test/tb_mips_control_srs.sv" -l compile.log
./simv -l sim.log
grep -q 'REGRESSION_TEST_SUCCESS mips_control_srs' sim.log
echo 'MIPS SRS control decoder gate: PASS'
