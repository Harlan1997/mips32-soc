#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/srs_exception"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/srs_exception/firmware.hex"}
if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: missing SRS exception firmware: $FW_HEX"
    exit 1
fi
FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" \
    VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:+${VCS_EXTRA_ARGS} }+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_UART_PIN_CHECK +define+TB_SKIP_JTAG_RESET_STRESS" \
    "${SCRIPT_DIR}/run.sh"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
cat > "${RUN_DIR}/srs_exception_completion_report.md" <<EOF
# MIPS32r2 Shadow Register Set Exception Gate

- Status: PASS
- Contract: opt-in \`ESS -> CSS\` exception entry and \`PSS -> CSS\` ERET restore
- Firmware: \`$(realpath "$FW_HEX")\`
- Simulation log: \`${RUN_DIR}/sim.log\`
- Residual: external VEIC/EICSS policy and scheduler/Linux SRS ABI remain open; nested policy is covered by \
  `make srs-nested-gate qemu-system-srs-nested-differential-gate`.
EOF
echo "SUCCESS: SRS exception firmware gate passed"
