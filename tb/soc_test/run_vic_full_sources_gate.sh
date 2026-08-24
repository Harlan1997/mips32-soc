#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${FW_DIR:-${ROOT_DIR}/build/firmware/vic_full_sources}
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/soc_test/vic_full_sources}

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/vic_full_sources" \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all

FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
  VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK" \
  "${ROOT_DIR}/tb/soc_test/run.sh"

grep -q 'VIC_FULL_SOURCES_PASS sources=32 tie=lower-id' "${RUN_DIR}/sim.log"
echo "VIC full-source SoC gate: PASS"
