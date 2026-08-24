#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_fpu_flags"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps +define+SOC_FPU_ENABLE=1 \
    "${ROOT_DIR}/rtl/cpu/mips_fpu.v" \
    "${SCRIPT_DIR}/tb_mips_fpu_flags.sv" \
    -top tb_mips_fpu_flags -o simv -l compile.log
./simv -l sim.log
grep -q 'REGRESSION_TEST_SUCCESS mips_fpu_flags' sim.log
echo 'MIPS FPU invalid/underflow flags: PASS'
