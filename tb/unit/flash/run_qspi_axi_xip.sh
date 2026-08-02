#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/qspi_axi_xip"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/perips/qspi_cmd_behavioral.v" \
    "${ROOT_DIR}/rtl/perips/qspi_axi_xip.v" \
    "${ROOT_DIR}/rtl/perips/spi_flash_behavioral.v" \
    "${SCRIPT_DIR}/tb_qspi_axi_xip.sv" -l compile.log

./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS qspi_axi_xip" sim.log
