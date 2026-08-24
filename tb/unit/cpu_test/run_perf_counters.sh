#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/perf_counters"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/cpu/mips_perf_counters.v" \
    "${ROOT_DIR}/tb/unit/cpu_test/tb_perf_counters.sv" \
    -top tb_perf_counters -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS perf_counters" sim.log
echo "performance counters: PASS"
