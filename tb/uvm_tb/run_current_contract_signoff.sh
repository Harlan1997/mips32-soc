#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: run_current_contract_signoff.sh
# Description: Unified entry point for current RTL contract full-chip sign-off.
# ==============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)

SIGNOFF_BASE_DIR=$(realpath -m "${ROOT_DIR}/build/signoff")
RUN_ROOT_INPUT=${RUN_ROOT:-"${SIGNOFF_BASE_DIR}/current_contract"}
CANON_RUN_ROOT=$(realpath -m "${RUN_ROOT_INPUT}")
ALLOW_EXTERNAL_RUN_ROOT=${ALLOW_EXTERNAL_RUN_ROOT:-0}

# Validate RUN_ROOT path safely. External roots are accepted only when the
# caller explicitly opts in, so the default invocation remains constrained to
# the repository build tree while large signoff runs can use a dedicated
# scratch filesystem.
if [[ "${ALLOW_EXTERNAL_RUN_ROOT}" != "1" && \
      ( "${CANON_RUN_ROOT}" != "${SIGNOFF_BASE_DIR}/"* ||
        "${CANON_RUN_ROOT}" == "${SIGNOFF_BASE_DIR}" ) ]]; then
    echo "ERROR: RUN_ROOT must be a child directory of ${SIGNOFF_BASE_DIR}, got: ${RUN_ROOT_INPUT} (canonical: ${CANON_RUN_ROOT})"
    exit 1
fi
RUN_ROOT="${CANON_RUN_ROOT}"

FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}
FLASH_IMAGE=${FLASH_IMAGE:-"${SCRIPT_DIR}/data/flash_xip_image.hex"}
SEED_BASE=${SEED_BASE:-1}
NUM_TESTS=${NUM_TESTS:-10}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

# Validate numerical inputs
if ! [[ "$NUM_TESTS" =~ ^[0-9]+$ ]] || [ "$NUM_TESTS" -lt 10 ]; then
    echo "ERROR: NUM_TESTS must be an integer >= 10, got: $NUM_TESTS"
    exit 1
fi

if ! [[ "$SEED_BASE" =~ ^[0-9]+$ ]]; then
    echo "ERROR: SEED_BASE must be a non-negative integer, got: $SEED_BASE"
    exit 1
fi

# Default UVM code coverage thresholds (%) - 99% across all 6 metrics
MIN_UVM_SCORE=${MIN_UVM_SCORE:-99.00}
MIN_UVM_LINE=${MIN_UVM_LINE:-99.00}
MIN_UVM_COND=${MIN_UVM_COND:-99.00}
MIN_UVM_TOGGLE=${MIN_UVM_TOGGLE:-99.00}
MIN_UVM_FSM=${MIN_UVM_FSM:-99.00}
MIN_UVM_BRANCH=${MIN_UVM_BRANCH:-99.00}

# Default Product-top CPU/CP0 code coverage thresholds (%) - 99% across all 6 metrics
MIN_PRODUCT_SCORE=${MIN_PRODUCT_SCORE:-99.00}
MIN_PRODUCT_LINE=${MIN_PRODUCT_LINE:-99.00}
MIN_PRODUCT_COND=${MIN_PRODUCT_COND:-99.00}
MIN_PRODUCT_TOGGLE=${MIN_PRODUCT_TOGGLE:-99.00}
MIN_PRODUCT_FSM=${MIN_PRODUCT_FSM:-99.00}
MIN_PRODUCT_BRANCH=${MIN_PRODUCT_BRANCH:-99.00}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

if [[ ! -x "${EDA_RUNNER}" ]]; then
    echo "ERROR: EDA runner is not executable: ${EDA_RUNNER}" >&2
    exit 1
fi

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

if [ ! -f "$FLASH_IMAGE" ]; then
    echo "ERROR: FLASH_IMAGE does not exist: $FLASH_IMAGE"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
FLASH_IMAGE_ABS=$(realpath "$FLASH_IMAGE")

# Clean stale output directory safely using --
rm -rf -- "$RUN_ROOT"
mkdir -p -- "$RUN_ROOT"

REPORT="${RUN_ROOT}/current_contract_signoff_report.md"

fail_signoff() {
    local stage=$1
    local msg=$2
    echo "======================================================================"
    echo " SIGNOFF FAILURE AT STAGE: $stage"
    echo " Message: $msg"
    echo "======================================================================"
    {
        echo "# Current RTL Contract Full-Chip Sign-off Report"
        echo
        echo "- **Overall Status**: **FAIL**"
        echo "- **Failed Stage**: \`$stage\`"
        echo "- **Error Detail**: $msg"
        echo "- **Timestamp**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "- **Host**: $(hostname)"
        echo
        echo "## Scope Limitation"
        echo "- Current scope: RTL implementation, frontend compile/elaboration, and functional simulation verification."
        echo "- Remaining scope outside this sign-off: full ISA/MMU/Linux/QEMU differential, Linux VM ownership and multicore shootdown, complete FPU/IEEE-754/ABI semantics, real QSPI/DDR device timing and PHY training, synthesis/STA/DFT/formal/CDC/RDC."
        echo "- Scope claim: strictly limited to the current documented RTL contract. This is not synthesis, backend, production, or tapeout sign-off."
    } > "$REPORT"
    exit 1
}

