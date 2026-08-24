#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb_errors"}
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/cache/l1_cache_nb.v" \
    "${ROOT_DIR}/tb/unit/cache/tb_l1_cache_nb_errors.sv" \
    -top tb_l1_cache_nb_errors -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS l1nb_errors" sim.log
cat > l1_nonblocking_errors_report.md <<EOF
# L1 Nonblocking Error/Reset Contract Gate

Result: PASS

- Failed refill errors reach both primary and merged secondary IDs.
- Independent MSHRs preserve ID/error association under out-of-order failed
  refills.
- Reset flushes queued responses and all MSHR/writeback occupancy.
- This is an opt-in line-cache contract gate; CPU arbitrary multi-error,
  coherence, and default blocking behavior remain separate contracts.
EOF
echo "L1 nonblocking error/reset contract: PASS"
