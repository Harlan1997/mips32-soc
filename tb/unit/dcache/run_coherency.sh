#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/dcache_coherency"}
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
  "${ROOT_DIR}/rtl/cache/dcache.v" \
  "${ROOT_DIR}/tb/unit/dcache/tb_dcache_coherency.sv" \
  -top tb_dcache_coherency -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS dcache_coherency" sim.log
echo "dcache coherency v0.1: PASS"
