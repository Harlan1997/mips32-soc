#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cache_concurrency/l1nb_axi_bridge"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/cache/l1_cache_nb_axi_bridge.v" \
    "${ROOT_DIR}/tb/unit/cache/tb_l1_cache_nb_axi_bridge.sv" \
    -top tb_l1_cache_nb_axi_bridge -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS l1nb_axi_bridge" sim.log
cat > l1_nonblocking_axi_bridge_report.md <<EOF
# L1 Nonblocking AXI Bridge Contract Gate

Result: PASS

- Two independent refill reads are issued with AXI IDs 0 and 1.
- ID 1 completes before ID 0 and retains its address/data/error association.
- A response error is isolated to the matching read slot.
- Reset flushes both in-flight read slots.
- Scope is the opt-in line-port bridge; CPU simultaneous exception recovery,
  maintenance/coherence interleavings, and physical DDR behavior remain open.
EOF
echo "L1 nonblocking AXI bridge contract: PASS"
