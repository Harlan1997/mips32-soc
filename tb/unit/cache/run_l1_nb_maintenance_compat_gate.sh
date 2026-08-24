#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb_maintenance_compat"}
mkdir -p "${RUN_DIR}"

# The opt-in adapter deliberately keeps CACHE/Tag/SYNC on the blocking dcache
# until a nonblocking maintenance protocol exists.  Make that boundary
# executable by running the CPU-side completion and CP0 tag contracts together
# and checking the adapter source still exposes the compatibility routing.
grep -q 'assign cache_op_ready  = legacy_cache_op_ready' \
    "${ROOT_DIR}/rtl/cache/l1_cache_nb_cpu_axi.v"
grep -q 'cache_op_valid' "${ROOT_DIR}/rtl/cache/l1_cache_nb_cpu_axi.v"
grep -q 'maintenance_issue' "${ROOT_DIR}/rtl/cache/l1_cache_nb_cpu_axi.v"
grep -q 'L1_MAINTENANCE_IDLE' "${ROOT_DIR}/tb/sva/l1_maintenance_props.sv"

RUN_DIR="${RUN_DIR}/cache_op" \
    "${ROOT_DIR}/tb/unit/cpu_test/run_cache_op.sh" >"${RUN_DIR}/cache_op_gate.log" 2>&1
RUN_DIR="${RUN_DIR}/cache_tag" \
    "${ROOT_DIR}/tb/unit/cpu_test/run_cache_tag.sh" >"${RUN_DIR}/cache_tag_gate.log" 2>&1

grep -q 'REGRESSION_TEST_SUCCESS mips_cpu_cacheop' "${RUN_DIR}/cache_op/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS mips_cpu_cachetag' "${RUN_DIR}/cache_tag/sim.log"

cat >"${RUN_DIR}/l1_nb_maintenance_compat_report.md" <<'EOF'
# L1 Nonblocking Maintenance Compatibility Gate

- Result: PASS
- CPU CACHE completion/stall behavior passes through the existing blocking
  dcache contract.
- CP0 TagLo/TagHi read/write and SYNC ordered-no-op behavior passes.
- The opt-in L1 adapter source audit confirms maintenance requests are not
  silently allocated into the nonblocking line cache.

This closes compatibility of the existing maintenance contract. It does not
claim a nonblocking CACHE protocol, maintenance concurrent with outstanding
L1 responses, full cache ordering, or an OS cache-management ABI.
EOF
echo 'L1 nonblocking maintenance compatibility: PASS'
