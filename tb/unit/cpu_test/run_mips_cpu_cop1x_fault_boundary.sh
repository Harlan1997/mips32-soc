#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/cpu-cop1x-fault-boundary}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
"${EDA_RUNNER}" vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_FPU_ENABLE=1 \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_cpu_cop1x_fault_boundary.sv" \
    -top tb_mips_cpu_cop1x_fault_boundary -l compile.log
"${EDA_RUNNER}" ./simv -no_save -l sim.log
grep -q '^COP1X_FAULT_BOUNDARY_PASS ' sim.log
cat > "${RUN_DIR}/cop1x_fault_boundary_completion_report.md" <<EOF
# COP1X Fault Boundary Gate

- Result: PASS
- Simulation log: \`${RUN_DIR}/sim.log\`
- Contract: first and second aligned LUXC1 faults do not partially commit the
  FPR, and a faulting SUXC1 second beat does not issue a store request.
- Evidence: \`COP1X_FAULT_BOUNDARY_PASS first_fault=1 second_fault=1 fpr_atomic=1 store_blocked=1 reverse_endian=1\`
EOF
echo "COP1X fault boundary gate: PASS"