PHASE2_ROOT="${RUN_ROOT}/phase2_complete"
PHASE3_ROOT="${RUN_ROOT}/phase3_complete"
PHASE3B_ROOT="${RUN_ROOT}/phase3b_complete"
PHASE3C_ROOT="${RUN_ROOT}/phase3c_complete"
STRESS_ROOT="${RUN_ROOT}/stress_regression"

echo "======================================================================"
echo " Starting Current RTL Contract Full-Chip Sign-off"
echo " Run root: $RUN_ROOT"
echo "======================================================================"

echo "[Stage 1/5] Running Phase 2 Complete Gate..."
set +e
FW_HEX="$FW_HEX_ABS" FW_ROOT_DIR="${FW_ROOT_DIR:-}" RUN_ROOT="$PHASE2_ROOT" "${SCRIPT_DIR}/run_phase2_complete.sh"
p2_status=$?
set -e
if [ "$p2_status" -ne 0 ]; then
    fail_signoff "PHASE2_GATE" "Phase 2 completion gate failed (status=$p2_status)"
fi

echo "[Stage 2/5] Running Phase 3A Complete Gate..."
set +e
# Phase 3A coverage is part of signoff, including the product CPU/CP0 VDB.
# Keep a caller's no-coverage diagnostic setting from suppressing that input.
SKIP_COVERAGE=0 FW_HEX="$FW_HEX_ABS" FW_ROOT_DIR="${FW_ROOT_DIR:-}" FLASH_IMAGE="$FLASH_IMAGE_ABS" RUN_ROOT="$PHASE3_ROOT" CPU_CP0_DIR="${PHASE3_ROOT}/cpu_cp0_gate" "${SCRIPT_DIR}/run_phase3_complete.sh"
p3a_status=$?
set -e
if [ "$p3a_status" -ne 0 ]; then
    fail_signoff "PHASE3A_GATE" "Phase 3A completion gate failed (status=$p3a_status)"
fi

echo "[Stage 3/5] Running Phase 3B Complete Gate..."
set +e
FW_HEX="$FW_HEX_ABS" RUN_ROOT="$PHASE3B_ROOT" "${SCRIPT_DIR}/run_phase3b_complete.sh"
p3b_status=$?
set -e
if [ "$p3b_status" -ne 0 ]; then
    fail_signoff "PHASE3B_GATE" "Phase 3B completion gate failed (status=$p3b_status)"
fi

echo "[Stage 4/5] Running Phase 3C Complete Gate..."
set +e
FW_HEX="$FW_HEX_ABS" RUN_ROOT="$PHASE3C_ROOT" "${SCRIPT_DIR}/run_phase3c_complete.sh"
p3c_status=$?
set -e
if [ "$p3c_status" -ne 0 ]; then
    fail_signoff "PHASE3C_GATE" "Phase 3C completion gate failed (status=$p3c_status)"
fi

echo "[Stage 5/5] Running Multi-Seed UVM Stress Regression..."
set +e
FW_HEX="$FW_HEX_ABS" SEED_BASE="$SEED_BASE" NUM_TESTS="$NUM_TESTS" RUN_DIR="$STRESS_ROOT" "${SCRIPT_DIR}/run_regression.sh"
stress_status=$?
set -e
if [ "$stress_status" -ne 0 ]; then
    fail_signoff "STRESS_REGRESSION" "Multi-seed stress regression failed (status=$stress_status)"
fi

echo "======================================================================"
echo " Merging UVM Coverage Databases"
echo "======================================================================"
MERGED_COV_DIR="${RUN_ROOT}/coverage"
mkdir -p -- "$MERGED_COV_DIR"

set +e
# Generate raw report first without exclusions
"${EDA_RUNNER}" urg -dir "${PHASE2_ROOT}/directed_cov/directed.vdb" \
        "${PHASE3_ROOT}/directed_cov/directed.vdb" \
        "${PHASE3B_ROOT}/directed_cov/directed.vdb" \
        "${PHASE3C_ROOT}/directed_cov/directed.vdb" \
        "${STRESS_ROOT}/regression.vdb" \
    -dbname "${MERGED_COV_DIR}/merged.vdb" \
    -format both \
    -report "${MERGED_COV_DIR}/raw_urgReport" \
    -log "${MERGED_COV_DIR}/urg_raw.log"

# Refine exclusions directly from fresh VDBs
python3 "${ROOT_DIR}/tb/coverage/refine_exclusions.py" "${MERGED_COV_DIR}/merged.vdb" "${PHASE3_ROOT}/cpu_cp0_gate/simv.vdb"

# URG requires one strict exclusion file per metric when a merged VDB contains
# multiple elaboration/configuration variants.  Generate these files directly
# from the fresh VDBs so checksums and object sets cannot become stale.
UVM_STRICT_ELFILELIST=$(python3 "${ROOT_DIR}/tb/coverage/dump_strict_exclusions.py" \
    "${MERGED_COV_DIR}/merged.vdb" "${MERGED_COV_DIR}/strict_exclusions" uvm)
