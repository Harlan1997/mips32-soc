#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/srs_nested"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/srs_nested"}
FW_HEX="${FW_DIR}/firmware.hex"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/srs_nested" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
    VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:+${VCS_EXTRA_ARGS} }+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_UART_PIN_CHECK +define+TB_SKIP_JTAG_RESET_STRESS" \
    "${SCRIPT_DIR}/run.sh"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
cat > "${RUN_DIR}/srs_nested_completion_report.md" <<EOF
# MIPS32r2 Shadow Register Set Nested Exception Gate

- Status: PASS
- Contract: nested synchronous exception preserves CSS/PSS and does not overwrite the original exception context
- Firmware: $(realpath "${FW_HEX}")
- Simulation log: ${RUN_DIR}/sim.log
- Residual: external VEIC/EICSS policy and Linux SRS ABI remain open
EOF
echo "SUCCESS: SRS nested exception firmware gate passed"
