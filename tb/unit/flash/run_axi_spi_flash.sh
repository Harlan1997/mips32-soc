#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/axi_spi_flash"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/perips/axi_spi_flash.v" \
    "${SCRIPT_DIR}/tb_axi_spi_flash.sv" -l compile.log

./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS axi_spi_flash" sim.log
