#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/smoke"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    echo "Build it with: make firmware"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "Run directory: $RUN_DIR"
echo "Firmware: $FW_HEX_ABS"
echo "Firmware SHA256: $(sha256sum "$FW_HEX_ABS" | awk '{print $1}')"

export MODULES_PAGER=cat PAGER=cat TERM=dumb
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

# Opt-in L2 selection (default = reset-safe write-through).
#   L2_NONBLOCKING=1 -> non-blocking write-back (full MSHR) drop-in
#   L2_WRITEBACK=1   -> blocking write-back
#   (neither)        -> write-through (default)
l2_define_args=()
if [ "${L2_NONBLOCKING:-0}" = "1" ]; then
    l2_define_args=(+define+SOC_L2_CACHING +define+SOC_L2_NONBLOCKING)
    echo "L2 policy: non-blocking write-back / full MSHR (SOC_L2_NONBLOCKING)"
elif [ "${L2_WRITEBACK:-0}" = "1" ]; then
    l2_define_args=(+define+SOC_L2_WRITEBACK)
    echo "L2 policy: write-back (SOC_L2_WRITEBACK)"
else
    echo "L2 policy: write-through (default)"
fi

vcs_extra_args=()
if [ -n "${VCS_EXTRA_ARGS:-}" ]; then
    read -r -a vcs_extra_args <<< "${VCS_EXTRA_ARGS}"
fi

vcs -full64 -sverilog -timescale=1ns/1ps -cm line+cond+fsm+branch+tgl \
    "${l2_define_args[@]}" \
    "${vcs_extra_args[@]}" \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu \
    +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips \
    +incdir+"${SCRIPT_DIR}" \
    "${ROOT_DIR}"/rtl/cpu/mips_alu.v "${ROOT_DIR}"/rtl/cpu/mips_control.v \
    "${ROOT_DIR}"/rtl/cpu/mips_core.v "${ROOT_DIR}"/rtl/cpu/mips_cp0.v "${ROOT_DIR}"/rtl/cpu/mips_tlb.v "${ROOT_DIR}"/rtl/cpu/mips_mmu.v "${ROOT_DIR}"/rtl/cpu/mips_bpu.v "${ROOT_DIR}"/rtl/cpu/mips_cpu.v "${ROOT_DIR}"/rtl/cpu/mips_ex_mem_reg.v \
    "${ROOT_DIR}"/rtl/cpu/mips_ex_stage.v "${ROOT_DIR}"/rtl/cpu/mips_id_ex_reg.v "${ROOT_DIR}"/rtl/cpu/mips_id_stage.v \
    "${ROOT_DIR}"/rtl/cpu/mips_if_id_reg.v "${ROOT_DIR}"/rtl/cpu/mips_if_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mdu.v \
    "${ROOT_DIR}"/rtl/cpu/mips_mem_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mem_wb_reg.v "${ROOT_DIR}"/rtl/cpu/mips_rob.v "${ROOT_DIR}"/rtl/cpu/mips_regfile.v \
    "${ROOT_DIR}"/rtl/cpu/mips_wb_stage.v "${ROOT_DIR}"/rtl/axi/axi2apb_bridge.v "${ROOT_DIR}"/rtl/axi/axi_crossbar.v "${ROOT_DIR}"/rtl/axi/axi_read_timeout_guard.v \
    "${ROOT_DIR}"/rtl/perips/apb_axi_dma.v "${ROOT_DIR}"/rtl/perips/apb_gpio.v "${ROOT_DIR}"/rtl/perips/apb_vic.v "${ROOT_DIR}"/rtl/perips/apb_wdt.v "${ROOT_DIR}"/rtl/perips/apb_boot_status.v \
    "${ROOT_DIR}"/rtl/perips/apb_timer.v "${ROOT_DIR}"/rtl/perips/apb_uart_16550.v "${ROOT_DIR}"/rtl/perips/apb_qspi_status.v "${ROOT_DIR}"/rtl/perips/qspi_cmd_behavioral.v "${ROOT_DIR}"/rtl/perips/qspi_apb_integration.v "${ROOT_DIR}"/rtl/perips/axi_spi_flash.v "${ROOT_DIR}"/rtl/perips/axi_flash_image_model.v \
    "${ROOT_DIR}"/rtl/perips/axi_sram.v "${ROOT_DIR}"/rtl/perips/axi_ddr_model.v "${ROOT_DIR}"/rtl/perips/axi_ddr_behavioral.v "${ROOT_DIR}"/rtl/perips/axi_boot_rom.v "${ROOT_DIR}"/rtl/perips/jtag_debug_top.v \
    "${ROOT_DIR}"/rtl/cache/dcache.v "${ROOT_DIR}"/rtl/cache/icache.v "${ROOT_DIR}"/rtl/cache/l2_cache.v "${ROOT_DIR}"/rtl/cache/l2_cache_caching.v "${ROOT_DIR}"/rtl/cache/l2_cache_wt.v "${ROOT_DIR}"/rtl/cache/l2_cache_nb.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_mips_soc.v -l vcs.log

./simv +FW_HEX="$FW_HEX_ABS" -cm line+cond+fsm+branch+tgl -l sim.log
urg -dir simv.vdb -report textReportRaw -format text
urg -dir simv.vdb -elfile "${ROOT_DIR}/tb/coverage/product_exclusions.el" -excl_strict -report textReportFinal -format text
