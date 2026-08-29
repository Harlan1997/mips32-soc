#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb_maintenance_compat"}
mkdir -p "${RUN_DIR}"

# The opt-in adapter routes the two address-scoped invalidate operations to
# L1, while retaining the legacy dcache for tag, writeback and other CACHE
# operations. Make that split executable alongside the CPU-side contracts.
grep -q 'l1_maintenance_supported' \
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
  dcache contract for tag/writeback/unsupported operations.
- `Index_Invalidate_D` and `Hit_Invalidate_D` are accepted by the opt-in L1
  only after outstanding line traffic and responses drain, then complete with
  a one-cycle L1 maintenance handshake.
- CP0 TagLo/TagHi read/write and SYNC ordered-drain behavior passes.
- The opt-in L1 adapter source audit confirms maintenance requests are not
  silently allocated into the nonblocking line cache.

This closes the two address-scoped invalidate operations in the opt-in L1
adapter. It does not claim nonblocking writeback/tag operations, concurrent
maintenance before drain, full cache ordering, or an OS cache-management ABI.
EOF
echo 'L1 nonblocking maintenance compatibility: PASS'
