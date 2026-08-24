#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_ddr_nonblocking"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_ddr_nonblocking"}
FW_HEX=${FW_DIR}/firmware.hex
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_ddr_nonblocking" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+SOC_L1_NONBLOCKING_DDR_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
    "${SCRIPT_DIR}/run.sh"

grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
cat >"${RUN_DIR}/l1_ddr_nonblocking_report.md" <<'EOF'
# L1 Nonblocking DDR Window Gate

Result: PASS

- Opt-in `SOC_L1_NONBLOCKING_DDR_ENABLE=1` admits the real physical DDR
  window `0x0800_0000..0x0fff_ffff` to the CPU-facing L1 adapter.
- Firmware performs two stores, same-line readback, a different-line read,
  and a final hit read through the real CPU/L1/AXI/DDR4-controller path.
- Default blocking, SRAM-only and uncached paths are unchanged.
- Physical DDR PHY timing, training and silicon memory behavior remain outside
  this behavioral RTL gate.
EOF
echo 'l1 nonblocking DDR window: PASS'
