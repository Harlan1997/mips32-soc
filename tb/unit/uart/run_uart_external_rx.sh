#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/uart_external_rx"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/perips" \
    "${ROOT_DIR}/rtl/perips/apb_uart_16550.v" \
    "${SCRIPT_DIR}/tb_uart_external_rx.sv" -l compile.log
./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS uart_external_rx" sim.log
echo "UART external RX gate: PASS"
