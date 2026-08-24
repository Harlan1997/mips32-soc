#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb"}
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/cache/l1_cache_nb.v" "${ROOT_DIR}/tb/unit/cache/tb_l1_cache_nb.sv" -top tb_l1_cache_nb -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS l1nb" sim.log
cat > l1_nonblocking_report.md <<EOF
# L1 Nonblocking Contract Gate

Result: PASS

- Two outstanding L1 miss status slots and a four-entry writeback queue
  structure reserved in the contract.
- One secondary request to an outstanding line merges into its MSHR and both
  request IDs receive a response after the shared refill.
- Request IDs are preserved across out-of-order distinct-line responses.
- Default SoC dcache remains blocking; CPU late-response integration and dirty
  eviction enqueue are open follow-up items.
EOF
