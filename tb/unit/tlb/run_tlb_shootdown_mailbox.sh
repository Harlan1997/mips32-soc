#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/tlb_shootdown_mailbox"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/cpu/mmu_tlb_shootdown_mailbox.v" "${ROOT_DIR}/tb/unit/tlb/tb_tlb_shootdown_mailbox.sv" -top tb_tlb_shootdown_mailbox -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS tlb_shootdown_mailbox" sim.log
