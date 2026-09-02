#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/page_table_tlb_refill"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
SIM_TIMEOUT=${SIM_TIMEOUT:-30}
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/cpu/mips_page_table_walker.v" "${ROOT_DIR}/rtl/cpu/mips_page_table_tlb_refill.v" "${ROOT_DIR}/tb/unit/mmu/tb_page_table_tlb_refill.sv" -top tb_page_table_tlb_refill -l compile.log
if ! timeout --foreground --signal=TERM --kill-after=5s "${SIM_TIMEOUT}s" \
    ./simv -l sim.log; then
    echo "page-table TLB refill: simulation timeout or runtime failure (SIM_TIMEOUT=${SIM_TIMEOUT}s)" >&2
    exit 1
fi
grep -q "REGRESSION_TEST_SUCCESS page_table_tlb_refill" sim.log
echo "page-table walker TLB refill: PASS"
