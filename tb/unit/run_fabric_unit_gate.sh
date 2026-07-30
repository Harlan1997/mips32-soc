#!/bin/bash
# =============================================================================
# Fabric unit gate — compiles and runs the axi_crossbar focused unit tests:
#   1. xbar_core     — basic R/W per slave, DECERR read burst + write, bursts
#   2. xbar_qos      — QoS-priority arbitration + round-robin tie-break
#   3. xbar_multi_ot — multi-outstanding boundary depth + cross-slave concurrency
#   4. xbar_ddr      — Phase C.4 DDR window (S3) integrity + FLASH boundary
# =============================================================================
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/unit_tb/fabric"}

source /etc/profile.d/modules.sh 2>/dev/null
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs 2>/dev/null

XBAR="${ROOT_DIR}/rtl/axi/axi_crossbar.v"
MEMSLV="${ROOT_DIR}/tb/unit/fabric/axi_mem_slave.v"
MOSLV="${ROOT_DIR}/tb/unit/fabric/axi_mo_slave.v"
DDRSLV="${ROOT_DIR}/rtl/perips/axi_ddr_behavioral.v"
INC="+incdir+${ROOT_DIR}/rtl/include"

FAILED=0
run_one() {
    local name="$1"; shift
    local tb="$1"; shift
    local dir="${RUN_ROOT}/${name}"
    echo "--- Running ${name} ---"
    mkdir -p "${dir}"
    ( cd "${dir}"
      vcs -full64 -sverilog -timescale=1ns/1ps ${INC} "$@" "${tb}" -l compile.log > /dev/null 2>&1
      ./simv -l sim.log > /dev/null 2>&1 )
    if grep -q "REGRESSION_TEST_SUCCESS ${name#xbar_}" "${dir}/sim.log" 2>/dev/null \
       || grep -q "REGRESSION_TEST_SUCCESS xbar" "${dir}/sim.log" 2>/dev/null; then
        echo "${name}: PASS"
    else
        echo "${name}: FAIL"; FAILED=1
    fi
}

echo "Running Fabric Unit Gate (4 tests)"
run_one xbar_core     "${ROOT_DIR}/tb/unit/fabric/tb_xbar_core.v"     "${XBAR}" "${MEMSLV}"
run_one xbar_qos      "${ROOT_DIR}/tb/unit/fabric/tb_xbar_qos.v"      "${XBAR}" "${MEMSLV}"
run_one xbar_multi_ot "${ROOT_DIR}/tb/unit/fabric/tb_xbar_multi_ot.v" "${XBAR}" "${MOSLV}"
run_one xbar_ddr      "${ROOT_DIR}/tb/unit/fabric/tb_xbar_ddr.v"      "${XBAR}" "${MEMSLV}" "${DDRSLV}"

echo "======================================================================"
if [ "${FAILED}" -eq 0 ]; then
    echo " Fabric Unit Gate Passed (4/4)"; exit 0
else
    echo " Fabric Unit Gate FAILED"; exit 1
fi
