#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_lui_lw_forward"}
VCS_EXTRA_ARGS=${VCS_EXTRA_ARGS:-}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
vcs_extra_args=()
if [[ -n "${VCS_EXTRA_ARGS}" ]]; then
    read -r -a vcs_extra_args <<< "${VCS_EXTRA_ARGS}"
fi
vcs -full64 -sverilog -timescale=1ns/1ps \
    "${vcs_extra_args[@]}" \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_cpu_lui_lw_forward.sv" \
    -top tb_mips_cpu_lui_lw_forward -l compile.log
SIM_ARGS=${SIM_ARGS:-}
./simv -no_save ${SIM_ARGS} -l sim.log
grep -q "REGRESSION_TEST_SUCCESS mips_cpu_lui_lw_forward" sim.log
echo "CPU LUI-to-LW forwarding gate: PASS"
