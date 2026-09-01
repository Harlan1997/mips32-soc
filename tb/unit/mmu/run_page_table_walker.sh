#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/page_table_walker"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
VCS_DEFINES=${VCS_DEFINES:-}
vcs -full64 -sverilog -timescale=1ns/1ps ${VCS_DEFINES} "${ROOT_DIR}/rtl/cpu/mips_page_table_walker.v" "${ROOT_DIR}/tb/unit/mmu/tb_page_table_walker.sv" -top tb_page_table_walker -l compile.log
./simv -l sim.log; grep -q "REGRESSION_TEST_SUCCESS page_table_walker" sim.log
echo "page-table walker permission, page-size and A/D update matrix: PASS"
