#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/qspi_retry_policy"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/qspi_retry_policy.v" "${ROOT_DIR}/tb/unit/flash/tb_qspi_retry_policy.sv" -top tb_qspi_retry_policy -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS qspi_retry_policy" sim.log
