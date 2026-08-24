#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/srs"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/srs/firmware.hex"}
if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: missing SRS firmware: $FW_HEX"
    exit 1
fi
FW_HEX="$FW_HEX" RUN_DIR="$RUN_DIR" \
    VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:+${VCS_EXTRA_ARGS} }+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_UART_PIN_CHECK +define+TB_SKIP_JTAG_RESET_STRESS" \
    "${SCRIPT_DIR}/run.sh"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
cat > "${RUN_DIR}/srs_completion_report.md" <<EOF
# MIPS32r2 Shadow Register Set Gate

- Status: PASS
- Contract: opt-in software-selected \`SRSCtl.PSS\` bank access
- Firmware: \`$(realpath "$FW_HEX")\`
- Simulation log: \`${RUN_DIR}/sim.log\`
- Residual: exception-entry CSS/ESS switching, ERET shadow restoration, and OS scheduler/Linux SRS ABI are not implemented.
EOF
echo "SUCCESS: SRS CPU firmware gate passed"
