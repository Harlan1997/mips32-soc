#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/uvm/phase3_complete"}
TESTLIST=${TESTLIST:-"${SCRIPT_DIR}/phase3_directed_tests.txt"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}
FLASH_IMAGE=${FLASH_IMAGE:-"${SCRIPT_DIR}/data/flash_xip_image.hex"}

BUILD_DIR=$(realpath -m "${ROOT_DIR}/build")
RUN_ROOT=$(realpath -m "$RUN_ROOT")
ALLOW_EXTERNAL_RUN_ROOT=${ALLOW_EXTERNAL_RUN_ROOT:-0}
if [[ "${ALLOW_EXTERNAL_RUN_ROOT}" != "1" && "${RUN_ROOT}" != "${BUILD_DIR}/"* ]]; then
    echo "ERROR: RUN_ROOT must be a child directory of ${BUILD_DIR}, got: ${RUN_ROOT}"
    exit 1
fi

DIRECTED_DIR="${RUN_ROOT}/directed"
COV_DIR="${RUN_ROOT}/directed_cov"
CPU_CP0_DIR=${CPU_CP0_DIR:-"${RUN_ROOT}/cpu_cp0_gate"}
CPU_CP0_DIR=$(realpath -m "$CPU_CP0_DIR")
if [[ "${CPU_CP0_DIR}" != "${RUN_ROOT}/"* ]]; then
    echo "ERROR: CPU_CP0_DIR must be a child directory of ${RUN_ROOT}, got: ${CPU_CP0_DIR}"
    exit 1
fi
REPORT="${RUN_ROOT}/phase3_completion_report.md"

ERROR_RE='^(Error:|Error-\[|Fatal:|Fatal-\[)|^UVM_(ERROR|FATAL)[[:space:]]+(@|/)|fabric_axim|Cannot connect to the license server|COVERAGE REPORT GENERATION FAILED|DIRECTED TESTLIST FAILED'

required_groups=(
    'axi_uart_irq_seq::uart_irq_event_cg'
    'axi_apb_fault_stress_seq::apb_fault_stress_cg'
    'axi_flash_image_seq::flash_image_cg'
)

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

if [ ! -f "$FLASH_IMAGE" ]; then
    echo "ERROR: FLASH_IMAGE does not exist: $FLASH_IMAGE"
    exit 1
fi

if [ ! -f "$TESTLIST" ]; then
    echo "ERROR: TESTLIST does not exist: $TESTLIST"
    exit 1
fi

# A completion report is valid only when every owned artifact comes from this
# invocation. Keep deletion constrained to this gate's build subdirectory.
rm -rf -- "$DIRECTED_DIR" "$COV_DIR" "$CPU_CP0_DIR"
rm -f -- "$REPORT" "${RUN_ROOT}/phase3_error_scan.txt" \
    "${RUN_ROOT}/phase3_error_scan.txt.tmp" "${RUN_ROOT}/phase3_error_scan_err.txt"
mkdir -p "$RUN_ROOT"

echo "======================================================================"
echo " Phase 3A Completion Gate"
echo "======================================================================"
echo "Run root: $RUN_ROOT"
echo "Firmware: $FW_HEX"
echo "Flash image: $FLASH_IMAGE"
echo "Testlist: $TESTLIST"

echo "======================================================================"
echo " Running Phase 3A no-coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" FLASH_IMAGE="$FLASH_IMAGE" TESTLIST="$TESTLIST" RUN_DIR="$DIRECTED_DIR" ENABLE_COV=0 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Running Phase 3A coverage directed gate"
echo "======================================================================"
FW_HEX="$FW_HEX" FLASH_IMAGE="$FLASH_IMAGE" TESTLIST="$TESTLIST" RUN_DIR="$COV_DIR" ENABLE_COV=1 \
    "${SCRIPT_DIR}/run_testlist.sh"

echo "======================================================================"
echo " Running CPU/CP0 firmware gate"
echo "======================================================================"
FW_HEX="$FW_HEX" RUN_DIR="$CPU_CP0_DIR" "${ROOT_DIR}/tb/soc_test/run_cpu_cp0_gate.sh"

