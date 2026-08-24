#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/micro_tlb"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cpu/mips_micro_tlb.v" \
    "${SCRIPT_DIR}/tb_micro_tlb.sv" \
    -top tb_micro_tlb -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS micro_tlb" sim.log
echo "micro_tlb: PASS"
