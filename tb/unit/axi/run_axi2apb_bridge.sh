#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd); RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/axi2apb_write_timing"}; mkdir -p "$RUN_DIR"; cd "$RUN_DIR"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/axi/axi2apb_bridge.v" "${ROOT_DIR}/tb/unit/axi/tb_axi2apb_bridge.sv" -top tb_axi2apb_bridge -l compile.log > /dev/null
./simv -l sim.log > /dev/null
grep -q "REGRESSION_TEST_SUCCESS axi2apb_write_timing" sim.log && echo "axi2apb-write-timing: PASS"
