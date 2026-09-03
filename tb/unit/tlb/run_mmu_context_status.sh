#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mmu_context_status"}; mkdir -p "$RUN_DIR"; cd "$RUN_DIR"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/cpu/mmu_asid_allocator.v" "${ROOT_DIR}/rtl/cpu/mmu_page_table_allocator.v" "${ROOT_DIR}/rtl/cpu/mmu_page_frame_allocator.v" "${ROOT_DIR}/rtl/cpu/mmu_context_allocator.v" "${ROOT_DIR}/rtl/cpu/mmu_tlb_shootdown_mailbox.v" "${ROOT_DIR}/rtl/perips/apb_mmu_context_status.v" "${SCRIPT_DIR}/tb_mmu_context_status.sv" -top tb_mmu_context_status -l compile.log > /dev/null
./simv -l sim.log > /dev/null
grep -q "REGRESSION_TEST_SUCCESS mmu_context_status" sim.log && echo "mmu-context-status: PASS"
