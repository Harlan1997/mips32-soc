#!/bin/bash
# =============================================================================
# run_mmu_refill.sh — Phase B.3.d/B.3.4 proof-of-concept gate.
#
# Compiles the full SoC TB with +define+SOC_MMU_ENABLE=1 (project default
# stays 0; this is opt-in via the ifndef guard in soc_config.vh) and runs the
# mmu_refill firmware (tb/soc_test/fw/tests/mmu_refill), which installs a
# single identity-mapped TLB entry per fault via a real TLB-refill exception
# handler and retries. Proves the CP0/TLB/mips_mmu translation path works
# end to end under real firmware -- NOT a real Linux-capable page-table-based
# MMU (no demand paging, no page tables, no per-process ASID reuse).
# =============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/mmu_refill"}
FW_DIR="${ROOT_DIR}/tb/soc_test/fw/tests/mmu_refill"
FW_HEX="${FW_DIR}/firmware.hex"

export MODULES_PAGER=cat PAGER=cat TERM=dumb
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

echo "--- Building mmu_refill firmware ---"
make -C "${FW_DIR}"

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: firmware build did not produce ${FW_HEX}"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "Run directory: $RUN_DIR"
echo "Firmware: $FW_HEX_ABS"

vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_MMU_ENABLE=1 \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu \
    +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips \
    +incdir+"${ROOT_DIR}"/tb/soc_test \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${ROOT_DIR}"/tb/soc_test/tb_mips_soc.v -l vcs.log

./simv +FW_HEX="$FW_HEX_ABS" -l sim.log

if grep -q "REGRESSION_TEST_SUCCESS" sim.log && grep -q "mmu_refill: PASS" sim.log; then
    echo "SUCCESS: MMU REFILL GATE PASSED"
    exit 0
else
    echo "ERROR: mmu_refill gate did not pass"
    grep -E "mmu_refill:|REGRESSION_TEST" sim.log || true
    exit 1
fi
