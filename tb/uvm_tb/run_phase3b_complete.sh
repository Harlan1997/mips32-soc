#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/uvm/phase3b_complete"}
TESTLIST=${TESTLIST:-"${SCRIPT_DIR}/phase3b_directed_tests.txt"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}

DIRECTED_DIR="${RUN_ROOT}/directed"
COV_DIR="${RUN_ROOT}/directed_cov"
REPORT="${RUN_ROOT}/phase3b_completion_report.md"

ERROR_RE='^(Error:|Error-\[|Fatal:|Fatal-\[)|^UVM_(ERROR|FATAL)[[:space:]]+(@|/)|fabric_axim|Cannot connect to the license server|COVERAGE REPORT GENERATION FAILED|DIRECTED TESTLIST FAILED'

required_groups=(
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_event_cg'
    'soc_cpu_cp0_exception_test::cpu_cp0_exception_count_cg'
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
echo " Phase 3B CPU/CP0 UVM Coverage Gate"
echo "======================================================================"
echo "Run root: $RUN_ROOT"
echo "Firmware: $FW_HEX"
echo "Testlist: $TESTLIST"

echo "======================================================================"
echo " Running Phase 3B no-coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" FW_ROOT_DIR="${FW_ROOT_DIR:-}" TESTLIST="$TESTLIST" RUN_DIR="$DIRECTED_DIR" ENABLE_COV=0 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Running Phase 3B coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" FW_ROOT_DIR="${FW_ROOT_DIR:-}" TESTLIST="$TESTLIST" RUN_DIR="$COV_DIR" ENABLE_COV=1 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Scanning logs"
echo "======================================================================"
scan_tmp="${RUN_ROOT}/phase3b_error_scan.txt.tmp"
scan_err="${RUN_ROOT}/phase3b_error_scan_err.txt"
if command -v rg >/dev/null 2>&1; then
    set +e
    rg -n "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
else
    set +e
    grep -RInE --exclude-dir=csrc --exclude-dir=simv.daidir --exclude-dir=urgReport --exclude="*.so" --exclude="*.o" "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
fi

if [ "$scan_status" -eq 0 ]; then
    mv "$scan_tmp" "${RUN_ROOT}/phase3b_error_scan.txt"
    echo "ERROR: Phase 3B error scan found failures. See ${RUN_ROOT}/phase3b_error_scan.txt"
    [ -s "$scan_err" ] && cat "$scan_err"
    exit 1
elif [ "$scan_status" -eq 1 ]; then
    : > "${RUN_ROOT}/phase3b_error_scan.txt"
    rm -f "$scan_tmp" "$scan_err"
else
    rm -f "$scan_tmp"
    echo "ERROR: Phase 3B error scan failed:"
    [ -f "$scan_err" ] && cat "$scan_err"
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
    echo "# Phase 3B CPU/CP0 UVM Coverage Report"
    echo
    echo "- Status: COMPLETE for UVM-visible CPU exception-entry/return functional coverage."
    echo "- Firmware: \`$FW_HEX\`"
    echo "- Testlist: \`$TESTLIST\`"
    echo "- No-coverage run: \`$DIRECTED_DIR\`"
    echo "- Coverage run: \`$COV_DIR\`"
    echo
    echo "## Regression Results"
    echo
    echo "| Gate | Total | Passed | Failed |"
    echo "| --- | ---: | ---: | ---: |"
    echo "| Phase 3B directed | ${directed_total:-unknown} | ${directed_passed:-unknown} | ${directed_failed:-unknown} |"
    echo "| Phase 3B coverage | ${cov_total:-unknown} | ${cov_passed:-unknown} | ${cov_failed:-unknown} |"
    echo
    echo "## Coverage Summary"
    echo
    echo "- Total coverage: \`${coverage_line:-unavailable}\`"
    echo "- Functional groups: all required Phase 3B CPU/CP0 groups are 100.00%."
    echo
    echo "## Required Functional Groups"
    echo
    for group_name in "${required_groups[@]}"; do
        echo "- \`${group_name}\`: 100.00%"
    done
    echo
    echo "## Scope Boundary"
    echo
    echo "- This gate closes UVM-visible CPU/CP0 exception-entry/return coverage using the firmware exception path."
    echo "- RTL multi-outstanding fabric support and SPI-serial boot-from-flash remain separate open items."
    echo
    echo "## Log Scan"
    echo
    echo "- Error scan: clean"
    echo "- Scan output: \`${RUN_ROOT}/phase3b_error_scan.txt\`"
} > "$REPORT"

echo "SUCCESS: PHASE 3B CPU/CP0 UVM COVERAGE GATE PASSED"
echo "Report: $REPORT"
