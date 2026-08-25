#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_wdt"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/wdt_boot_failure" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware \
    EXTRA_CFLAGS="-DQEMU_SYSTEM_WDT" >"${RUN_DIR}/firmware_build.log" 2>&1

timeout "${QEMU_TIMEOUT:-30}" "${QEMU_BIN}" \
    -M mips32-soc-ref -cpu "${QEMU_CPU:-24Kc}" -m 64K \
    -kernel "${FW_DIR}/firmware.elf" -nographic -monitor none \
    </dev/null >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"

grep -q 'wdt_boot_failure: REGRESSION_TEST_SUCCESS' \
    "${RUN_DIR}/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<'EOF'
# QEMU System WDT/Boot-Status Gate

- Result: PASS
- The QEMU WDT implements CTRL/LOAD/VAL/KICK/STATUS and a 50 MHz virtual
  countdown. Expiry requests one guest reset and preserves the sticky status.
- Boot stage, failure code and POR|watchdog reset cause are retained across
  the reset; the restarted firmware clears the W1C fields and reaches mailbox
  completion.
- Boundary: virtual reference-machine timing, not physical clock/reset or
  production boot-status retention signoff.
EOF
echo "QEMU system WDT/boot-status gate: PASS"
