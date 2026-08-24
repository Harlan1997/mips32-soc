#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_test/rob_fifo"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/cpu/mips_rob_fifo.v" \
    "${ROOT_DIR}/tb/unit/cpu_test/tb_mips_rob_fifo.sv" -top tb_mips_rob_fifo -l compile.log
./simv -l sim.log
grep -q 'REGRESSION_TEST_SUCCESS rob_fifo' sim.log
