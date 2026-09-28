#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/cpu-badvaddr-owner-gate}
LOG="${RUN_DIR}/sim.log"

mkdir -p "${RUN_DIR}"
RUN_DIR="${RUN_DIR}" \
OWNER_TRACE=1 \
SIM_EXTRA_ARGS="+D_FAULT_OWNER_TRACE=1" \
  "${ROOT_DIR}/tb/soc_test/run_mmu_refill.sh" >"${RUN_DIR}/run.log" 2>&1

python3 "${ROOT_DIR}/scripts/check_badvaddr_owner_trace.py" "${LOG}"
grep -q "MMU_REFILL_MARKER_PASS" "${LOG}"
grep -q "REGRESSION_TEST_SUCCESS" "${LOG}"

cat >"${RUN_DIR}/badvaddr_owner_completion_report.md" <<EOF
# BadVAddr Owner Gate

- Result: PASS
- Simulation log: \`${LOG}\`
- Contract: every observed owner commit has matching PC/instruction/address/code
  identity and CP0 BadVAddr equals the captured virtual address.
- Workload: MMU demand refill, cross-page access, and permission-fault firmware.
EOF
echo "CPU BadVAddr owner gate: PASS"
