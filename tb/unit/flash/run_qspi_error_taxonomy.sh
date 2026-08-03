#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/qspi_error_taxonomy"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/apb_qspi_status.v" "${ROOT_DIR}/tb/unit/flash/tb_qspi_error_taxonomy.sv" -top tb_qspi_error_taxonomy -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS qspi_error_taxonomy" sim.log
