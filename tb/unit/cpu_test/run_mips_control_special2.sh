#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_control_special2"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

source /etc/profile.d/modules.sh
module load vcs

vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cpu/mips_control.v" \
    "${SCRIPT_DIR}/tb_mips_control_special2.sv" \
    -top tb_mips_control_special2 -o simv -l compile.log
./simv -l sim.log
grep -q 'REGRESSION_TEST_SUCCESS mips_control_special2' sim.log
echo 'MIPS control SPECIAL2 gate: PASS'
