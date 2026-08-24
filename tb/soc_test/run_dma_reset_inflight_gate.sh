#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/dma_reset_inflight"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/dma_reset_inflight"}
mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_reset_inflight" OUT_DIR="${FW_DIR}" FW_BASE=firmware all >"${RUN_DIR}/firmware_build.log" 2>&1
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" VCS_EXTRA_ARGS='+define+TB_DMA_RESET_STRESS +define+TB_SKIP_JTAG_RESET_STRESS' "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1
grep -q 'DMA_RESET_STRESS: busy observed' "${RUN_DIR}/sim.log"
grep -q 'DMA_RESET_STRESS: reset released' "${RUN_DIR}/sim.log"
grep -q 'dma_reset_inflight: REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
! grep -q 'dma_reset_inflight: TIMEOUT' "${RUN_DIR}/sim.log"
! grep -q 'dma_reset_inflight: DATA' "${RUN_DIR}/sim.log"
cat >"${RUN_DIR}/dma_reset_inflight_report.md" <<'EOF'
# DMA Reset-In-Flight Gate

- Result: PASS
- Reset was asserted after DMA channel 0 reported `busy`.
- Firmware restarted after reset, completed a 256-byte direct transfer, and
  checked data integrity and DONE/W1C behavior using uncached `kseg1` buffers.
- Physical DMA/DDR reset policy and arbitrary multi-channel interleavings remain open.
EOF
echo "DMA reset-in-flight: PASS"
