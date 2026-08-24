#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/vic_priority_checker"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+VIC_PRIORITY_CHECKER_ENABLE \
    "${ROOT_DIR}/rtl/perips/apb_vic.v" \
    "${ROOT_DIR}/tb/sva/vic_priority_checker.sv" \
    "${ROOT_DIR}/tb/sva/vic_priority_bind.sv" \
    "${ROOT_DIR}/tb/unit/vic/tb_vic.v" \
    -top tb_vic -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS vic" sim.log
if grep -q "VIC_PRIORITY_CHECKER_FAIL" sim.log; then
    echo "vic priority checker: FAIL" >&2
    exit 1
fi
echo "vic priority checker: PASS"
