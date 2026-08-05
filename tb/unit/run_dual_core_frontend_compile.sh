#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/unit_tb/dual_core_frontend"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_ROOT}"
cd "${RUN_ROOT}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    -top soc_top -pvalue+soc_top.ENABLE_DUAL_CORE=1 \
    +incdir+"${ROOT_DIR}/rtl/include" \
    +incdir+"${ROOT_DIR}/rtl/cpu" \
    +incdir+"${ROOT_DIR}/rtl/axi" \
    +incdir+"${ROOT_DIR}/rtl/perips" \
    "${ROOT_DIR}"/rtl/clock/*.v "${ROOT_DIR}"/rtl/cpu/*.v \
    "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v "${ROOT_DIR}"/rtl/soc_fabric.v \
    "${ROOT_DIR}"/rtl/soc_core_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_memory_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_debug_subsystem.v \
    "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v \
    "${ROOT_DIR}"/rtl/soc_top.v -l compile.log

test -x simv
cat > dual_core_frontend_report.md <<EOF
# Dual-Core RTL Frontend Report

- Status: \`RTL_FRONTEND_COMPILE_READY\`
- Configuration: \`soc_top.ENABLE_DUAL_CORE=1\`
- Evidence: VCS elaborated \`simv\`; see \`compile.log\`.
- Scope: two CPU/MMU/L1 instances, core-1 AXI read arbitration, shared fabric
  master slot, APB IPI wiring, and coherency ports. Functional coherency
  evidence is provided separately by make dcache-coherency-gate. Page-table
  walker and OS scheduling remain active implementation work.
EOF
echo "dual-core frontend compile: PASS"
