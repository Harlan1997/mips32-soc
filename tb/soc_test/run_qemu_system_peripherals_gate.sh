#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_peripherals"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_peripherals"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}

mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_peripherals" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
[[ -x "${QEMU_BIN}" ]]
sha256sum "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"
set +e
timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" \
    -M "mips32-soc-ref,qspi-image=${FW_ELF}" -m 64K \
    -kernel "${FW_ELF}" -nographic -monitor none \
    >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
status=$?
set -e
[[ ${status} -eq 0 ]]
for marker in GPIO_PASS TIMER_PASS DMA_PASS PIC_PASS QSPI_PASS DDR_PASS; do
    grep -q "QEMU_SYSTEM_PERIPH: ${marker}" "${RUN_DIR}/qemu_stdout.log"
done
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Peripheral Contract

- Result: PASS
- Machine: mips32-soc-ref
- Contract: GPIO, timer, DMA, PIC, QSPI status, DDR window/status
- Evidence: firmware_build.log, firmware.sha256, qemu_stdout.log, qemu_stderr.log
- Residual risk: behavioral model only; no PHY, JEDEC electrical timing, or RTL differential claim.
EOF
echo "QEMU system peripheral contract: PASS"
