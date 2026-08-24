#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_dma_v2_model"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/dma_cpu"}
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_cpu" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

RUN_DIR="${RUN_DIR}/qemu" \
FW_ELF="${FW_DIR}/firmware.elf" \
REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=0 \
"${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

grep -q 'dma_cpu test: REGRESSION_TEST_SUCCESS' "${RUN_DIR}/qemu/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DMA v2 Model Gate

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Evidence: firmware_build.log, qemu/qemu_stdout.log, qemu/qemu_stderr.log,
  qemu/qemu_retire.jsonl, qemu/qemu_build_identity.txt
- Scope: four-channel DMA v2 direct-copy CSR model, zero-length completion,
  DONE/ERR W1C, alignment/descriptor classification and channel IRQ model.
- Cross-model evidence: use
  `make qemu-system-dma-v2-event-contract-gate`, which compares ordered
  semantic DMA events and intentionally ignores status-poll latency.
- Residual risk: SG long-form data movement, physical AXI error injection and
  reset-in-flight remain open.
EOF
echo "QEMU system DMA v2 model gate: PASS"
