#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${ROOT_DIR}/build/firmware/cpu_irq_delay_slot
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/soc_test/cpu_irq_delay_slot}

make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=cpu_irq_delay_slot \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all

FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}" \
  VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK" \
  "${ROOT_DIR}/tb/soc_test/run.sh"

grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
echo "CPU IRQ branch-delay-slot gate: PASS"
