#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
SOURCE_DIR=${UBOOT_SOURCE_DIR:-"${ROOT_DIR}/third_party/u-boot"}
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/uboot"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
# Keep the default bounded for small CI/VM hosts; override explicitly when
# parallel U-Boot builds are appropriate.
JOBS=${JOBS:-1}
EXPECTED_COMMIT=f919c3a889f0ec7d63a48b5d0ed064386b0980bd

test -f "${SOURCE_DIR}/Makefile"
test -f "${SOURCE_DIR}/.source-commit"
test "$(tr -d '[:space:]' < "${SOURCE_DIR}/.source-commit")" = "${EXPECTED_COMMIT}"
command -v "${CROSS_COMPILE}gcc" >/dev/null
mkdir -p "${RUN_DIR}"

make -C "${SOURCE_DIR}" O="${RUN_DIR}/build" \
    CROSS_COMPILE="${CROSS_COMPILE}" maltael_defconfig \
    >"${RUN_DIR}/config.log" 2>&1
make -C "${SOURCE_DIR}" O="${RUN_DIR}/build" \
    CROSS_COMPILE="${CROSS_COMPILE}" -j"${JOBS}" all \
    >"${RUN_DIR}/build.log" 2>&1

for artifact in u-boot u-boot.bin u-boot-nodtb.bin u-boot.sym; do
    test -s "${RUN_DIR}/build/${artifact}"
done
sha256sum "${RUN_DIR}/build/u-boot" "${RUN_DIR}/build/u-boot.bin" \
    "${RUN_DIR}/build/u-boot-nodtb.bin" >"${RUN_DIR}/artifacts.sha256"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# Official U-Boot MIPS32LE Build Gate

- Result: PASS (official source build)
- Source commit: ${EXPECTED_COMMIT}
- Configuration: maltael_defconfig
- Toolchain: ${CROSS_COMPILE}
- Artifacts: u-boot, u-boot.bin, u-boot-nodtb.bin, u-boot.sym
- Evidence: config.log, build.log, artifacts.sha256
- Boundary: this proves a reproducible upstream U-Boot MIPS32 little-endian
  build only. Malta board configuration is not the mips32-soc-ref machine;
  QSPI image loading, DDR initialization, SoC-specific U-Boot port, Linux
  handoff and RTL system-mode Linux differential remain open.
EOF
echo "U-Boot MIPS32LE build gate: PASS"
