#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_srs_privilege"}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
"${EDA_RUNNER}" vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_SRS_ENABLE=1 \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_cpu_srs_privilege.sv" \
    -top tb_mips_cpu_srs_privilege -l compile.log
"${EDA_RUNNER}" ./simv -no_save -l sim.log
grep -q '^SRS_PRIVILEGE_TEST_PASS ' sim.log
grep -q '^DI_EI_USER_PRIVILEGE_PASS ' sim.log
echo "CPU SRS privilege gate: PASS"
