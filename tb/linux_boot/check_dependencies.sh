#!/usr/bin/env bash
set -euo pipefail

cross_prefix=${MIPS_CROSS_COMPILE:-mips64-linux-gnu-}
missing=0

for tool in "${cross_prefix}gcc" "${cross_prefix}objcopy" "${cross_prefix}objdump" qemu-system-mips qemu-mips; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "FOUND: $tool -> $(command -v "$tool")"
  else
    echo "MISSING: $tool"
    missing=1
  fi
done

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
