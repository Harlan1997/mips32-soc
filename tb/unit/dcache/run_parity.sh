#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/unit_tb/dcache_parity}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
  +incdir+"${ROOT_DIR}/rtl/include" \
  "${ROOT_DIR}/rtl/cache/dcache.v" \
  "${ROOT_DIR}/tb/unit/dcache/tb_dcache.v" \
  -top tb_dcache -l compile.log
./simv -l sim.log
grep -q 'REGRESSION_TEST_SUCCESS dcache' sim.log
cat > dcache_parity_report.md <<'EOF'
# D-cache Parity/CacheErr Gate

Result: PASS

- Resident data-line parity injection reaches `cpu_cache_error`/CacheErr.
- Resident tag parity injection reaches `cpu_cache_error`/CacheErr.
- The error cycle suppresses normal `cpu_data_ok` completion.
- Clearing injection permits a clean retry of the line.
- Scope is simulation parity and architectural error propagation; this is not
  SECDED correction, multi-bit ECC, or silicon memory-reliability signoff.
EOF
echo "D-cache parity/CacheErr gate: PASS"
