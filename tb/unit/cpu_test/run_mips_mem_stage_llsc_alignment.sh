#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_mem_stage_llsc_alignment"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/cpu/mips_mem_stage.v" \
    "${SCRIPT_DIR}/tb_mips_mem_stage_llsc_alignment.sv" \
    -top tb_mips_mem_stage_llsc_alignment -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS mips_mem_stage_llsc_alignment" sim.log
echo "MIPS MEM-stage LL/SC alignment gate: PASS"
