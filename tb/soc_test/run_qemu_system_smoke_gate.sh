#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_smoke"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_smoke"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}

mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_smoke" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

if [[ ! -x "${QEMU_BIN}" ]]; then
    echo "QEMU system smoke: BLOCKED (missing ${QEMU_BIN})" >&2
    exit 2
fi

sha256sum "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"
set +e
timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" \
    -M mips32-soc-ref -m 64K -kernel "${FW_ELF}" \
    -nographic -monitor none </dev/null >"${RUN_DIR}/qemu_stdout.log" \
    2>"${RUN_DIR}/qemu_stderr.log"
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
    echo "QEMU system smoke: FAIL (exit ${status})" >&2
    exit 1
fi

grep -q "QEMU_SYSTEM_SMOKE: UART_PASS" "${RUN_DIR}/qemu_stdout.log"
grep -q "QEMU_SYSTEM_SMOKE: SRAM_PASS" "${RUN_DIR}/qemu_stdout.log"
if grep -q "SRAM_ALIAS_FAIL" "${RUN_DIR}/qemu_stdout.log"; then
    echo "QEMU system smoke: FAIL (SRAM alias)" >&2
    exit 1
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System SRAM/UART/Mailbox Smoke

- Result: PASS
- Machine: mips32-soc-ref
- QEMU: ${QEMU_BIN}
- Firmware: ${FW_ELF}
- Contract: SRAM, kseg1 alias, UART TX, success mailbox
- Evidence: firmware_build.log, firmware.sha256, qemu_stdout.log, qemu_stderr.log
EOF
echo "QEMU system smoke: PASS"
