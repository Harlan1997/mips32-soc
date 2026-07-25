#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/uvm/phase3c_complete"}
TESTLIST=${TESTLIST:-"${SCRIPT_DIR}/phase3c_directed_tests.txt"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}

DIRECTED_DIR="${RUN_ROOT}/directed"
COV_DIR="${RUN_ROOT}/directed_cov"
REPORT="${RUN_ROOT}/phase3c_completion_report.md"

ERROR_RE='^(Error:|Error-\[|Fatal:|Fatal-\[)|^UVM_(ERROR|FATAL)[[:space:]]+(@|/)|fabric_axim|Cannot connect to the license server|COVERAGE REPORT GENERATION FAILED|DIRECTED TESTLIST FAILED'

required_groups=(
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_event_cg'
    'axi_pic_mask_arbitration_seq::pic_mask_arbitration_active_cg'
)

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

if [ ! -f "$TESTLIST" ]; then
    echo "ERROR: TESTLIST does not exist: $TESTLIST"
    exit 1
fi

mkdir -p "$RUN_ROOT"

echo "======================================================================"
echo " Phase 3C PIC Mask Arbitration Gate"
echo "======================================================================"
echo "Run root: $RUN_ROOT"
echo "Firmware: $FW_HEX"
echo "Testlist: $TESTLIST"

echo "======================================================================"
echo " Running Phase 3C no-coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" TESTLIST="$TESTLIST" RUN_DIR="$DIRECTED_DIR" ENABLE_COV=0 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Running Phase 3C coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" TESTLIST="$TESTLIST" RUN_DIR="$COV_DIR" ENABLE_COV=1 \
    "${SCRIPT_DIR}/run_testlist.sh"

scan_tmp="${RUN_ROOT}/phase3c_error_scan.txt.tmp"
if command -v rg >/dev/null 2>&1; then
    set +e
    rg -n "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" > "$scan_tmp"
    scan_status=$?
    set -e
else
    set +e
    grep -RInE "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" > "$scan_tmp"
    scan_status=$?
    set -e
fi

if [ "$scan_status" -eq 0 ]; then
    mv "$scan_tmp" "${RUN_ROOT}/phase3c_error_scan.txt"
    echo "ERROR: Phase 3C error scan found failures. See ${RUN_ROOT}/phase3c_error_scan.txt"
    exit 1
elif [ "$scan_status" -eq 1 ]; then
    : > "${RUN_ROOT}/phase3c_error_scan.txt"
    rm -f "$scan_tmp"
else
    rm -f "$scan_tmp"
    echo "ERROR: Phase 3C error scan failed"
    exit 1
fi

if [ ! -f "${COV_DIR}/urgReport/groups.txt" ]; then
    echo "ERROR: missing coverage group report: ${COV_DIR}/urgReport/groups.txt"
    exit 1
fi

for group_name in "${required_groups[@]}"; do
    if ! grep -Eq "100\\.00[[:space:]]+100\\.00.*${group_name}" "${COV_DIR}/urgReport/groups.txt"; then
        echo "ERROR: required coverage group is not 100%: ${group_name}"
        exit 1
    fi
done

directed_total=$(awk '/ Total:/ {value=$2} END {print value}' "${DIRECTED_DIR}/directed_summary.txt")
directed_passed=$(awk '/ Passed:/ {value=$2} END {print value}' "${DIRECTED_DIR}/directed_summary.txt")
directed_failed=$(awk '/ Failed:/ {value=$2} END {print value}' "${DIRECTED_DIR}/directed_summary.txt")
cov_total=$(awk '/ Total:/ {value=$2} END {print value}' "${COV_DIR}/directed_summary.txt")
cov_passed=$(awk '/ Passed:/ {value=$2} END {print value}' "${COV_DIR}/directed_summary.txt")
cov_failed=$(awk '/ Failed:/ {value=$2} END {print value}' "${COV_DIR}/directed_summary.txt")
coverage_line=$(awk '/^SCORE[[:space:]]+LINE[[:space:]]+COND/ {getline; print; exit}' "${COV_DIR}/directed_summary.txt")

{
    echo "# Phase 3C PIC Mask Arbitration Report"
    echo
    echo "- Status: COMPLETE for PIC multi-source mask arbitration coverage."
    echo "- Firmware: \`$FW_HEX\`"
    echo "- Testlist: \`$TESTLIST\`"
    echo "- No-coverage run: \`$DIRECTED_DIR\`"
    echo "- Coverage run: \`$COV_DIR\`"
    echo
    echo "## Regression Results"
    echo
    echo "| Gate | Total | Passed | Failed |"
    echo "| --- | ---: | ---: | ---: |"
    echo "| Phase 3C directed | ${directed_total:-unknown} | ${directed_passed:-unknown} | ${directed_failed:-unknown} |"
    echo "| Phase 3C coverage | ${cov_total:-unknown} | ${cov_passed:-unknown} | ${cov_failed:-unknown} |"
    echo
    echo "## Coverage Summary"
    echo
    echo "- Total coverage: \`${coverage_line:-unavailable}\`"
    echo "- Functional groups: all required Phase 3C PIC groups are 100.00%."
    echo
    echo "## Required Functional Groups"
    echo
    for group_name in "${required_groups[@]}"; do
        echo "- \`${group_name}\`: 100.00%"
    done
    echo
    echo "## Scope Boundary"
    echo
    echo "- This gate signs off PIC mask arbitration for UART, timer, and DMA pending sources."
    echo "- It does not claim priority encoding; current PIC RTL exposes only status, mask, active bits, and OR-reduced cpu_int."
    echo
    echo "## Log Scan"
    echo
    echo "- Error scan: clean"
    echo "- Scan output: \`${RUN_ROOT}/phase3c_error_scan.txt\`"
} > "$REPORT"

echo "SUCCESS: PHASE 3C PIC MASK ARBITRATION GATE PASSED"
echo "Report: $REPORT"
