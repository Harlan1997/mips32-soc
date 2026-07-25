#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: run_regression.sh
# Description: Runs multiple UVM simulations with different random seeds to
#              stress test the SOC and AXI bus arbiter.
# ==============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/uvm/regression"}
TESTNAME=${TESTNAME:-soc_bus_stress_test}
NUM_TESTS=${NUM_TESTS:-10}

if [ -z "${FW_HEX:-}" ]; then
    echo "ERROR: FW_HEX must point to the firmware hex artifact."
    exit 1
fi

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "Firmware: $FW_HEX_ABS"
echo "Firmware SHA256: $(sha256sum "$FW_HEX_ABS" | awk '{print $1}')"
echo "UVM test: $TESTNAME"
echo "Run directory: $RUN_DIR"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

echo "Compiling design..."
vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
    -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_hier "${SCRIPT_DIR}"/cov.cfg \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips +incdir+"${ROOT_DIR}"/rtl/cache \
    +incdir+"${SCRIPT_DIR}"/agents +incdir+"${SCRIPT_DIR}"/env +incdir+"${SCRIPT_DIR}"/tests +incdir+"${SCRIPT_DIR}"/seqs +incdir+"${SCRIPT_DIR}"/checkers \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_top/soc_verif_top.sv "${SCRIPT_DIR}"/tb_top/tb_top.sv \
    -l vcs_compile.log

FAIL_COUNT=0
PASS_COUNT=0

echo "======================================================================"
echo " Starting Large-Scale Regression Testing ($NUM_TESTS tests)"
echo "======================================================================"

mkdir -p regression_logs

for i in $(seq 1 $NUM_TESTS); do
    SEED=$RANDOM
    LOG_FILE="regression_logs/test_${i}_seed_${SEED}.log"
    
    echo -n "Running Test $i/$NUM_TESTS with Seed $SEED... "
    
    ./simv +UVM_TESTNAME="$TESTNAME" +ntb_random_seed="$SEED" +FW_HEX="$FW_HEX_ABS" \
        -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_name test_$SEED > "$LOG_FILE" 2>&1
    
    # Check if the test completed successfully by looking for the mailbox success print
    if grep -q "REGRESSION_TEST_SUCCESS" "$LOG_FILE"; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL (Check $LOG_FILE)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo "======================================================================"
echo " Regression Results:"
echo " Total Tests: $NUM_TESTS"
echo " Passed:      $PASS_COUNT"
echo " Failed:      $FAIL_COUNT"
echo "======================================================================"

if [ $FAIL_COUNT -eq 0 ]; then
    echo "SUCCESS: ALL TESTS PASSED!"
    exit 0
else
    echo "ERROR: SOME TESTS FAILED!"
    exit 1
fi
