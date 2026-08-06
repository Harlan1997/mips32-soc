#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/soc_memory_quad_xip"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/axi/axi_read_timeout_guard.v" \
    "${ROOT_DIR}/rtl/perips/ecc_secded_32.v" \
    "${ROOT_DIR}/rtl/perips/axi_ddr4_controller.v" \
    "${ROOT_DIR}/rtl/perips/axi_ddr_model.v" \
    "${ROOT_DIR}/rtl/perips/axi_flash_image_model.v" \
    "${ROOT_DIR}/rtl/perips/axi_spi_flash.v" \
    "${ROOT_DIR}/rtl/perips/axi_boot_rom.v" \
    "${ROOT_DIR}/rtl/perips/qspi_cmd_behavioral.v" \
    "${ROOT_DIR}/rtl/perips/qspi_axi_xip.v" \
    "${ROOT_DIR}/rtl/perips/qspi_retry_policy.v" \
    "${ROOT_DIR}/rtl/perips/qspi_flash_quad_behavioral.v" \
    "${ROOT_DIR}/rtl/cache/l2_cache.v" \
    "${ROOT_DIR}/rtl/cache/l2_cache_wt.v" \
    "${ROOT_DIR}/rtl/soc_memory_subsystem.v" \
    "${SCRIPT_DIR}/tb_soc_memory_quad_xip.sv" -l compile.log

./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS soc_memory_quad_xip" sim.log
