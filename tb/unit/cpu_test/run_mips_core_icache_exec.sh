#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mips_core_icache_exec"}
SIM_TIMEOUT=${SIM_TIMEOUT:-120}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_core_icache_exec.sv" \
    -top tb_mips_core_icache_exec -l compile.log
if [[ "${SIM_TIMEOUT}" == "0" ]]; then
    ./simv -no_save -l sim.log
else
    timeout --foreground --signal=TERM --kill-after=5s "${SIM_TIMEOUT}s" \
        ./simv -no_save -l sim.log
fi
grep -q "REGRESSION_TEST_SUCCESS mips_core_icache_exec" sim.log
