#!/bin/bash
# Block-level sanity for Phase B.3.c mips_mmu. Exits 0 on TB PASS.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit/mmu"}
mkdir -p "$RUN_DIR"; cd "$RUN_DIR"

export MODULES_PAGER=cat PAGER=cat TERM=dumb
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    "${ROOT_DIR}/rtl/cpu/mips_mmu.v" \
    "${SCRIPT_DIR}/tb_mips_mmu.sv" \
    -top tb_mips_mmu -l vcs.log > /dev/null

./simv -l sim.log > /dev/null

if grep -q "^TB PASS" sim.log; then
    echo "mmu: PASS"; exit 0
else
    echo "mmu: FAIL"; grep -E "^\[FAIL\]|^TB (FAIL|TIMEOUT)" sim.log; exit 1
fi
