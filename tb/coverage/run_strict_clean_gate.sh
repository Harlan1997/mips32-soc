#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/coverage/strict_clean"}
UVM_VDB=${UVM_VDB:-"${ROOT_DIR}/build/signoff/current_contract/phase2_complete/directed_cov/directed.vdb"}
PRODUCT_VDB=${PRODUCT_VDB:-"${ROOT_DIR}/build/signoff/current_contract/phase3_complete/cpu_cp0_gate/simv.vdb"}
mkdir -p "${RUN_DIR}"

source /etc/profile.d/modules.sh
module load vcs

for vdb in "$UVM_VDB" "$PRODUCT_VDB"; do
  if [ ! -d "$vdb" ]; then
    echo "ERROR: missing VDB: $vdb" >&2
    exit 1
  fi
done

python3 "${ROOT_DIR}/tb/coverage/audit_exclusions.py" > "${RUN_DIR}/exclusion_audit.log"

run_urg_clean() {
  local name=$1
  local vdb=$2
  local report="${RUN_DIR}/${name}_urgReport"
  local log="${RUN_DIR}/${name}_urg.log"
  rm -rf -- "$report"
  urg -dir "$vdb" \
      -elfile "${ROOT_DIR}/tb/coverage/${name}_exclusions.el" \
      -excl_strict -format text -report "$report" -log "$log"
  if grep -Eqi 'warning-|invalid|checksum mismatch|illegal exclusion|unknown module|excluded item does not exist|stale|VCM-HFUFR|no source' "$log"; then
    echo "ERROR: strict URG metadata warning in $log" >&2
    return 1
  fi
  test -s "${report}/dashboard.txt"
}

run_urg_clean uvm "$UVM_VDB"
run_urg_clean product "$PRODUCT_VDB"

if [ -n "${COMPILE_LOG:-}" ] && grep -Eqi 'VCM-HFUFR|Warning-\[VCM' "$COMPILE_LOG"; then
  echo "ERROR: coverage compile hierarchy warning in ${COMPILE_LOG}" >&2
  exit 1
fi

echo "REGRESSION_TEST_SUCCESS coverage_strict_clean"
