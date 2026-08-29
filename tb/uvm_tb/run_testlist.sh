#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: run_testlist.sh
# Description:
#   Compile the UVM testbench once, then run a directed test list with fixed
#   seeds. This is the Phase 2 gate for deterministic signoff checks.
# ==============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/uvm/directed"}
TESTLIST=${TESTLIST:-"${SCRIPT_DIR}/phase2_directed_tests.txt"}
ENABLE_COV=${ENABLE_COV:-0}
VCS_JOBS=${VCS_JOBS:-1}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

if [ -z "${FW_HEX:-}" ]; then
    echo "ERROR: FW_HEX must point to the firmware hex artifact."
    exit 1
fi

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

if [ ! -f "$TESTLIST" ]; then
    echo "ERROR: TESTLIST does not exist: $TESTLIST"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
TESTLIST_ABS=$(realpath "$TESTLIST")
FLASH_IMAGE_ABS=""
if [ -n "${FLASH_IMAGE:-}" ]; then
    if [ ! -f "$FLASH_IMAGE" ]; then
        echo "ERROR: FLASH_IMAGE does not exist: $FLASH_IMAGE"
        exit 1
    fi
    FLASH_IMAGE_ABS=$(realpath "$FLASH_IMAGE")
fi
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"
SUMMARY_FILE=directed_summary.txt
rm -rf test_logs
mkdir -p test_logs
: > "$SUMMARY_FILE"

echo "Firmware: $FW_HEX_ABS"
echo "Firmware SHA256: $(sha256sum "$FW_HEX_ABS" | awk '{print $1}')"
if [ -n "$FLASH_IMAGE_ABS" ]; then
    echo "Flash image: $FLASH_IMAGE_ABS"
    echo "Flash image SHA256: $(sha256sum "$FLASH_IMAGE_ABS" | awk '{print $1}')"
fi
echo "Testlist: $TESTLIST_ABS"
echo "Run directory: $RUN_DIR"
echo "Coverage enabled: $ENABLE_COV"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

