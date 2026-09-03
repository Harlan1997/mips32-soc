#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/smoke"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}
VCS_JOBS=${VCS_JOBS:-1}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

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

if ! [[ "${VCS_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: VCS_JOBS must be a positive integer: ${VCS_JOBS}" >&2
    exit 1
fi
if [[ ! -x "${EDA_RUNNER}" ]]; then
    echo "ERROR: EDA runner is not executable: ${EDA_RUNNER}" >&2
    exit 1
fi

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

sva_args=()
sva_sources=()
cm_args="line+cond+fsm+branch+tgl"
coverage_enabled=1
if [ "${SKIP_COVERAGE:-0}" = "1" ]; then
    coverage_enabled=0
    cm_args=""
    echo "Coverage: disabled by explicit SKIP_COVERAGE=1"
fi
if [ "${SVA_ENABLE:-0}" = "1" ]; then
    sva_args=(+define+SVA_ENABLE +define+VIC_PRIORITY_CHECKER_ENABLE)
    sva_sources=(
        "${ROOT_DIR}/rtl/clock/reset_sync.v"
        "${ROOT_DIR}/tb/sva/axi4_protocol_props.sv"
        "${ROOT_DIR}/tb/sva/apb_protocol_props.sv"
        "${ROOT_DIR}/tb/sva/cache_state_props.sv"
        "${ROOT_DIR}/tb/sva/tlb_lookup_props.sv"
        "${ROOT_DIR}/tb/sva/page_table_walker_props.sv"
        "${ROOT_DIR}/tb/sva/vic_priority_checker.sv"
        "${ROOT_DIR}/tb/sva/vic_contract_props.sv"
        "${ROOT_DIR}/tb/sva/vic_priority_bind.sv"
        "${ROOT_DIR}/tb/sva/l1_maintenance_props.sv"
        "${ROOT_DIR}/tb/sva/l1_resource_props.sv"
        "${ROOT_DIR}/tb/sva/reset_sync_props.sv"
        "${ROOT_DIR}/tb/sva/sva_bind.sv"
    )
    if [ "${coverage_enabled}" = "1" ]; then
        cm_args="line+cond+fsm+branch+tgl+assert"
    fi
fi

vcs_args=(-full64 -sverilog -timescale=1ns/1ps)
if [ "${coverage_enabled}" = "1" ]; then
    vcs_args+=(-cm "${cm_args}")
fi
"${EDA_RUNNER}" vcs -j"${VCS_JOBS}" "${vcs_args[@]}" \
    "${l2_define_args[@]}" \
    "${sva_args[@]}" \
    "${vcs_extra_args[@]}" \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu \
    +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips \
    +incdir+"${SCRIPT_DIR}" \
    "${ROOT_DIR}"/rtl/cpu/dual_core_axi_subsystem.v \
    "${ROOT_DIR}"/rtl/cpu/cpu_scheduler.v "${ROOT_DIR}"/rtl/cpu/mips_page_table_walker.v \
    "${ROOT_DIR}"/rtl/cpu/mips_alu.v "${ROOT_DIR}"/rtl/cpu/mips_control.v \
    "${ROOT_DIR}"/rtl/cpu/mips_core.v "${ROOT_DIR}"/rtl/cpu/mips_cp0.v "${ROOT_DIR}"/rtl/cpu/mips_tlb.v "${ROOT_DIR}"/rtl/cpu/mips_micro_tlb.v "${ROOT_DIR}"/rtl/cpu/mips_mmu.v "${ROOT_DIR}"/rtl/cpu/mips_bpu.v "${ROOT_DIR}"/rtl/cpu/mips_cpu.v "${ROOT_DIR}"/rtl/cpu/mips_ex_mem_reg.v \
    "${ROOT_DIR}"/rtl/cpu/mips_ex_stage.v "${ROOT_DIR}"/rtl/cpu/mips_id_ex_reg.v "${ROOT_DIR}"/rtl/cpu/mips_id_stage.v \
    "${ROOT_DIR}"/rtl/cpu/mips_perf_counters.v "${ROOT_DIR}"/rtl/cpu/mips_fpu.v \
    "${ROOT_DIR}"/rtl/cpu/mips_if_id_reg.v "${ROOT_DIR}"/rtl/cpu/mips_if_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mdu.v \
    "${ROOT_DIR}"/rtl/cpu/mips_mem_stage.v "${ROOT_DIR}"/rtl/cpu/mips_mem_wb_reg.v "${ROOT_DIR}"/rtl/cpu/mips_rob.v "${ROOT_DIR}"/rtl/cpu/mips_regfile.v \
    "${ROOT_DIR}"/rtl/cpu/mips_wb_stage.v "${ROOT_DIR}"/rtl/cpu/mips_rob_fifo.v "${ROOT_DIR}"/rtl/axi/axi2apb_bridge.v "${ROOT_DIR}"/rtl/axi/axi_crossbar.v "${ROOT_DIR}"/rtl/axi/axi_read_timeout_guard.v \
    "${ROOT_DIR}"/rtl/perips/apb_axi_dma.v "${ROOT_DIR}"/rtl/perips/apb_gpio.v "${ROOT_DIR}"/rtl/perips/apb_vic.v "${ROOT_DIR}"/rtl/perips/apb_wdt.v "${ROOT_DIR}"/rtl/perips/apb_boot_status.v "${ROOT_DIR}"/rtl/perips/apb_ddr4_status.v "${ROOT_DIR}"/rtl/perips/apb_perf_counters.v \
    "${ROOT_DIR}"/rtl/cpu/mmu_asid_allocator.v "${ROOT_DIR}"/rtl/cpu/mmu_page_table_allocator.v "${ROOT_DIR}"/rtl/cpu/mmu_page_frame_allocator.v "${ROOT_DIR}"/rtl/cpu/mmu_context_allocator.v "${ROOT_DIR}"/rtl/cpu/mmu_ipi_shootdown.v \
    "${ROOT_DIR}"/rtl/cpu/mmu_tlb_shootdown_mailbox.v \
    "${ROOT_DIR}"/rtl/perips/apb_mmu_context_status.v "${ROOT_DIR}"/rtl/perips/apb_mmu_ipi_status.v \
    "${ROOT_DIR}"/rtl/perips/apb_timer.v "${ROOT_DIR}"/rtl/perips/apb_uart_16550.v "${ROOT_DIR}"/rtl/perips/uart_pad_wrapper.v "${ROOT_DIR}"/rtl/perips/apb_qspi_status.v "${ROOT_DIR}"/rtl/perips/qspi_cmd_behavioral.v "${ROOT_DIR}"/rtl/perips/qspi_apb_integration.v "${ROOT_DIR}"/rtl/perips/qspi_shared_pin_arbiter.v "${ROOT_DIR}"/rtl/perips/qspi_soc_pad_mux.v "${ROOT_DIR}"/rtl/perips/qspi_axi_xip.v "${ROOT_DIR}"/rtl/perips/axi_spi_flash.v "${ROOT_DIR}"/rtl/perips/axi_flash_image_model.v \
    "${ROOT_DIR}"/rtl/perips/axi_sram.v "${ROOT_DIR}"/rtl/perips/axi_ddr_model.v "${ROOT_DIR}"/rtl/perips/ecc_secded_32.v "${ROOT_DIR}"/rtl/perips/axi_ddr4_controller.v "${ROOT_DIR}"/rtl/perips/axi_boot_rom.v "${ROOT_DIR}"/rtl/perips/jtag_debug_top.v \
    "${ROOT_DIR}"/rtl/cache/dcache.v "${ROOT_DIR}"/rtl/cache/icache.v "${ROOT_DIR}"/rtl/cache/l1_cache_nb.v "${ROOT_DIR}"/rtl/cache/l1_cache_nb_axi_bridge.v "${ROOT_DIR}"/rtl/cache/l1_cache_nb_cpu_axi.v "${ROOT_DIR}"/rtl/cache/l2_cache.v "${ROOT_DIR}"/rtl/cache/l2_cache_caching.v "${ROOT_DIR}"/rtl/cache/l2_cache_wt.v "${ROOT_DIR}"/rtl/cache/l2_cache_nb.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${sva_sources[@]}" \
    "${SCRIPT_DIR}"/tb_mips_soc.v -l vcs.log

sim_extra_args=()
if [ -n "${SIM_EXTRA_ARGS:-}" ]; then
    read -r -a sim_extra_args <<< "${SIM_EXTRA_ARGS}"
fi
if [ -n "${LINUX_EXTRA_SIM_ARGS:-}" ]; then
    read -r -a linux_extra_sim_args <<< "${LINUX_EXTRA_SIM_ARGS}"
    sim_extra_args+=("${linux_extra_sim_args[@]}")
fi
if [ -n "${LINUX_TRACE_WINDOW_ARGS:-}" ]; then
    read -r -a linux_trace_window_args <<< "${LINUX_TRACE_WINDOW_ARGS}"
    sim_extra_args+=("${linux_trace_window_args[@]}")
fi
sim_args=(+FW_HEX="$FW_HEX_ABS" "${sim_extra_args[@]}")
if [ -n "${RETIRE_TRACE:-}" ]; then
    sim_args+=(+RETIRE_TRACE="$(realpath -m "${RETIRE_TRACE}")")
fi
if [ "${coverage_enabled}" = "1" ]; then
    sim_args+=(-cm "${cm_args}")
fi
# Keep VCS's internal runtime log separate from any caller's stdout
# redirection.  Some long-running gates invoke this script as `run.sh
# >sim.log`; writing sim.log here as well would give two writers ownership of
# the same file and can truncate or interleave diagnostics.  Publish the
# complete VCS log only after simulation has exited.
set +e
"${EDA_RUNNER}" ./simv "${sim_args[@]}" -l sim_runtime.log
sim_status=$?
set -e
cp sim_runtime.log sim.log
if [ "${sim_status}" -ne 0 ]; then
    exit "${sim_status}"
fi
if grep -q "SoC Simulation Timeout" sim.log; then
    echo "ERROR: SoC simulation watchdog expired"
    exit 1
fi
if grep -Eq "REGRESSION_TEST_FAILED|Comprehensive SoC Test Failed" sim.log; then
    echo "ERROR: SoC firmware regression reported failure"
    exit 1
fi
if [ "${coverage_enabled}" = "1" ]; then
    urg -dir simv.vdb -report textReportRaw -format text
    if [ "${SKIP_URG_EXCLUSION_CHECK:-0}" = "1" ]; then
        echo "URG exclusion application: SKIPPED by explicit caller opt-in"
    else
        urg -dir simv.vdb -elfile "${ROOT_DIR}/tb/coverage/product_exclusions.el" -excl_strict -report textReportFinal -format text
    fi
fi
