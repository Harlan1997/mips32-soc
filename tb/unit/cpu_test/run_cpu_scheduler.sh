#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_scheduler"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/cpu/cpu_scheduler.v" "${ROOT_DIR}/tb/unit/cpu_test/tb_cpu_scheduler.sv" -top tb_cpu_scheduler -l compile.log
./simv -l sim.log; grep -q "REGRESSION_TEST_SUCCESS cpu_scheduler" sim.log
echo "cpu scheduler v0.1: PASS"
