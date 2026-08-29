#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_peripheral_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_peripherals"}
FLASH_IMAGE=${FLASH_IMAGE:-"${RUN_DIR}/firmware.flash.hex"}
mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_peripherals" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
objcopy=${OBJCOPY:-mips64-linux-gnu-objcopy}
"${objcopy}" -O binary "${FW_DIR}/firmware.elf" "${RUN_DIR}/firmware.flash.bin"
python3 "${ROOT_DIR}/tb/soc_test/fw/common/bin2bytehex.py" \
    "${RUN_DIR}/firmware.flash.bin" "${FLASH_IMAGE}"
FW_TEST=qemu_system_peripherals FW_DIR="${FW_DIR}" \
FLASH_IMAGE="${FLASH_IMAGE}" QEMU_QSPI_IMAGE="${RUN_DIR}/firmware.flash.bin" \
RTL_VCS_EXTRA_ARGS="${RTL_VCS_EXTRA_ARGS:-} +define+SOC_ENABLE_DDR4_STATUS" \
RUN_DIR="${RUN_DIR}" "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"
cat >"${RUN_DIR}/peripheral_scope.md" <<EOF
# QEMU System Peripheral RTL Retire Differential Scope

- Firmware: ${FW_DIR}/firmware.elf
- Scope: GPIO, timer control, DMA status, QSPI status/XIP, DDR status, and mailbox retirement.
- Residual risk: PIC/vector and timer interrupt replay, QSPI command/FIFO/quad/retry, DMA error/reset-in-flight, DDR window/refresh/error behavior, and physical DDR/PHY timing remain open.
EOF
echo "QEMU system peripheral RTL retire differential: PASS"
