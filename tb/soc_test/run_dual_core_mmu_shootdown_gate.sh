#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/dual_core_mmu_shootdown"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/mmu_dual_core_shootdown"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}

if [ ! -f "${FW_HEX}" ]; then
  make -C "${ROOT_DIR}/tb/soc_test/fw" \
    FW_NAME=mmu_dual_core_shootdown OUT_DIR="${FW_DIR}" FW_BASE=firmware all
fi

FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_ENABLE_DUAL_CORE +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1 +define+SOC_MICRO_TLB_ENABLE=1 +define+TB_DUAL_CORE_MMU_SHOOTDOWN +define+TB_LINUX_BOOT_TRACE +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
SIM_EXTRA_ARGS="+BOOT_ROM_HEX=${FW_HEX} +LINUX_PC_TRACE=1 +LINUX_PC_TRACE_LIMIT=160 +LINUX_PC_TRACE_START=bfc00000 +LINUX_PC_TRACE_END=bfc00500" \
  "${SCRIPT_DIR}/run.sh"

grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
echo 'dual-core MMU shootdown end-to-end gate: PASS'
