#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency"}

mkdir -p "${RUN_DIR}/l2nb"
FAILED=0

if ! command -v vcs >/dev/null 2>&1; then
    echo "cache-concurrency-gate: vcs is required" >&2
    exit 2
fi

echo "========================================================================"
echo " Cache Concurrency Gate"
echo " Run Root: ${RUN_DIR}"
echo "========================================================================"

(
    cd "${RUN_DIR}/l2nb"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" \
        +incdir+"${ROOT_DIR}/rtl/cache" \
        "${ROOT_DIR}/rtl/cache/l2_cache_nb.v" \
        "${ROOT_DIR}/tb/unit/l2nb/tb_l2nb.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS l2nb" "${RUN_DIR}/l2nb/sim.log"; then
    echo "L2 non-blocking MSHR: PASS"
else
    echo "L2 non-blocking MSHR: FAIL"
    FAILED=1
fi

cat > "${RUN_DIR}/cache_concurrency_report.md" <<EOF
# Cache Concurrency Gate

## Result

$(if [ "${FAILED}" -eq 0 ]; then echo PASS; else echo FAIL; fi)

## Closed contract

- L2 non-blocking option: 8 MSHRs.
- Secondary misses to one cache line merge into one refill.
- Distinct lines may remain outstanding concurrently.
- Responses are routed by AXI ID and may complete out of order across IDs.
- The downstream memory port remains single-outstanding.
- The default SoC path remains unchanged: L1 is blocking and L2 non-blocking is opt-in.

## Evidence

See l2nb/compile.log and l2nb/sim.log. The test reports peak MSHR use,
hit-under-miss responses, and scoreboard-checked read beats.

## Residual risk

L1/CPU late-response integration remains separate. The L1 2-MSHR/ID unit
contract is covered by run_l1_nb_gate.sh; this report must not be read as full
SoC L1/L2 non-blocking signoff.
EOF

exit "${FAILED}"
