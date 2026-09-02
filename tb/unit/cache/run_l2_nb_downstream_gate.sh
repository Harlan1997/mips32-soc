#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/l2nb_downstream"}
mkdir -p "${RUN_DIR}"

if ! command -v vcs >/dev/null 2>&1; then
    echo "l2-nb-downstream-gate: vcs is required" >&2
    exit 2
fi

cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cache/l2_cache_nb.v" \
    "${ROOT_DIR}/tb/unit/l2nb/tb_l2nb_parallel.v" -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS l2nb_parallel" sim.log
cat > "${RUN_DIR}/l2nb_downstream_report.md" <<EOF
# L2 Nonblocking Downstream Refill Gate

- Result: PASS
- Contract: opt-in two clean-refill AR/R slots with RID routing.
- Evidence: see compile.log and sim.log; the test reports 32 checked beats,
  two active downstream slots, and cross-ID interleaving.
- Boundary: dirty eviction/writeback remains serialized; arbitrary slot counts,
  concurrent dirty writeback, and full coherency are separate contracts.
EOF
echo "L2 nonblocking downstream refill concurrency: PASS"
