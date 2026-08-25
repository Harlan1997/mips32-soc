#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_ddr"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_ddr"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
mkdir -p "${RUN_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_ddr" OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" -M mips32-soc-ref -m 64K -kernel "${FW_DIR}/firmware.elf" -nographic -monitor none </dev/null >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
grep -q 'QEMU_SYSTEM_DDR: WINDOW_PASS' "${RUN_DIR}/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DDR Behavioral Window Gate

- Result: PASS
- Machine: mips32-soc-ref
- Scope: DDR status/version/error/W1C and image-independent 128 MiB
  behavioral window read/write plus cached/uncached aliases.
- Evidence: firmware_build.log, qemu_stdout.log, qemu_stderr.log
- Residual risk: no PHY training, JEDEC timing, refresh scheduler, ECC fault
  injection, board timing, or commercial DDR signoff.
EOF
echo "QEMU system DDR behavioral window gate: PASS"
