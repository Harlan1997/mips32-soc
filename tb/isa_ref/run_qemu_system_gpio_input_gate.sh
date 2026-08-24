#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_gpio_input"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
QEMU_BIN=$(realpath -m "${QEMU_BIN}")
GPIO_EXPECTED=${GPIO_EXPECTED:-0xA55A5AA5}
mkdir -p "${RUN_DIR}"
[[ -x "${QEMU_BIN}" ]]

FW_DIR="${RUN_DIR}/firmware"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_peripherals" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware \
    EXTRA_CFLAGS="-DQEMU_GPIO_INPUT_TEST -DQEMU_GPIO_EXPECTED=${GPIO_EXPECTED} -DQEMU_TIMER_IRQ_TEST" \
    >"${RUN_DIR}/firmware_build.log" 2>&1

timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" \
    -M "mips32-soc-ref,gpio-input=${GPIO_EXPECTED}" \
    -cpu "${QEMU_CPU:-24Kc}" -m 64K \
    -kernel "${FW_DIR}/firmware.elf" -nographic -monitor none \
    >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
grep -q 'QEMU_SYSTEM_PERIPH: GPIO_INPUT_PASS' "${RUN_DIR}/qemu_stdout.log"
grep -q 'QEMU_SYSTEM_PERIPH: TIMER_IRQ_PASS' "${RUN_DIR}/qemu_stdout.log"
grep -q 'QEMU_SYSTEM_PERIPH: DDR_PASS' "${RUN_DIR}/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System GPIO Input Gate

- Result: PASS
- Machine property: gpio-input=${GPIO_EXPECTED}
- Contract: input-only GPIO readback through GPIO_DATA with GPIO_DIR=0.
- Timer contract: source-2 interrupt assertion, sticky INT readback and W1C.
- Default behavior: no property preserves zero external input and output readback.
- Scope: QEMU reference-machine peripheral model; RTL pin timing and board I/O remain separate.
EOF
echo "QEMU system GPIO input gate: PASS"
