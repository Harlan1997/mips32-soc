#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/uhi_dtb"}
QEMU_SYSTEM_BIN=${QEMU_SYSTEM_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
DTB=${DTB:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/pc-bios/canyonlands.dtb"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_uhi_dtb"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}

mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_uhi_dtb" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

test -x "${QEMU_SYSTEM_BIN}"
test -s "${DTB}"
test -s "${FW_ELF}"

set +e
timeout "${QEMU_TIMEOUT:-10s}" "${QEMU_SYSTEM_BIN}" \
    -M mips32-soc-ref -m 4M -kernel "${FW_ELF}" -dtb "${DTB}" \
    -display none -monitor none -serial none \
    >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
    echo "QEMU UHI/DTB gate: FAIL (status ${status})" >&2
    exit 1
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU UHI/DTB Gate

- Result: PASS
- Machine: mips32-soc-ref
- Guest: ${FW_ELF}
- DTB: ${DTB}
- Contract: guest observed UHI a0=-2, kseg0 a1, and the FDT magic
  before writing the success mailbox.
- This gate does not claim Linux kernel boot, device-driver probing, or U-Boot
  image loading.
EOF
echo "QEMU UHI/DTB gate: PASS"
