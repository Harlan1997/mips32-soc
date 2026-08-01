#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/ddr4_phy_behavioral"}

source /etc/profile.d/modules.sh 2>/dev/null
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs 2>/dev/null

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${ROOT_DIR}/rtl/perips/ddr4_phy_behavioral.v" \
    "${ROOT_DIR}/tb/unit/ddr4/tb_ddr4_phy_behavioral.sv" \
    -l compile.log > /dev/null 2>&1
./simv -l sim.log > /dev/null 2>&1

if grep -q "REGRESSION_TEST_SUCCESS ddr4_phy_behavioral" sim.log; then
    echo "DDR4 PHY behavioral gate: PASS"
    exit 0
fi

echo "DDR4 PHY behavioral gate: FAIL"
tail -80 sim.log
exit 1
