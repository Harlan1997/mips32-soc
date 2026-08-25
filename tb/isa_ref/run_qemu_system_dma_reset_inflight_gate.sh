#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_dma_reset_inflight"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_reset_inflight" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

timeout "${QEMU_TIMEOUT:-30}" "${QEMU_BIN}" \
    -M "mips32-soc-ref,dma-reset-inflight=on" \
    -cpu "${QEMU_CPU:-24Kc}" -m 64K -kernel "${FW_DIR}/firmware.elf" \
    -nographic -monitor none >"${RUN_DIR}/qemu_stdout.log" \
    2>"${RUN_DIR}/qemu_stderr.log"

grep -q 'dma_reset_inflight: REGRESSION_TEST_SUCCESS' \
    "${RUN_DIR}/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<'EOF'
# QEMU System DMA Reset-In-Flight Gate

- Result: PASS
- The opt-in reference machine requests one guest reset after the first DMA
  start, before source data is copied.
- The reset callback clears DMA busy/status/IRQ state; the restarted guest
  performs the 256-byte direct transfer and verifies data plus DONE/W1C.
- Boundary: this is a custom-machine reset contract, not physical DDR reset
  timing or arbitrary multi-channel reset interleavings.
EOF
echo "QEMU system DMA reset-in-flight gate: PASS"
