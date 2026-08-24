#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_fpu_compare"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_FPU_ENABLE=1 \
    "${ROOT_DIR}/rtl/cpu/mips_fpu.v" \
    "${SCRIPT_DIR}/tb_mips_fpu_compare.sv" \
    -top tb_mips_fpu_compare -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS mips_fpu_compare" sim.log
echo "MIPS32 COP1 compare predicate matrix gate: PASS"
