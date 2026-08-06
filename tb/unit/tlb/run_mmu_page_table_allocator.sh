#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mmu_page_table_allocator"}
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
  "${ROOT_DIR}/rtl/cpu/mmu_page_table_allocator.v" \
  "${ROOT_DIR}/tb/unit/tlb/tb_mmu_page_table_allocator.sv" \
  -top tb_mmu_page_table_allocator -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS mmu_page_table_allocator" sim.log
echo "MMU page-table allocator: PASS"
