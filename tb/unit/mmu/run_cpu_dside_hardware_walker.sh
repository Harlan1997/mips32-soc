#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_dside_hardware_walker"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps +define+SOC_MMU_ENABLE=1 +incdir+"${ROOT_DIR}/rtl/include" \
  "${ROOT_DIR}/rtl/cpu/mips_alu.v" "${ROOT_DIR}/rtl/cpu/mips_bpu.v" \
  "${ROOT_DIR}/rtl/cpu/mips_control.v" "${ROOT_DIR}/rtl/cpu/mips_cp0.v" \
  "${ROOT_DIR}/rtl/cpu/mips_cpu.v" "${ROOT_DIR}/rtl/cpu/mips_ex_mem_reg.v" \
  "${ROOT_DIR}/rtl/cpu/mips_ex_stage.v" "${ROOT_DIR}/rtl/cpu/mips_id_ex_reg.v" \
  "${ROOT_DIR}/rtl/cpu/mips_id_stage.v" "${ROOT_DIR}/rtl/cpu/mips_if_id_reg.v" \
  "${ROOT_DIR}/rtl/cpu/mips_if_stage.v" "${ROOT_DIR}/rtl/cpu/mips_mdu.v" \
  "${ROOT_DIR}/rtl/cpu/mips_mem_stage.v" "${ROOT_DIR}/rtl/cpu/mips_mem_wb_reg.v" \
  "${ROOT_DIR}/rtl/cpu/mips_mmu.v" "${ROOT_DIR}/rtl/cpu/mips_page_table_walker.v" \
  "${ROOT_DIR}/rtl/cpu/mips_regfile.v" "${ROOT_DIR}/rtl/cpu/mips_rob.v" \
  "${ROOT_DIR}/rtl/cpu/mips_tlb.v" "${ROOT_DIR}/rtl/cpu/mips_wb_stage.v" \
  "${ROOT_DIR}/tb/unit/mmu/tb_cpu_dside_hardware_walker.sv" \
  -top tb_cpu_dside_hardware_walker -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS cpu_dside_hardware_walker" sim.log
echo "CPU D-side hardware walker integration: PASS"
