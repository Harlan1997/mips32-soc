#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/product_mmu_boot"}

MICRO_TLB_DEFINE=()
if [ "${SOC_MICRO_TLB_ENABLE:-0}" = "1" ]; then
    MICRO_TLB_DEFINE=(+define+SOC_MICRO_TLB_ENABLE=1)
fi

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
RUN_DIR=$(cd "${RUN_DIR}" && pwd)
FW_DIR="${RUN_DIR}/firmware"

make -C "${ROOT_DIR}/tb/soc_test/fw" \
    FW_NAME=mmu_product_boot OUT_DIR="${FW_DIR}" FW_BASE=firmware all

cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1 \
    "${MICRO_TLB_DEFINE[@]}" \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    +incdir+"${ROOT_DIR}/rtl/axi" +incdir+"${ROOT_DIR}/rtl/perips" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v \
    "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_product_mmu_boot.sv -l compile.log

./simv -no_save \
    +FW_HEX="${FW_DIR}/firmware.hex" \
    +BOOT_ROM_HEX="${FW_DIR}/firmware.hex" -l sim.log
grep -q "REGRESSION_TEST_SUCCESS product_mmu_boot" sim.log