PRODUCT_STRICT_ELFILELIST=$(python3 "${ROOT_DIR}/tb/coverage/dump_strict_exclusions.py" \
    "${PHASE3_ROOT}/cpu_cp0_gate/simv.vdb" "${PHASE3_ROOT}/cpu_cp0_gate/strict_exclusions" product)

# Refresh Product textReportFinal using fresh strict per-metric exclusions
"${EDA_RUNNER}" urg -dir "${PHASE3_ROOT}/cpu_cp0_gate/simv.vdb" \
    -elfilelist "${PRODUCT_STRICT_ELFILELIST}" \
    -excl_strict \
    -format text \
    -report "${PHASE3_ROOT}/cpu_cp0_gate/textReportFinal" \
    -log "${PHASE3_ROOT}/cpu_cp0_gate/urg_final.log"

# Generate final adjusted report with strict exclusions
"${EDA_RUNNER}" urg -dir "${MERGED_COV_DIR}/merged.vdb" \
    -elfilelist "${UVM_STRICT_ELFILELIST}" \
    -excl_strict \
    -format both \
    -report "${MERGED_COV_DIR}/urgReport" \
    -log "${MERGED_COV_DIR}/urg.log"
urg_status=$?
set -e

if [ "$urg_status" -ne 0 ] || [ ! -d "${MERGED_COV_DIR}/merged.vdb" ] || \
   [ ! -s "${MERGED_COV_DIR}/urgReport/dashboard.txt" ] || [ ! -s "${MERGED_COV_DIR}/urgReport/groups.txt" ] || \
   [ ! -s "${MERGED_COV_DIR}/urgReport/dashboard.html" ] || [ ! -s "${MERGED_COV_DIR}/urgReport/groups.html" ]; then
    fail_signoff "COVERAGE_MERGE" "URG coverage merge or report generation failed (urg_status=$urg_status)"
fi

# Verify all 15 required functional coverage groups
required_groups=(
    'soc_bus_coverage::bus_contract_cg'
    'soc_jtag_reset_recovery_test::jtag_reset_event_cg'
    'soc_jtag_reset_recovery_test::jtag_recovery_pulse_cg'
    'axi_timer_irq_seq::timer_irq_event_cg'
    'axi_timer_irq_seq::timer_irq_latency_cg'
    'axi_pic_combined_irq_seq::pic_combined_irq_event_cg'
    'axi_pic_combined_irq_seq::pic_combined_irq_state_cg'
    'axi_apb_burst_stress_seq::apb_burst_stress_cg'
    'axi_uart_irq_seq::uart_irq_event_cg'
    'axi_apb_fault_stress_seq::apb_fault_stress_cg'
    'axi_flash_image_seq::flash_image_cg'
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_event_cg'
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_count_cg'
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_event_cg'
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_active_cg'
)

for group_name in "${required_groups[@]}"; do
    if ! grep -Eq "100\\.00[[:space:]]+100\\.00.*${group_name}" "${MERGED_COV_DIR}/urgReport/groups.txt"; then
        fail_signoff "FUNCTIONAL_COVERAGE" "Required functional coverage group is not 100%: ${group_name}"
    fi
done

# Perform coverage threshold checks & metrics parsing via Python
set +e
python3 - << 'PYEOF' "$MERGED_COV_DIR/urgReport/dashboard.txt" "${PHASE3_ROOT}/cpu_cp0_gate/textReportFinal/dashboard.txt" \
  "$MIN_UVM_SCORE" "$MIN_UVM_LINE" "$MIN_UVM_COND" "$MIN_UVM_TOGGLE" "$MIN_UVM_FSM" "$MIN_UVM_BRANCH" \
  "$MIN_PRODUCT_SCORE" "$MIN_PRODUCT_LINE" "$MIN_PRODUCT_COND" "$MIN_PRODUCT_TOGGLE" "$MIN_PRODUCT_FSM" "$MIN_PRODUCT_BRANCH" \
  "$RUN_ROOT/coverage_summary.json"
import sys, json
from decimal import Decimal

uvm_dash, prod_dash = sys.argv[1], sys.argv[2]
uvm_thresh = {
    'SCORE': Decimal(sys.argv[3]), 'LINE': Decimal(sys.argv[4]), 'COND': Decimal(sys.argv[5]),
    'TOGGLE': Decimal(sys.argv[6]), 'FSM': Decimal(sys.argv[7]), 'BRANCH': Decimal(sys.argv[8])
}
prod_thresh = {
    'SCORE': Decimal(sys.argv[9]), 'LINE': Decimal(sys.argv[10]), 'COND': Decimal(sys.argv[11]),
    'TOGGLE': Decimal(sys.argv[12]), 'FSM': Decimal(sys.argv[13]), 'BRANCH': Decimal(sys.argv[14])
}
out_json = sys.argv[15]

