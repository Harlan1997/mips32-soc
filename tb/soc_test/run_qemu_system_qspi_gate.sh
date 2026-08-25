#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_qspi"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_qspi"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_qspi" OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" -M "mips32-soc-ref,qspi-image=${FW_DIR}/firmware.elf" -m 64K -kernel "${FW_DIR}/firmware.elf" -nographic -monitor none </dev/null >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
grep -q 'QEMU_SYSTEM_QSPI: COMMAND_PASS' "${RUN_DIR}/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System QSPI Command/FIFO Model Gate

- Result: PASS
- Machine: mips32-soc-ref
- Scope: APB command configuration, x1/quad image-backed reads, TX/RX FIFO,
  busy error, IRQ/DONE W1C, abort and timeout status.
- Evidence: firmware_build.log, qemu_stdout.log, qemu_stderr.log
- Residual risk: transaction-level model only; no SPI pin timing, PHY, JEDEC
  device behavior, erase/program endurance, or RTL/QEMU retire differential claim.
EOF
echo "QEMU system QSPI command model gate: PASS"
