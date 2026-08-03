#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/uart_pad_wrapper"}
source /etc/profile.d/modules.sh
module load vcs
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/uart_pad_wrapper.v" "${SCRIPT_DIR}/tb_uart_pad_wrapper.sv" -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS uart_pad_wrapper" sim.log
echo "UART pad wrapper gate: PASS"
