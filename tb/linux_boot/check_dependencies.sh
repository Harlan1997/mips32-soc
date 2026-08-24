#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
cross_prefix=${MIPS_CROSS_COMPILE:-mips64-linux-gnu-}
qemu_system_bin=${QEMU_SYSTEM_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
qemu_user_bin=${QEMU_USER_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-linux-user/qemu-mipsel"}
missing=0

check_tool() {
  local label=$1
  local candidate=$2
  if [[ "$candidate" == */* ]]; then
    if [[ -x "$candidate" ]]; then
      echo "FOUND: ${label} -> ${candidate}"
    else
      echo "MISSING: ${label} (${candidate})"
      missing=1
    fi
  elif command -v "$candidate" >/dev/null 2>&1; then
    echo "FOUND: ${label} -> $(command -v "$candidate")"
  else
    echo "MISSING: ${label} (${candidate})"
    missing=1
  fi
}

check_tool "${cross_prefix}gcc" "${cross_prefix}gcc"
check_tool "${cross_prefix}objcopy" "${cross_prefix}objcopy"
check_tool "${cross_prefix}objdump" "${cross_prefix}objdump"
check_tool "QEMU system-mode mips32-soc-ref" "${qemu_system_bin}"
check_tool "QEMU linux-user mipsel" "${qemu_user_bin}"

for source in "${UBOOT_SOURCE_DIR:-third_party/u-boot}" "${LINUX_SOURCE_DIR:-third_party/linux}"; do
  if [[ -d "$source" ]]; then
    echo "FOUND: source directory $source"
  else
    echo "MISSING: source directory $source"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "LINUX_BOOT_DEPENDENCY_GATE: BLOCKED"
  exit 2
fi

echo "LINUX_BOOT_DEPENDENCY_GATE: PASS"
