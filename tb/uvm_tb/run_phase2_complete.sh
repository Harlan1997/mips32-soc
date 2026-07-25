#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/uvm/phase2_complete"}
TESTLIST=${TESTLIST:-"${SCRIPT_DIR}/phase2_directed_tests.txt"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}

DIRECTED_DIR="${RUN_ROOT}/directed"
COV_DIR="${RUN_ROOT}/directed_cov"
REPORT="${RUN_ROOT}/phase2_completion_report.md"

ERROR_RE='^(Error:|Error-\[|Fatal:|Fatal-\[)|^UVM_(ERROR|FATAL)[[:space:]]+(@|/)|fabric_axim|Cannot connect to the license server|COVERAGE REPORT GENERATION FAILED|DIRECTED TESTLIST FAILED'

required_groups=(
    'soc_bus_coverage::bus_contract_cg'
    'soc_jtag_reset_recovery_test::jtag_reset_event_cg'
    'soc_jtag_reset_recovery_test::jtag_recovery_pulse_cg'
    'axi_timer_irq_seq::timer_irq_event_cg'
    'axi_timer_irq_seq::timer_irq_latency_cg'
    'axi_pic_combined_irq_seq::pic_combined_irq_event_cg'
    'axi_pic_combined_irq_seq::pic_combined_irq_state_cg'
    'axi_apb_burst_stress_seq::apb_burst_stress_cg'
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
echo " Phase 2 Completion Gate"
echo "======================================================================"
echo "Run root: $RUN_ROOT"
echo "Firmware: $FW_HEX"
echo "Testlist: $TESTLIST"

echo "======================================================================"
echo " Running no-coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" TESTLIST="$TESTLIST" RUN_DIR="$DIRECTED_DIR" ENABLE_COV=0 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Running coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" TESTLIST="$TESTLIST" RUN_DIR="$COV_DIR" ENABLE_COV=1 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Scanning logs"
echo "======================================================================"
scan_tmp="${RUN_ROOT}/phase2_error_scan.txt.tmp"
scan_err="${RUN_ROOT}/phase2_error_scan_err.txt"
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
    mv "$scan_tmp" "${RUN_ROOT}/phase2_error_scan.txt"
    echo "ERROR: Phase 2 error scan found failures. See ${RUN_ROOT}/phase2_error_scan.txt"
    [ -s "$scan_err" ] && cat "$scan_err"
    exit 1
elif [ "$scan_status" -eq 1 ]; then
    : > "${RUN_ROOT}/phase2_error_scan.txt"
    rm -f "$scan_tmp" "$scan_err"
else
    rm -f "$scan_tmp"
    echo "ERROR: Phase 2 error scan failed:"
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
module_coverage_line=$(awk '/^Total Module Definition Coverage Summary/ {found=1; next} found && /^SCORE/ {getline; print; exit}' "${COV_DIR}/directed_summary.txt")

{
    echo "# Phase 2 Completion Report"
    echo
    echo "- Status: COMPLETE for the current RTL contract"
    echo "- Firmware: \`$FW_HEX\`"
    echo "- Testlist: \`$TESTLIST\`"
    echo "- No-coverage run: \`$DIRECTED_DIR\`"
    echo "- Coverage run: \`$COV_DIR\`"
    echo
    echo "## Regression Results"
    echo
    echo "| Gate | Total | Passed | Failed |"
    echo "| --- | ---: | ---: | ---: |"
    echo "| Directed | ${directed_total:-unknown} | ${directed_passed:-unknown} | ${directed_failed:-unknown} |"
    echo "| Coverage | ${cov_total:-unknown} | ${cov_passed:-unknown} | ${cov_failed:-unknown} |"
    echo
    echo "## Coverage Summary"
    echo
    echo "- Total coverage: \`${coverage_line:-unavailable}\`"
    echo "- Module definition coverage: \`${module_coverage_line:-unavailable}\`"
    echo "- Functional groups: all required Phase 2 groups are 100.00%."
    echo
    echo "## Required Functional Groups"
    echo
    for group_name in "${required_groups[@]}"; do
        echo "- \`${group_name}\`: 100.00%"
    done
    echo
    echo "## Log Scan"
    echo
    echo "- Error scan: clean"
    echo "- Scan output: \`${RUN_ROOT}/phase2_error_scan.txt\`"
    echo
    echo "## Deferred Out Of Phase 2"
    echo
    echo "- RTL multi-outstanding support: current product fabric contract remains single-outstanding."
    echo "- UART TX IRQ, loadable flash-image reads, APB wait/PSLVERR stress, and CPU/CP0 firmware smoke gating are Phase 3A items; use \`make phase3-complete\` for their closure gate."
    echo "- CPU/CP0 UVM-visible exception-entry/return functional coverage remains a separate post-Phase-3A item."
    echo "- SPI-serial flash protocol modeling remains future work; Phase 3A signs off the loadable AXI flash-image/XIP verification window."
} > "$REPORT"

echo "SUCCESS: PHASE 2 COMPLETION GATE PASSED"
echo "Report: $REPORT"
