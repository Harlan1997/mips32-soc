#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_id_stage_llsc_hazard"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}/rtl/cpu/mips_control.v" \
    "${ROOT_DIR}/rtl/cpu/mips_id_stage.v" \
    "${ROOT_DIR}/rtl/cpu/mips_regfile.v" \
    "${SCRIPT_DIR}/tb_mips_id_stage_llsc_hazard.sv" \
    -top tb_mips_id_stage_llsc_hazard -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS mips_id_stage_llsc_hazard" sim.log
echo "MIPS ID-stage LL/SC hazard gate: PASS"
