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

SEED_BASE=${SEED_BASE:-1}

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

# Clean stale simulator, log, and coverage artifacts before run
rm -rf regression_logs regression.vdb urgReport urg.log simv simv.daidir csrc regression_summary.txt vcs_compile.log

echo "Firmware: $FW_HEX_ABS"
echo "Firmware SHA256: $(sha256sum "$FW_HEX_ABS" | awk '{print $1}')"
echo "UVM test: $TESTNAME"
echo "Seed base: $SEED_BASE"
echo "Run directory: $RUN_DIR"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

# Opt-in L2 write-back selection (default = reset-safe write-through).
l2_define_args=()
if [ "${L2_WRITEBACK:-0}" = "1" ]; then
    l2_define_args=(+define+SOC_L2_WRITEBACK)
    echo "L2 policy: write-back (SOC_L2_WRITEBACK)"
else
    echo "L2 policy: write-through (default)"
fi

echo "Compiling design..."
vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
    "${l2_define_args[@]}" \
    -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_hier "${SCRIPT_DIR}"/cov.cfg \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips +incdir+"${ROOT_DIR}"/rtl/cache \
    +incdir+"${SCRIPT_DIR}"/agents +incdir+"${SCRIPT_DIR}"/env +incdir+"${SCRIPT_DIR}"/tests +incdir+"${SCRIPT_DIR}"/seqs +incdir+"${SCRIPT_DIR}"/checkers +incdir+"${SCRIPT_DIR}"/tb_top \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_top/soc_verif_top.sv "${SCRIPT_DIR}"/tb_top/tb_top.sv \
    -l vcs_compile.log

FAIL_COUNT=0
PASS_COUNT=0
SUMMARY_FILE="regression_summary.txt"

check_log_pass() {
    local log_file=$1
    local sim_status=$2
    local uvm_errors
    local uvm_fatals

    if [ "$sim_status" -ne 0 ]; then
        return 1
    fi

    uvm_errors=$(awk '/UVM_ERROR[[:space:]]*:/ {value=$3} END {print value}' "$log_file")
    uvm_fatals=$(awk '/UVM_FATAL[[:space:]]*:/ {value=$3} END {print value}' "$log_file")

    if [ -n "$uvm_errors" ] || [ -n "$uvm_fatals" ]; then
        if [ "${uvm_errors:-1}" != "0" ] || [ "${uvm_fatals:-1}" != "0" ]; then
            return 1
        fi
    fi

    if grep -Eq '^(Error:|Error-\[|Fatal:|Fatal-\[)' "$log_file"; then
        return 1
    fi

    if grep -Eq '^UVM_(ERROR|FATAL)[[:space:]]+(@|/)' "$log_file"; then
        return 1
    fi

    if grep -q "REGRESSION_TEST_SUCCESS" "$log_file"; then
        return 0
    fi

    return 1
}

echo "======================================================================"
echo " Starting Large-Scale Regression Testing ($NUM_TESTS tests, seed_base=$SEED_BASE)"
echo "======================================================================"

mkdir -p regression_logs
: > "$SUMMARY_FILE"

for i in $(seq 1 $NUM_TESTS); do
    SEED=$((SEED_BASE + i - 1))
    LOG_FILE="regression_logs/test_${i}_seed_${SEED}.log"
    
    echo -n "Running Test $i/$NUM_TESTS with Seed $SEED... "
    
    set +e
    ./simv +UVM_TESTNAME="$TESTNAME" +ntb_random_seed="$SEED" +FW_HEX="$FW_HEX_ABS" \
        -cm line+cond+fsm+tgl+branch -cm_dir regression.vdb -cm_name "test_${i}_seed_${SEED}" > "$LOG_FILE" 2>&1
    sim_status=$?
    set -e
    
    if check_log_pass "$LOG_FILE" "$sim_status"; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "Test ${i}/${NUM_TESTS} | Seed: ${SEED} | Status: PASS | Log: ${LOG_FILE}" >> "$SUMMARY_FILE"
    else
        echo "FAIL (Check $LOG_FILE)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "Test ${i}/${NUM_TESTS} | Seed: ${SEED} | Status: FAIL (status=${sim_status}) | Log: ${LOG_FILE}" >> "$SUMMARY_FILE"
    fi
done

echo "======================================================================" | tee -a "$SUMMARY_FILE"
echo " Regression Results:" | tee -a "$SUMMARY_FILE"
echo " Total Tests: $NUM_TESTS" | tee -a "$SUMMARY_FILE"
echo " Passed:      $PASS_COUNT" | tee -a "$SUMMARY_FILE"
echo " Failed:      $FAIL_COUNT" | tee -a "$SUMMARY_FILE"
echo "======================================================================" | tee -a "$SUMMARY_FILE"

echo "======================================================================"
echo " Generating Coverage Report"
echo "======================================================================"

set +e
urg -dir regression.vdb -format both -report urgReport -log urg.log
urg_status=$?
set -e

if [ "$urg_status" -ne 0 ] || [ ! -s urgReport/dashboard.txt ] || [ ! -s urgReport/dashboard.html ]; then
    echo "ERROR: COVERAGE REPORT GENERATION FAILED status=${urg_status} log=urg.log"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [ $FAIL_COUNT -eq 0 ]; then
    echo "SUCCESS: ALL TESTS PASSED!"
    exit 0
else
    echo "ERROR: SOME TESTS FAILED!"
    exit 1
fi
