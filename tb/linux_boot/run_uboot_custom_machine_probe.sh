#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/uboot_custom_probe"}
QEMU_SYSTEM_BIN=${QEMU_SYSTEM_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
UBOOT_ELF=${UBOOT_ELF:-"${ROOT_DIR}/third_party/u-boot/build/linux_boot/uboot/build-soc-probe/u-boot"}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-2}

test -x "${QEMU_SYSTEM_BIN}"
test -s "${UBOOT_ELF}"
mkdir -p "${RUN_DIR}"

set +e
timeout "${TIMEOUT_SECONDS}s" "${QEMU_SYSTEM_BIN}" \
    -M mips32-soc-ref,malta-u-boot-compat=on -m 64M -cpu 24Kc \
    -kernel "${UBOOT_ELF}" -display none -monitor none \
    -d in_asm,guest_errors -D "${RUN_DIR}/qemu_trace.log" \
    >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
status=$?
set -e

if ! rg -q 'board_init_f|lowlevel_init' "${RUN_DIR}/qemu_trace.log"; then
    echo "U-Boot custom-machine probe: FAIL (CPU did not reach board init)" >&2
    exit 1
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU custom-machine U-Boot compatibility probe

- Result: INCOMPLETE (execution reached U-Boot board initialization)
- Image: ${UBOOT_ELF}
- Machine: mips32-soc-ref with opt-in malta-u-boot-compat=on
- Exit status: ${status} (timeout is expected for this bounded probe)
- Evidence: qemu_trace.log, qemu_stdout.log, qemu_stderr.log
- Boundary: this proves ELF loading, kseg1 flash aliasing, CPU entry and the
  opt-in legacy Malta UART/revision compatibility endpoint. It does not prove
  a SoC U-Boot port, DDR/QSPI initialization, Linux handoff, or a boot prompt.
EOF

echo "U-Boot custom-machine probe: reached board initialization"
