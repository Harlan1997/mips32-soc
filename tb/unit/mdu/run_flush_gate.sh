#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mdu_flush"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-2700@localhost}
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-2700@localhost}

mkdir -p "${RUN_DIR}"
(
    cd "${RUN_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" \
        "${ROOT_DIR}/rtl/cpu/mips_mdu.v" \
        "${ROOT_DIR}/tb/unit/mdu/tb_mdu.v" \
        -top tb_mdu -l compile.log
    ./simv -l sim.log
)

grep -q "REGRESSION_TEST_SUCCESS mdu" "${RUN_DIR}/sim.log"
echo "MDU flush gate: PASS"
