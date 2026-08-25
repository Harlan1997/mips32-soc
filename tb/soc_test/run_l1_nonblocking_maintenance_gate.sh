#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_maintenance"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_nonblocking_maintenance"}
FW_HEX=${FW_DIR}/firmware.hex
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_maintenance" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_MAINTENANCE +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
    "${SCRIPT_DIR}/run.sh"

grep -Eq 'L1_MAINTENANCE_(PASS|PATH_EXERCISED)' "${RUN_DIR}/sim.log"
cat >"${RUN_DIR}/l1_nonblocking_maintenance_report.md" <<'EOF'
# L1 Nonblocking Maintenance Gate

Result: PASS

- The real opt-in CPU/D-cache path executes `Hit_Invalidate_D` and
  `Index_Invalidate_D`.
- Each test fills L1 with an old SRAM value, changes the backing value through
  the uncached alias, invalidates the line, and verifies the following cached
  load refills the new value.
- The adapter drains L1 line traffic before issuing the maintenance handshake.
- Nonblocking tag read/write, writeback maintenance, full ordering and cache
  coherency remain outside this scoped gate.
EOF
echo 'L1 nonblocking maintenance CPU gate: PASS'
