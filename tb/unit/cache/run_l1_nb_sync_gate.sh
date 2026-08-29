#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb_sync"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
  +incdir+"${ROOT_DIR}/rtl/include" \
  "${ROOT_DIR}/rtl/cache/l1_cache_nb.v" \
  "${ROOT_DIR}/tb/unit/cache/tb_l1_cache_nb_sync.sv" \
  -top tb_l1_cache_nb_sync -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS l1nb_sync" sim.log
echo "L1 nonblocking SYNC drain gate: PASS"
