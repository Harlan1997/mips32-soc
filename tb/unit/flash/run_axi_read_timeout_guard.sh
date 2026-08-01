#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/axi_read_timeout_guard"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/axi/axi_read_timeout_guard.v" \
    "${SCRIPT_DIR}/tb_axi_read_timeout_guard.sv" -l compile.log

./simv -no_save -l sim.log
grep -q "REGRESSION_TEST_SUCCESS axi_read_timeout_guard" sim.log
