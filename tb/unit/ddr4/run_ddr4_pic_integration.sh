#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/ddr4_pic_integration"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/axi" +incdir+"${ROOT_DIR}/rtl/perips" \
    "${ROOT_DIR}/rtl/axi/axi2apb_bridge.v" \
    "${ROOT_DIR}/rtl/perips/apb_axi_dma.v" "${ROOT_DIR}/rtl/perips/apb_gpio.v" \
    "${ROOT_DIR}/rtl/perips/apb_vic.v" "${ROOT_DIR}/rtl/perips/apb_wdt.v" \
    "${ROOT_DIR}/rtl/perips/apb_boot_status.v" "${ROOT_DIR}/rtl/cpu/mmu_asid_allocator.v" \
    "${ROOT_DIR}/rtl/cpu/mmu_tlb_shootdown_mailbox.v" "${ROOT_DIR}/rtl/cpu/mmu_page_table_allocator.v" "${ROOT_DIR}/rtl/cpu/mmu_context_allocator.v" "${ROOT_DIR}/rtl/perips/apb_mmu_context_status.v" \
    "${ROOT_DIR}/rtl/perips/apb_qspi_status.v" "${ROOT_DIR}/rtl/perips/apb_ddr4_status.v" \
    "${ROOT_DIR}/rtl/perips/apb_perf_counters.v" \
    "${ROOT_DIR}/rtl/perips/qspi_cmd_behavioral.v" "${ROOT_DIR}/rtl/perips/qspi_apb_integration.v" \
    "${ROOT_DIR}/rtl/perips/apb_timer.v" "${ROOT_DIR}/rtl/perips/apb_uart_16550.v" \
    "${ROOT_DIR}/rtl/soc_peripheral_subsystem.v" \
    "${SCRIPT_DIR}/tb_ddr4_pic_integration.sv" -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS ddr4_pic_integration" sim.log
echo "DDR4 PIC integration gate: PASS"
