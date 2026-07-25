#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/cpu_cp0_gate"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}
SUMMARY_FILE="${RUN_DIR}/cpu_cp0_summary.txt"

FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" "${SCRIPT_DIR}/run.sh"

SIM_LOG="${RUN_DIR}/sim.log"
if [ ! -f "$SIM_LOG" ]; then
    echo "ERROR: missing simulation log: $SIM_LOG"
    exit 1
fi

summary_line=$(grep 'CPU_CP0_SUMMARY' "$SIM_LOG" | tail -n 1 || true)
if [ -z "$summary_line" ]; then
    echo "ERROR: missing CPU_CP0_SUMMARY in $SIM_LOG"
    exit 1
fi

extract_count() {
    local key=$1
    echo "$summary_line" | sed -n "s/.*${key}=\([0-9][0-9]*\).*/\1/p"
}

intr_count=$(extract_count intr)
syscall_count=$(extract_count syscall)
ri_count=$(extract_count ri)
adel_count=$(extract_count adel)
eret_count=$(extract_count eret)

if ! grep -q 'REGRESSION_TEST_SUCCESS' "$SIM_LOG"; then
    echo "ERROR: firmware smoke did not reach REGRESSION_TEST_SUCCESS"
    exit 1
fi

for item in \
    "interrupt:${intr_count:-0}" \
    "syscall:${syscall_count:-0}" \
    "reserved_instruction:${ri_count:-0}" \
    "adel:${adel_count:-0}" \
    "eret:${eret_count:-0}"; do
    name=${item%%:*}
    count=${item##*:}
    if [ "$count" -le 0 ]; then
        echo "ERROR: CPU/CP0 gate missing dynamic event: $name"
        echo "Summary: $summary_line"
        exit 1
    fi
done

{
    echo "# CPU/CP0 Firmware Gate"
    echo
    echo "- Status: PASS"
    echo "- Firmware: \`$(realpath "$FW_HEX")\`"
    echo "- Run directory: \`$RUN_DIR\`"
    echo "- Simulation log: \`$SIM_LOG\`"
    echo "- Summary: \`$summary_line\`"
    echo
    echo "| Event | Count |"
    echo "| --- | ---: |"
    echo "| interrupt | $intr_count |"
    echo "| syscall | $syscall_count |"
    echo "| reserved instruction | $ri_count |"
    echo "| AdEL | $adel_count |"
    echo "| ERET | $eret_count |"
} > "$SUMMARY_FILE"

echo "SUCCESS: CPU/CP0 FIRMWARE GATE PASSED"
echo "Summary: $SUMMARY_FILE"