def parse_dashboard(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    headers, values = [], []
    in_mod_def = False
    for i, line in enumerate(lines):
        if 'Total Module Definition Coverage Summary' in line:
            in_mod_def = True
            for j in range(i + 1, min(i + 5, len(lines))):
                if 'SCORE' in lines[j]:
                    headers = lines[j].split()
                    values = lines[j + 1].split()
                    break
            break
    if not in_mod_def or not headers or not values:
        for i, line in enumerate(lines):
            if 'Total Coverage Summary' in line:
                for j in range(i + 1, min(i + 5, len(lines))):
                    if 'SCORE' in lines[j]:
                        headers = lines[j].split()
                        values = lines[j + 1].split()
                        break
                break
    metrics = {}
    for h, v in zip(headers, values):
        try:
            metrics[h.upper()] = Decimal(v)
        except Exception:
            pass
    return metrics

uvm_metrics = parse_dashboard(uvm_dash)
prod_metrics = parse_dashboard(prod_dash)

errors = []
uvm_results = {}
for m, th in uvm_thresh.items():
    act = uvm_metrics.get(m, Decimal('0.0'))
    passed = act >= th
    uvm_results[m] = {'actual': str(act), 'threshold': str(th), 'pass': passed}
    if not passed:
        errors.append(f"UVM merged {m}: actual {act}% < threshold {th}%")

prod_results = {}
for m, th in prod_thresh.items():
    act = prod_metrics.get(m, Decimal('0.0'))
    passed = act >= th
    prod_results[m] = {'actual': str(act), 'threshold': str(th), 'pass': passed}
    if not passed:
        errors.append(f"Product CPU/CP0 {m}: actual {act}% < threshold {th}%")

summary = {
    'uvm': uvm_results,
    'product': prod_results,
    'passed': len(errors) == 0,
    'errors': errors
}

with open(out_json, 'w') as f:
    json.dump(summary, f, indent=2)

if errors:
    print("COVERAGE THRESHOLD ERROR:", "; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

cov_status=$?
set -e
if [ "$cov_status" -ne 0 ]; then
    fail_signoff "COVERAGE_THRESHOLDS" "Code coverage did not meet required thresholds"
fi

# Log scan
ERROR_RE='^(Error:|Error-\[|Fatal:|Fatal-\[)|^UVM_(ERROR|FATAL)[[:space:]]+(@|/)|fabric_axim|Cannot connect to the license server|COVERAGE REPORT GENERATION FAILED|DIRECTED TESTLIST FAILED'
scan_file="${RUN_ROOT}/project_error_scan.txt"
scan_tmp="${RUN_ROOT}/project_error_scan.txt.tmp"
scan_err="${RUN_ROOT}/project_error_scan_err.txt"

if command -v rg >/dev/null 2>&1; then
    set +e
    rg -n "$ERROR_RE" "$RUN_ROOT" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
else
    set +e
    grep -RInE --exclude-dir=csrc --exclude-dir=simv.daidir --exclude-dir=urgReport --exclude="*.vdb" --exclude="*.so" --exclude="*.o" "$ERROR_RE" "$RUN_ROOT" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
fi

if [ "$scan_status" -eq 0 ]; then
    mv "$scan_tmp" "$scan_file"
    fail_signoff "LOG_ERROR_SCAN" "Sign-off error scan found failures. See $scan_file"
elif [ "$scan_status" -eq 1 ]; then
    : > "$scan_file"
    rm -f "$scan_tmp" "$scan_err"
else
    rm -f "$scan_tmp"
    fail_signoff "LOG_ERROR_SCAN" "Log scan command failed"
fi

# Collect provenance
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
VCS_VER=$(vcs -ID 2>&1 | grep -i 'Compiler version' | head -n 1 || echo "unknown")
URG_VER=$(urg -version 2>&1 | grep -E '^URG [Vv]ersion' | head -n 1 || echo "unknown")
FW_SHA=$(sha256sum "$FW_HEX_ABS" | awk '{print $1}')
FLASH_SHA=$(sha256sum "$FLASH_IMAGE_ABS" | awk '{print $1}')
DATE_STR=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
HOST_STR=$(hostname)

## Extract and validate subordinate counts
validate_decimal_int() {
    local val=$1
    local name=$2
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        fail_signoff "REGRESSION_CARDINALITY" "Malformed summary count for ${name}: '${val}' (expected non-negative integer)"
    fi
}

extract_single_val() {
    local summary_file=$1
    local pattern=$2
    local field_num=$3

    if [ ! -f "$summary_file" ]; then
        echo "INVALID_FILE"
        return
    fi

    local raw_matches
    raw_matches=$(awk -v f="$field_num" "$pattern {if (\$f != \"\") print \$f}" "$summary_file")
    if [ -z "$raw_matches" ]; then
        echo "MISSING_MATCH"
        return
    fi

    local match_count
    match_count=$(echo "$raw_matches" | wc -l)
    if [ "$match_count" -eq 1 ]; then
        echo "$raw_matches"
    else
        echo "MULTIPLE_MATCHES"
    fi
}

extract_summary_counts() {
    local summary_file=$1
    local tot pass fail
    tot=$(extract_single_val "$summary_file" '/[[:space:]]Total:/' 2)
    pass=$(extract_single_val "$summary_file" '/[[:space:]]Passed:/' 2)
    fail=$(extract_single_val "$summary_file" '/[[:space:]]Failed:/' 2)
    echo "${tot} ${pass} ${fail}"
}

extract_stress_counts() {
    local summary_file=$1
    local tot pass fail
    tot=$(extract_single_val "$summary_file" '/Total Tests:/' 3)
    pass=$(extract_single_val "$summary_file" '/[[:space:]]Passed:/' 2)
    fail=$(extract_single_val "$summary_file" '/[[:space:]]Failed:/' 2)
    echo "${tot} ${pass} ${fail}"
}

read p2_dir_tot p2_dir_pass p2_dir_fail <<< "$(extract_summary_counts "${PHASE2_ROOT}/directed/directed_summary.txt")"
read p2_cov_tot p2_cov_pass p2_cov_fail <<< "$(extract_summary_counts "${PHASE2_ROOT}/directed_cov/directed_summary.txt")"

read p3a_dir_tot p3a_dir_pass p3a_dir_fail <<< "$(extract_summary_counts "${PHASE3_ROOT}/directed/directed_summary.txt")"
read p3a_cov_tot p3a_cov_pass p3a_cov_fail <<< "$(extract_summary_counts "${PHASE3_ROOT}/directed_cov/directed_summary.txt")"

read p3b_dir_tot p3b_dir_pass p3b_dir_fail <<< "$(extract_summary_counts "${PHASE3B_ROOT}/directed/directed_summary.txt")"
read p3b_cov_tot p3b_cov_pass p3b_cov_fail <<< "$(extract_summary_counts "${PHASE3B_ROOT}/directed_cov/directed_summary.txt")"

read p3c_dir_tot p3c_dir_pass p3c_dir_fail <<< "$(extract_summary_counts "${PHASE3C_ROOT}/directed/directed_summary.txt")"
read p3c_cov_tot p3c_cov_pass p3c_cov_fail <<< "$(extract_summary_counts "${PHASE3C_ROOT}/directed_cov/directed_summary.txt")"

read stress_tot stress_pass stress_fail <<< "$(extract_stress_counts "${STRESS_ROOT}/regression_summary.txt")"

if [ -f "${PHASE3_ROOT}/cpu_cp0_gate/cpu_cp0_summary.txt" ] && grep -q 'Status: PASS' "${PHASE3_ROOT}/cpu_cp0_gate/cpu_cp0_summary.txt"; then
    cpu_cp0_tot=1
    cpu_cp0_pass=1
    cpu_cp0_fail=0
else
    cpu_cp0_tot=0
    cpu_cp0_pass=0
    cpu_cp0_fail=1
fi

validate_decimal_int "$p2_dir_tot" "p2_dir_tot"
validate_decimal_int "$p2_dir_pass" "p2_dir_pass"
validate_decimal_int "$p2_dir_fail" "p2_dir_fail"
validate_decimal_int "$p2_cov_tot" "p2_cov_tot"
validate_decimal_int "$p2_cov_pass" "p2_cov_pass"
validate_decimal_int "$p2_cov_fail" "p2_cov_fail"

validate_decimal_int "$p3a_dir_tot" "p3a_dir_tot"
validate_decimal_int "$p3a_dir_pass" "p3a_dir_pass"
validate_decimal_int "$p3a_dir_fail" "p3a_dir_fail"
validate_decimal_int "$p3a_cov_tot" "p3a_cov_tot"
validate_decimal_int "$p3a_cov_pass" "p3a_cov_pass"
validate_decimal_int "$p3a_cov_fail" "p3a_cov_fail"

validate_decimal_int "$p3b_dir_tot" "p3b_dir_tot"
validate_decimal_int "$p3b_dir_pass" "p3b_dir_pass"
validate_decimal_int "$p3b_dir_fail" "p3b_dir_fail"
validate_decimal_int "$p3b_cov_tot" "p3b_cov_tot"
validate_decimal_int "$p3b_cov_pass" "p3b_cov_pass"
validate_decimal_int "$p3b_cov_fail" "p3b_cov_fail"

validate_decimal_int "$p3c_dir_tot" "p3c_dir_tot"
validate_decimal_int "$p3c_dir_pass" "p3c_dir_pass"
validate_decimal_int "$p3c_dir_fail" "p3c_dir_fail"
validate_decimal_int "$p3c_cov_tot" "p3c_cov_tot"
validate_decimal_int "$p3c_cov_pass" "p3c_cov_pass"
validate_decimal_int "$p3c_cov_fail" "p3c_cov_fail"

validate_decimal_int "$cpu_cp0_tot" "cpu_cp0_tot"
validate_decimal_int "$cpu_cp0_pass" "cpu_cp0_pass"
validate_decimal_int "$cpu_cp0_fail" "cpu_cp0_fail"

validate_decimal_int "$stress_tot" "stress_tot"
validate_decimal_int "$stress_pass" "stress_pass"
validate_decimal_int "$stress_fail" "stress_fail"

# Gate cardinalities strictly
if [ "$p2_dir_tot" -ne 16 ] || [ "$p2_dir_pass" -ne 16 ] || [ "$p2_dir_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 2 directed gate cardinality mismatch: total=$p2_dir_tot (expected 16), passed=$p2_dir_pass (expected 16), failed=$p2_dir_fail (expected 0)"
fi
if [ "$p2_cov_tot" -ne 16 ] || [ "$p2_cov_pass" -ne 16 ] || [ "$p2_cov_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 2 coverage gate cardinality mismatch: total=$p2_cov_tot (expected 16), passed=$p2_cov_pass (expected 16), failed=$p2_cov_fail (expected 0)"
fi
if [ "$p3a_dir_tot" -ne 8 ] || [ "$p3a_dir_pass" -ne 8 ] || [ "$p3a_dir_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3A directed gate cardinality mismatch: total=$p3a_dir_tot (expected 8), passed=$p3a_dir_pass (expected 8), failed=$p3a_dir_fail (expected 0)"
fi
if [ "$p3a_cov_tot" -ne 8 ] || [ "$p3a_cov_pass" -ne 8 ] || [ "$p3a_cov_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3A coverage gate cardinality mismatch: total=$p3a_cov_tot (expected 8), passed=$p3a_cov_pass (expected 8), failed=$p3a_cov_fail (expected 0)"
fi
if [ "$p3b_dir_tot" -ne 1 ] || [ "$p3b_dir_pass" -ne 1 ] || [ "$p3b_dir_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3B directed gate cardinality mismatch: total=$p3b_dir_tot (expected 1), passed=$p3b_dir_pass (expected 1), failed=$p3b_dir_fail (expected 0)"
fi
if [ "$p3b_cov_tot" -ne 1 ] || [ "$p3b_cov_pass" -ne 1 ] || [ "$p3b_cov_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3B coverage gate cardinality mismatch: total=$p3b_cov_tot (expected 1), passed=$p3b_cov_pass (expected 1), failed=$p3b_cov_fail (expected 0)"
fi
if [ "$p3c_dir_tot" -ne 1 ] || [ "$p3c_dir_pass" -ne 1 ] || [ "$p3c_dir_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3C directed gate cardinality mismatch: total=$p3c_dir_tot (expected 1), passed=$p3c_dir_pass (expected 1), failed=$p3c_dir_fail (expected 0)"
fi
if [ "$p3c_cov_tot" -ne 1 ] || [ "$p3c_cov_pass" -ne 1 ] || [ "$p3c_cov_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Phase 3C coverage gate cardinality mismatch: total=$p3c_cov_tot (expected 1), passed=$p3c_cov_pass (expected 1), failed=$p3c_cov_fail (expected 0)"
fi
if [ "$cpu_cp0_tot" -ne 1 ] || [ "$cpu_cp0_pass" -ne 1 ] || [ "$cpu_cp0_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "CPU/CP0 firmware smoke gate failed or missing"
fi
if [ "$stress_tot" -ne "$NUM_TESTS" ] || [ "$stress_pass" -ne "$NUM_TESTS" ] || [ "$stress_fail" -ne 0 ]; then
    fail_signoff "REGRESSION_CARDINALITY" "Stress regression cardinality mismatch: total=$stress_tot (expected $NUM_TESTS), passed=$stress_pass (expected $NUM_TESTS), failed=$stress_fail (expected 0)"
fi

# Generate final report
set +e
python3 - << 'PYEOF' "$REPORT" "$DATE_STR" "$HOST_STR" "$VCS_VER" "$URG_VER" "$GIT_HEAD" "$GIT_DIRTY" \
  "$FW_HEX_ABS" "$FW_SHA" "$FLASH_IMAGE_ABS" "$FLASH_SHA" "$RUN_ROOT" "$SEED_BASE" "$NUM_TESTS" \
  "${SCRIPT_DIR}/phase2_directed_tests.txt" "${SCRIPT_DIR}/phase3_directed_tests.txt" \
  "${SCRIPT_DIR}/phase3b_directed_tests.txt" "${SCRIPT_DIR}/phase3c_directed_tests.txt" \
  "$p2_dir_tot" "$p2_dir_pass" "$p2_dir_fail" "$p2_cov_tot" "$p2_cov_pass" "$p2_cov_fail" \
  "$p3a_dir_tot" "$p3a_dir_pass" "$p3a_dir_fail" "$p3a_cov_tot" "$p3a_cov_pass" "$p3a_cov_fail" \
  "$p3b_dir_tot" "$p3b_dir_pass" "$p3b_dir_fail" "$p3b_cov_tot" "$p3b_cov_pass" "$p3b_cov_fail" \
  "$p3c_dir_tot" "$p3c_dir_pass" "$p3c_dir_fail" "$p3c_cov_tot" "$p3c_cov_pass" "$p3c_cov_fail" \
  "$cpu_cp0_tot" "$cpu_cp0_pass" "$cpu_cp0_fail" \
  "$stress_tot" "$stress_pass" "$stress_fail" "$RUN_ROOT/coverage_summary.json"
import sys, json
from decimal import Decimal

(
    report_path, date_str, host_str, vcs_ver, urg_ver, git_head, git_dirty,
    fw_path, fw_sha, flash_path, flash_sha, run_root, seed_base, num_tests,
    p2_tl, p3a_tl, p3b_tl, p3c_tl,
    p2_dir_tot, p2_dir_pass, p2_dir_fail, p2_cov_tot, p2_cov_pass, p2_cov_fail,
    p3a_dir_tot, p3a_dir_pass, p3a_dir_fail, p3a_cov_tot, p3a_cov_pass, p3a_cov_fail,
    p3b_dir_tot, p3b_dir_pass, p3b_dir_fail, p3b_cov_tot, p3b_cov_pass, p3b_cov_fail,
    p3c_dir_tot, p3c_dir_pass, p3c_dir_fail, p3c_cov_tot, p3c_cov_pass, p3c_cov_fail,
    cpu_cp0_tot, cpu_cp0_pass, cpu_cp0_fail,
    stress_tot, stress_pass, stress_fail, cov_json_path
) = sys.argv[1:]

with open(cov_json_path, 'r') as f:
    cov_data = json.load(f)

uvm_cov = cov_data['uvm']
prod_cov = cov_data['product']

dirty_str = f"dirty ({git_dirty} uncommitted files)" if int(git_dirty) > 0 else "clean"

lines = []
lines.append("# Current RTL Contract Full-Chip Sign-off Report")
lines.append("")
lines.append("## Executive Summary")
lines.append("")
lines.append("- **Overall Status**: **PASS for the current documented RTL contract**")
lines.append("- **Sign-off Scope**: RTL implementation and functional simulation of the current RTL contract (NOT synthesis, backend, production, or tapeout sign-off)")
lines.append(f"- **Execution Date**: `{date_str}`")
lines.append(f"- **Host**: `{host_str}`")
lines.append(f"- **Git HEAD**: `{git_head}` ({dirty_str})")
lines.append(f"- **VCS Version**: `{vcs_ver.strip()}`")
lines.append(f"- **URG Version**: `{urg_ver.strip()}`")
lines.append(f"- **Firmware Artifact**: `{fw_path}` (SHA256: `{fw_sha}`)")
lines.append(f"- **Flash Image Artifact**: `{flash_path}` (SHA256: `{flash_sha}`)")
lines.append(f"- **Output Root**: `{run_root}`")
lines.append(f"- **Stress Regression Parameters**: `SEED_BASE={seed_base}`, `NUM_TESTS={num_tests}` (Seeds: {seed_base}..{int(seed_base)+int(num_tests)-1})")
lines.append(f"- **Phase 2 Directed Testlist**: `{p2_tl}`")
lines.append(f"- **Phase 3A Directed Testlist**: `{p3a_tl}`")
lines.append(f"- **Phase 3B Directed Testlist**: `{p3b_tl}`")
lines.append(f"- **Phase 3C Directed Testlist**: `{p3c_tl}`")
lines.append("")
lines.append("## Mandatory Gate Results")
lines.append("")
lines.append("| Gate | Total Tests | Passed | Failed | Status | Report / Summary |")
lines.append("| --- | ---: | ---: | ---: | --- | --- |")
lines.append(f"| Phase 2 Directed | {p2_dir_tot} | {p2_dir_pass} | {p2_dir_fail} | PASS | `{run_root}/phase2_complete/phase2_completion_report.md` |")
lines.append(f"| Phase 2 Coverage | {p2_cov_tot} | {p2_cov_pass} | {p2_cov_fail} | PASS | `{run_root}/phase2_complete/phase2_completion_report.md` |")
lines.append(f"| Phase 3A Directed | {p3a_dir_tot} | {p3a_dir_pass} | {p3a_dir_fail} | PASS | `{run_root}/phase3_complete/phase3_completion_report.md` |")
lines.append(f"| Phase 3A Coverage | {p3a_cov_tot} | {p3a_cov_pass} | {p3a_cov_fail} | PASS | `{run_root}/phase3_complete/phase3_completion_report.md` |")
lines.append(f"| Phase 3A CPU/CP0 Smoke | {cpu_cp0_tot} | {cpu_cp0_pass} | {cpu_cp0_fail} | PASS | `{run_root}/phase3_complete/cpu_cp0_gate/cpu_cp0_summary.txt` |")
lines.append(f"| Phase 3B Directed | {p3b_dir_tot} | {p3b_dir_pass} | {p3b_dir_fail} | PASS | `{run_root}/phase3b_complete/phase3b_completion_report.md` |")
lines.append(f"| Phase 3B Coverage | {p3b_cov_tot} | {p3b_cov_pass} | {p3b_cov_fail} | PASS | `{run_root}/phase3b_complete/phase3b_completion_report.md` |")
lines.append(f"| Phase 3C Directed | {p3c_dir_tot} | {p3c_dir_pass} | {p3c_dir_fail} | PASS | `{run_root}/phase3c_complete/phase3c_completion_report.md` |")
lines.append(f"| Phase 3C Coverage | {p3c_cov_tot} | {p3c_cov_pass} | {p3c_cov_fail} | PASS | `{run_root}/phase3c_complete/phase3c_completion_report.md` |")
lines.append(f"| Multi-Seed UVM Stress | {stress_tot} | {stress_pass} | {stress_fail} | PASS | `{run_root}/stress_regression/regression_summary.txt` |")
lines.append("")
lines.append("## Merged UVM Code Coverage (Module Definition)")
lines.append("")
lines.append("Merged VDB: `" + run_root + "/coverage/merged.vdb`")
lines.append("URG Report: `" + run_root + "/coverage/urgReport`")
lines.append("")
lines.append("| Metric | Required Minimum | Actual Score | Result |")
lines.append("| --- | ---: | ---: | --- |")
for m in ['SCORE', 'LINE', 'COND', 'TOGGLE', 'FSM', 'BRANCH']:
    info = uvm_cov[m]
    res_str = "PASS" if info['pass'] else "FAIL"
    act_val = Decimal(info['actual'])
    th_val = Decimal(info['threshold'])
    lines.append(f"| {m.capitalize()} | {th_val:.2f}% | {act_val:.2f}% | {res_str} |")

lines.append("")
lines.append("## Product-Top CPU/CP0 Code Coverage (Module Definition)")
lines.append("")
lines.append("Report: `" + run_root + "/phase3_complete/cpu_cp0_gate/textReportFinal`")
lines.append("")
lines.append("| Metric | Required Minimum | Actual Score | Result |")
lines.append("| --- | ---: | ---: | --- |")
for m in ['SCORE', 'LINE', 'COND', 'TOGGLE', 'FSM', 'BRANCH']:
    info = prod_cov[m]
    res_str = "PASS" if info['pass'] else "FAIL"
    act_val = Decimal(info['actual'])
    th_val = Decimal(info['threshold'])
    lines.append(f"| {m.capitalize()} | {th_val:.2f}% | {act_val:.2f}% | {res_str} |")

lines.append("")
lines.append("## Required Functional Coverage Groups (15/15 Passed 100.00%)")
lines.append("")
lines.append("| Functional Coverage Group | Target | Actual | Status |")
lines.append("| --- | ---: | ---: | --- |")
req_groups = [
    'soc_bus_coverage::bus_contract_cg',
    'soc_jtag_reset_recovery_test::jtag_reset_event_cg',
    'soc_jtag_reset_recovery_test::jtag_recovery_pulse_cg',
    'axi_timer_irq_seq::timer_irq_event_cg',
    'axi_timer_irq_seq::timer_irq_latency_cg',
    'axi_pic_combined_irq_seq::pic_combined_irq_event_cg',
    'axi_pic_combined_irq_seq::pic_combined_irq_state_cg',
    'axi_apb_burst_stress_seq::apb_burst_stress_cg',
    'axi_uart_irq_seq::uart_irq_event_cg',
    'axi_apb_fault_stress_seq::apb_fault_stress_cg',
    'axi_flash_image_seq::flash_image_cg',
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_event_cg',
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_count_cg',
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_event_cg',
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_active_cg'
]
for g in req_groups:
    lines.append(f"| `{g}` | 100.00% | 100.00% | PASS |")

lines.append("")
lines.append("## Scope Boundary")
lines.append("")
lines.append("- The functional RTL contract gates, CPU/CP0 gate, and 10-seed stress regression passed.")
lines.append("- This report does not claim full MIPS32r2/FPU compliance, Linux boot, complete MMU/QEMU/RTL differential, real JEDEC QSPI/DDR behavior, or ASIC signoff.")
lines.append("- Coverage thresholds remain a genuine failure; exclusions are not used to conceal uncovered objects.")

lines.append("")
lines.append("## Log Error Scan")
lines.append("")
lines.append("- Error Scan Status: **CLEAN** (0 errors/fatals found)")
lines.append(f"- Error Scan Artifact: `{run_root}/project_error_scan.txt`")
lines.append("")
lines.append("## Explicit Scope Boundaries & Open Items")
lines.append("")
lines.append("This sign-off applies strictly to RTL implementation and functional simulation of the current documented RTL contract. The following domains remain explicitly OPEN and OUT OF SCOPE:")
lines.append("1. **Full RTL Multi-outstanding & Response Reordering**: Selected AXI ID/OOO slices are verified, but the default current contract still does not claim unrestricted system-wide concurrency.")
lines.append("2. **UART Production Boundary**: Behavioral RX/TX, FIFO/CTS and RX interrupt paths are integrated and gated; pin timing, analog electrical behavior and production driver policy remain outside scope.")
lines.append("3. **SPI-Serial Protocol Timing & Real Flash Boot**: Verification models loadable AXI flash-image behavior; JEDEC command timing, erase/program endurance and physical flash boot remain open.")
lines.append("4. **PIC Full-System Policy**: 32-source priority/mask/active/pending, deterministic arbitration and selected vector paths are gated; unrestricted nested/preemptive OS policy remains open.")
lines.append("5. **Static/Physical Design Claims**: No synthesis, STA, DFT, formal, lint, CDC, or RDC claims.")
lines.append("6. **Production Tapeout**: This flow is NOT tapeout sign-off.")

with open(report_path, 'w') as f:
    f.write("\n".join(lines) + "\n")

PYEOF
py_report_status=$?
set -e

if [ "$py_report_status" -ne 0 ] || [ ! -s "$REPORT" ]; then
    fail_signoff "REPORT_GENERATION" "Final signoff report generation failed or output report is missing/empty (status=$py_report_status)"
fi

echo "======================================================================"
echo " SUCCESS: CURRENT RTL CONTRACT FULL-CHIP SIGNOFF PASSED!"
echo " Report written to: $REPORT"
echo "======================================================================"
