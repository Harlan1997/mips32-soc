#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_badvaddr_owner_context"}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
"${EDA_RUNNER}" vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_cpu_badvaddr_owner_context.sv" \
    -top tb_mips_cpu_badvaddr_owner_context -l compile.log
"${EDA_RUNNER}" ./simv -no_save -l sim.log
grep -q '^BADVADDR_OWNER_CONTEXT_PASS ' sim.log
cat > "${RUN_DIR}/badvaddr_owner_context_completion_report.md" <<EOF
# BadVAddr Owner Context Gate

- Result: PASS
- Simulation log: \`${RUN_DIR}/sim.log\`
- Contract: a live D-side translation-fault owner is cleared by scheduler
  context restore, ERET, interrupt flush, and reset before a later WB bundle
  can consume it.
- Evidence: \`BADVADDR_OWNER_CONTEXT_PASS restore=1 eret=1 irq=1 reset=1\`
EOF
echo "CPU BadVAddr owner context gate: PASS"
