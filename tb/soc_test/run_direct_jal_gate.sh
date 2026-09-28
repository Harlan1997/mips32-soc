#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${FW_DIR:-${ROOT_DIR}/build/firmware/direct_jal}
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/soc_test/direct_jal}
FW_HEX="${FW_DIR}/firmware.hex"

make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=direct_jal \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all

FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
  VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK" \
  "${ROOT_DIR}/tb/soc_test/run.sh"

if ! grep -aq 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"; then
    echo "Direct JAL delay-slot gate: FAIL" >&2
    exit 1
fi

cat > "${RUN_DIR}/direct_jal_completion_report.md" <<EOF
# Direct JAL Delay-Slot Gate

- Result: PASS
- Firmware: \`${FW_HEX}\`
- Contract: JAL retires once, its delay slot retires once, the target is
  reached next, and the fall-through poison path is not executed.
EOF
echo "Direct JAL delay-slot gate: PASS"
