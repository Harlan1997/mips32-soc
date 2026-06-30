#!/bin/bash

# ==============================================================================
# Script: run_regression.sh
# Description: Runs multiple UVM simulations with different random seeds to
#              stress test the SOC and AXI bus arbiter.
# ==============================================================================

    echo "Copying firmware to UVM directory..."
    cp ../soc_test/fw/firmware.hex .

    echo "Compiling design..."
    vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
        -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_hier cov.cfg \
        +incdir+../../rtl/cpu +incdir+../../rtl/axi +incdir+../../rtl/perips +incdir+../../rtl/cache \
        +incdir+./agents +incdir+./env +incdir+./tests \
        ../../rtl/cpu/*.v ../../rtl/axi/*.v ../../rtl/perips/*.v ../../rtl/cache/*.v ../../rtl/mips_soc.v \
        tb_top/tb_top.sv \
        -l vcs_compile.log
    
    if [ $? -ne 0 ]; then
        echo "Compilation failed!"
        exit 1
    fi

NUM_TESTS=10
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
    
    ./simv +UVM_TESTNAME=soc_bus_stress_test +ntb_random_seed=$SEED -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_name test_$SEED > $LOG_FILE 2>&1
    
    # Check if the test completed successfully by looking for the mailbox success print
    if grep -q "REGRESSION_TEST_SUCCESS" $LOG_FILE; then
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
