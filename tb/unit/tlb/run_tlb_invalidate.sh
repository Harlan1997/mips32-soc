#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "$0")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/tlb_invalidate"}
mkdir -p "$RUN_DIR"; cd "$RUN_DIR"
vcs -full64 -sverilog -timescale=1ns/1ps +incdir+"${ROOT_DIR}/rtl/include" "${ROOT_DIR}/rtl/cpu/mips_tlb.v" "${ROOT_DIR}/tb/unit/tlb/tb_tlb_invalidate.sv" -top tb_tlb_invalidate -l compile.log > /dev/null
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS tlb_invalidate" sim.log