if ! [[ "${VCS_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: VCS_JOBS must be a positive integer: ${VCS_JOBS}" >&2
    exit 1
fi
if [[ ! -x "${EDA_RUNNER}" ]]; then
    echo "ERROR: EDA runner is not executable: ${EDA_RUNNER}" >&2
    exit 1
fi

compile_cov_args=()
run_cov_args=()
if [ "$ENABLE_COV" = "1" ]; then
    rm -rf directed.vdb urgReport urg.log simv simv.daidir csrc
    compile_cov_args=(-cm line+cond+fsm+tgl+branch -cm_dir directed.vdb -cm_hier "${SCRIPT_DIR}/cov.cfg")
    run_cov_args=(-cm line+cond+fsm+tgl+branch -cm_dir directed.vdb)
fi

# Opt-in L2 write-back selection (default = reset-safe write-through).
l2_define_args=()
if [ "${L2_WRITEBACK:-0}" = "1" ]; then
    l2_define_args=(+define+SOC_L2_WRITEBACK)
    echo "L2 policy: write-back (SOC_L2_WRITEBACK)"
else
    echo "L2 policy: write-through (default)"
fi

echo "Compiling UVM testbench with VCS..."
"${EDA_RUNNER}" vcs -j"${VCS_JOBS}" -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
    "${compile_cov_args[@]}" "${l2_define_args[@]}" \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips +incdir+"${ROOT_DIR}"/rtl/cache \
    +incdir+"${SCRIPT_DIR}"/agents +incdir+"${SCRIPT_DIR}"/env +incdir+"${SCRIPT_DIR}"/tests +incdir+"${SCRIPT_DIR}"/seqs +incdir+"${SCRIPT_DIR}"/checkers +incdir+"${SCRIPT_DIR}"/tb_top \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_top/soc_verif_top.sv "${SCRIPT_DIR}"/tb_top/tb_top.sv \
    -l vcs_testlist_compile.log

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

log_summary() {
    echo "$*" | tee -a "$SUMMARY_FILE"
}

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
        [ "${uvm_errors:-1}" = "0" ] && [ "${uvm_fatals:-1}" = "0" ]
        if [ "$?" -ne 0 ]; then
            return 1
        fi
    fi

    if grep -Eq '^(Error:|Error-\[|Fatal:|Fatal-\[)' "$log_file"; then
        return 1
    fi

    if grep -Eq '^UVM_(ERROR|FATAL)[[:space:]]+(@|/)' "$log_file"; then
        return 1
    fi

    if [ -n "$uvm_errors" ] || [ -n "$uvm_fatals" ]; then
        return 0
    fi

    if grep -q "REGRESSION_TEST_SUCCESS" "$log_file"; then
        return 0
    fi

    return 1
}

log_summary "======================================================================"
log_summary " Starting Directed Testlist"
log_summary "======================================================================"

FW_ROOT_DIR=${FW_ROOT_DIR:-"${ROOT_DIR}/build/firmware"}

# Testlist entry format (whitespace-separated):
#   <test_name> [seed] [fw_variant]
# fw_variant is optional; when present, firmware hex is looked up at
# $FW_ROOT_DIR/<fw_variant>/firmware.hex. When absent, the caller-supplied
# $FW_HEX is used (backward-compatible).
while read -r test_name seed fw_variant _; do
    if [ -z "${test_name:-}" ] || [[ "$test_name" == \#* ]]; then
        continue
    fi

    seed=${seed:-1}
    if [ -n "${fw_variant:-}" ] && [[ "$fw_variant" != \#* ]]; then
        test_fw_hex="${FW_ROOT_DIR}/${fw_variant}/firmware.hex"
        if [ ! -f "$test_fw_hex" ]; then
            echo "ERROR: firmware for variant '${fw_variant}' not built: $test_fw_hex" >&2
            echo "       run: make -C tb/soc_test/fw all-firmwares OUT_DIR=${FW_ROOT_DIR}" >&2
            exit 1
        fi
        test_fw_hex_abs=$(realpath "$test_fw_hex")
    else
        test_fw_hex_abs=$FW_HEX_ABS
        fw_variant=default
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    log_file="test_logs/${TOTAL_COUNT}_${test_name}_seed_${seed}.log"

    printf "Running %s seed=%s fw=%s... " "$test_name" "$seed" "$fw_variant"

    set +e
    sim_args=(+UVM_TESTNAME="$test_name" +ntb_random_seed="$seed" +FW_HEX="$test_fw_hex_abs")
    if [ -n "$FLASH_IMAGE_ABS" ]; then
        sim_args+=(+FLASH_IMAGE="$FLASH_IMAGE_ABS")
    fi
    if [ "$ENABLE_COV" = "1" ]; then
        "${EDA_RUNNER}" ./simv "${sim_args[@]}" "${run_cov_args[@]}" -cm_name "${test_name}_${seed}" > "$log_file" 2>&1
    else
        "${EDA_RUNNER}" ./simv "${sim_args[@]}" > "$log_file" 2>&1
    fi
    sim_status=$?
    set -e

    if check_log_pass "$log_file" "$sim_status"; then
        echo "PASS"
        log_summary "${test_name} seed=${seed} fw=${fw_variant} PASS log=${log_file}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL (status=$sim_status log=$log_file)"
        log_summary "${test_name} seed=${seed} fw=${fw_variant} FAIL status=${sim_status} log=${log_file}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$TESTLIST_ABS"

log_summary "======================================================================"
log_summary " Directed Testlist Results:"
log_summary " Total:  $TOTAL_COUNT"
log_summary " Passed: $PASS_COUNT"
log_summary " Failed: $FAIL_COUNT"
log_summary "======================================================================"

if [ "$ENABLE_COV" = "1" ]; then
    log_summary "======================================================================"
    log_summary " Generating Coverage Report"
    log_summary "======================================================================"

    set +e
    "${EDA_RUNNER}" urg -dir directed.vdb -format both -report urgReport -log urg.log
    urg_status=$?
    set -e

    if [ "$urg_status" -eq 0 ] && [ -f urgReport/dashboard.txt ]; then
        log_summary "Coverage report: ${RUN_DIR}/urgReport"
        sed -n '1,36p' urgReport/dashboard.txt | tee -a "$SUMMARY_FILE"
    else
        log_summary "ERROR: COVERAGE REPORT GENERATION FAILED status=${urg_status} log=urg.log"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_summary "SUCCESS: DIRECTED TESTLIST PASSED"
    exit 0
fi

log_summary "ERROR: DIRECTED TESTLIST FAILED"
exit 1
