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
    "${ROOT_DIR}"/rtl/cpu/mips_alu.v "${ROOT_DIR}"/rtl/cpu/mips_control.v \
    "${ROOT_DIR}"/rtl/cpu/mips_core.v "${ROOT_DIR}"/rtl/cpu/mips_cp0.v "${ROOT_DIR}"/rtl/cpu/mips_tlb.v "${ROOT_DIR}"/rtl/cpu/mips_mmu.v "${ROOT_DIR}"/rtl/cpu/mips_bpu.v "${ROOT_DIR}"/rtl/cpu/mips_cpu.v "${ROOT_DIR}"/rtl/cpu/mips_ex_mem_reg.v \
    "${ROOT_DIR}"/rtl/cpu/mips_ex_stage.v "${ROOT_DIR}"/rtl/cpu/mips_id_ex_reg.v "${ROOT_DIR}"/rtl/cpu/mips_id_stage.v \
    "${ROOT_DIR}"/rtl/cpu/mips_if_id_reg.v "${ROOT_DIR}"/rtl/cpu/mips_if_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mdu.v \
    "${ROOT_DIR}"/rtl/cpu/mips_mem_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mem_wb_reg.v "${ROOT_DIR}"/rtl/cpu/mips_rob.v "${ROOT_DIR}"/rtl/cpu/mips_regfile.v \
    "${ROOT_DIR}"/rtl/cpu/mips_wb_stage.v "${ROOT_DIR}"/rtl/axi/axi2apb_bridge.v "${ROOT_DIR}"/rtl/axi/axi_crossbar.v "${ROOT_DIR}"/rtl/axi/axi_read_timeout_guard.v \
    "${ROOT_DIR}"/rtl/perips/apb_axi_dma.v "${ROOT_DIR}"/rtl/perips/apb_gpio.v "${ROOT_DIR}"/rtl/perips/apb_vic.v "${ROOT_DIR}"/rtl/perips/apb_wdt.v "${ROOT_DIR}"/rtl/perips/apb_boot_status.v \
    "${ROOT_DIR}"/rtl/perips/apb_timer.v "${ROOT_DIR}"/rtl/perips/apb_uart_16550.v "${ROOT_DIR}"/rtl/perips/apb_qspi_status.v "${ROOT_DIR}"/rtl/perips/qspi_cmd_behavioral.v "${ROOT_DIR}"/rtl/perips/qspi_apb_integration.v "${ROOT_DIR}"/rtl/perips/qspi_shared_pin_arbiter.v "${ROOT_DIR}"/rtl/perips/qspi_soc_pad_mux.v "${ROOT_DIR}"/rtl/perips/axi_spi_flash.v "${ROOT_DIR}"/rtl/perips/axi_flash_image_model.v \
    "${ROOT_DIR}"/rtl/perips/axi_sram.v "${ROOT_DIR}"/rtl/perips/axi_ddr_model.v "${ROOT_DIR}"/rtl/perips/axi_ddr_behavioral.v "${ROOT_DIR}"/rtl/perips/axi_boot_rom.v "${ROOT_DIR}"/rtl/perips/jtag_debug_top.v \
    "${ROOT_DIR}"/rtl/cache/dcache.v "${ROOT_DIR}"/rtl/cache/icache.v "${ROOT_DIR}"/rtl/cache/l2_cache.v "${ROOT_DIR}"/rtl/cache/l2_cache_caching.v "${ROOT_DIR}"/rtl/cache/l2_cache_wt.v "${ROOT_DIR}"/rtl/cache/l2_cache_nb.v \
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