echo "======================================================================"
echo " Scanning logs"
echo "======================================================================"
scan_tmp="${RUN_ROOT}/phase3_error_scan.txt.tmp"
scan_err="${RUN_ROOT}/phase3_error_scan_err.txt"
if command -v rg >/dev/null 2>&1; then
    set +e
    rg -n "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" "$CPU_CP0_DIR" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
else
    set +e
    grep -RInE --exclude-dir=csrc --exclude-dir=simv.daidir --exclude-dir=urgReport --exclude="*.so" --exclude="*.o" "$ERROR_RE" "$DIRECTED_DIR" "$COV_DIR" "$CPU_CP0_DIR" > "$scan_tmp" 2> "$scan_err"
    scan_status=$?
    set -e
fi

if [ "$scan_status" -eq 0 ]; then
    mv "$scan_tmp" "${RUN_ROOT}/phase3_error_scan.txt"
    echo "ERROR: Phase 3A error scan found failures. See ${RUN_ROOT}/phase3_error_scan.txt"
    [ -s "$scan_err" ] && cat "$scan_err"
    exit 1
elif [ "$scan_status" -eq 1 ]; then
    : > "${RUN_ROOT}/phase3_error_scan.txt"
    rm -f "$scan_tmp" "$scan_err"
else
    rm -f "$scan_tmp"
    echo "ERROR: Phase 3A error scan failed:"
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
cpu_cp0_summary=$(grep 'Summary:' "${CPU_CP0_DIR}/cpu_cp0_summary.txt" | head -n 1 | sed 's/^- Summary: //')

{
    echo "# Phase 3A Completion Report"
    echo
    echo "- Status: COMPLETE for UART TX IRQ, loadable flash-image reads, APB wait/PSLVERR stress, and CPU/CP0 firmware smoke gating."
    echo "- Firmware: \`$FW_HEX\`"
    echo "- Flash image: \`$FLASH_IMAGE\`"
    echo "- Testlist: \`$TESTLIST\`"
    echo "- No-coverage run: \`$DIRECTED_DIR\`"
    echo "- Coverage run: \`$COV_DIR\`"
    echo "- CPU/CP0 run: \`$CPU_CP0_DIR\`"
    echo
    echo "## Regression Results"
    echo
    echo "| Gate | Total | Passed | Failed |"
    echo "| --- | ---: | ---: | ---: |"
    echo "| Phase 3A directed | ${directed_total:-unknown} | ${directed_passed:-unknown} | ${directed_failed:-unknown} |"
    echo "| Phase 3A coverage | ${cov_total:-unknown} | ${cov_passed:-unknown} | ${cov_failed:-unknown} |"
    echo "| CPU/CP0 firmware | 1 | 1 | 0 |"
    echo
    echo "## Coverage Summary"
    echo
    echo "- Total coverage: \`${coverage_line:-unavailable}\`"
    echo "- Functional groups: all required Phase 3A groups are 100.00%."
    echo
    echo "## Required Functional Groups"
    echo
    for group_name in "${required_groups[@]}"; do
        echo "- \`${group_name}\`: 100.00%"
    done
    echo
    echo "## CPU/CP0 Firmware Gate"
    echo
    echo "- ${cpu_cp0_summary:-summary unavailable}"
    echo
    echo "## Log Scan"
    echo
    echo "- Error scan: clean"
    echo "- Scan output: \`${RUN_ROOT}/phase3_error_scan.txt\`"
    echo
    echo "## Still Out Of Phase 3A"
    echo
echo "- Bounded 4-entry fabric multi-outstanding and ID-based response routing are closed by fabric-unit-gate; end-to-end L1/L2/APB/flash multi-outstanding remains outside Phase 3."
    echo "- CPU/CP0 has a firmware smoke gate here; UVM-visible exception-entry/return coverage is outside Phase 3A and closed by the Phase 3B gate."
    echo "- SPI-serial flash protocol modeling remains future work; Phase 3A signs off the loadable AXI flash-image/XIP window used by verification."
} > "$REPORT"

echo "SUCCESS: PHASE 3A COMPLETION GATE PASSED"
echo "Report: $REPORT"
