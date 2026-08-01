#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/product_manifest_handoff"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
RUN_DIR=$(cd "${RUN_DIR}" && pwd)
FW_DIR="${RUN_DIR}/firmware"

MMU_DEFINE=()
KSEG0_RUNTIME_ARG=()
if [ "${SOC_MMU_ENABLE:-0}" = "1" ]; then
    MMU_DEFINE=(+define+SOC_MMU_ENABLE=1)
    KSEG0_RUNTIME_ARG=(+EXPECT_KSEG0_RUNTIME)
fi

make -C "${ROOT_DIR}/tb/soc_test/fw" \
    FW_NAME=boot_manifest_handoff OUT_DIR="${FW_DIR}" FW_BASE=firmware all

cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_PRODUCT_BOOT_ENABLE=1 \
    "${MMU_DEFINE[@]}" \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    +incdir+"${ROOT_DIR}/rtl/axi" +incdir+"${ROOT_DIR}/rtl/perips" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v \
    "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_product_manifest_handoff.sv -l compile.log

./simv -no_save \
    +BOOT_ROM_HEX="${FW_DIR}/boot_rom.hex" \
    +SPI_FLASH_HEX="${FW_DIR}/flash_image.hex" \
    "${KSEG0_RUNTIME_ARG[@]}" \
    -l sim_valid.log
grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_valid" sim_valid.log

./simv -no_save \
    +BOOT_ROM_HEX="${FW_DIR}/boot_rom.hex" \
    +SPI_FLASH_HEX="${FW_DIR}/flash_image_bad_crc.hex" \
    +EXPECT_BOOT_FAILURE \
    +EXPECT_FAILURE_NAME=bad_crc \
    -l sim_bad_crc.log
grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_bad_crc" sim_bad_crc.log

run_negative_image() {
    local name=$1

    ./simv -no_save \
        +BOOT_ROM_HEX="${FW_DIR}/boot_rom.hex" \
        +SPI_FLASH_HEX="${FW_DIR}/negative/${name}.hex" \
        +EXPECT_BOOT_FAILURE \
        +EXPECT_FAILURE_NAME="${name}" \
        -l "sim_${name}.log"
    grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_${name}" "sim_${name}.log"
}

for negative_case in \
    bad_magic \
    bad_version \
    bad_header_bytes \
    bad_payload_offset \
    bad_payload_length_zero \
    bad_payload_length_unaligned \
    bad_payload_length_bounds \
    bad_load_address \
    bad_entry_address \
    bad_flags; do
    run_negative_image "${negative_case}"
done

# Compile a second top with a deliberately short guard threshold. The serial
# responder remains untouched; the production timeout logic must turn its
# bounded AXI SLVERR into the Boot ROM's DBE failure record.
vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_PRODUCT_BOOT_ENABLE=1 \
    "${MMU_DEFINE[@]}" \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    +incdir+"${ROOT_DIR}/rtl/axi" +incdir+"${ROOT_DIR}/rtl/perips" \
    +incdir+"${SCRIPT_DIR}" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v \
    "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v \
    "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_product_manifest_xip_timeout.sv \
    -o simv_xip_timeout -l compile_xip_timeout.log

./simv_xip_timeout -no_save \
    +BOOT_ROM_HEX="${FW_DIR}/boot_rom.hex" \
    +SPI_FLASH_HEX="${FW_DIR}/flash_image.hex" \
    -l sim_xip_timeout.log
grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_xip_timeout" sim_xip_timeout.log
