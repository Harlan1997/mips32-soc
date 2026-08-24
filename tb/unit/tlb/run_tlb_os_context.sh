#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit/tlb_os_context"}

export MODULES_PAGER=cat PAGER=cat TERM=dumb
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_MMU_ENABLE=1 \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cpu/mips_tlb.v" \
    "${ROOT_DIR}/rtl/cpu/mips_micro_tlb.v" \
    "${ROOT_DIR}/rtl/cpu/mips_mmu.v" \
    "${SCRIPT_DIR}/tb_tlb_os_context.sv" \
    -top tb_tlb_os_context -l vcs.log > /dev/null

./simv -l sim.log > /dev/null

if grep -q "REGRESSION_TEST_SUCCESS tlb_os_context" sim.log; then
    echo "tlb_os_context: PASS"
else
    echo "tlb_os_context: FAIL"
    grep -E "^\[FAIL\]|REGRESSION_TEST_(FAILED|SUCCESS)" sim.log || true
    exit 1
fi
