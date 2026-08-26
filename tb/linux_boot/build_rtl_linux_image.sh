#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/rtl"}
KERNEL=${KERNEL:-"${ROOT_DIR}/build/linux_boot/rtl_prep/kernel/vmlinux"}
DTB=${DTB:-"${RUN_DIR}/mips32_soc_ref_rtl.dtb"}
DTB_SOURCE=${DTB_SOURCE:-"${SCRIPT_DIR}/mips32_soc_ref_rtl.dts"}
DTC=${DTC:-"${ROOT_DIR}/build/linux_boot/real/kernel/scripts/dtc/dtc"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
ELF2HEX=${ELF2HEX:-"${ROOT_DIR}/tb/soc_test/fw/common/elf2hex.py"}
DTB_OFFSET=${DTB_OFFSET:-0x00f00000}
KERNEL_LOAD_PHYSICAL=0x08000000

mkdir -p "${RUN_DIR}"
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v "${CROSS_COMPILE}objcopy" >/dev/null
test -f "${KERNEL}"
if [[ ! -f "${DTB}" || "${DTB_SOURCE}" -nt "${DTB}" ]]; then
    test -x "${DTC}"
    "${DTC}" -I dts -O dtb -o "${DTB}" "${DTB_SOURCE}"
fi
test -f "${DTB}"

entry=$(${CROSS_COMPILE}readelf -h "${KERNEL}" | awk '/Entry point address:/ {print $NF}')
test -n "${entry}"

${CROSS_COMPILE}gcc -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -DKERNEL_ENTRY=${entry} \
    -Wl,-T,"${SCRIPT_DIR}/rtl_bootrom.ld" -Wl,-Map,"${RUN_DIR}/bootrom.map" \
    -o "${RUN_DIR}/bootrom.elf" "${SCRIPT_DIR}/rtl_bootrom.S"
${CROSS_COMPILE}objcopy -O binary "${RUN_DIR}/bootrom.elf" "${RUN_DIR}/bootrom.bin"
python3 "${ELF2HEX}" "${RUN_DIR}/bootrom.bin" "${RUN_DIR}/bootrom.hex"

${CROSS_COMPILE}objcopy -O binary "${KERNEL}" "${RUN_DIR}/kernel.bin"
kernel_size=$(stat -c %s "${RUN_DIR}/kernel.bin")
dtb_offset=$((DTB_OFFSET))
if (( kernel_size >= dtb_offset )); then
    echo "kernel image (${kernel_size}) overlaps DTB offset ${dtb_offset}" >&2
    exit 1
fi

ddr_bin="${RUN_DIR}/ddr.bin"
truncate -s $((dtb_offset + 0x20000)) "${ddr_bin}"
dd if="${RUN_DIR}/kernel.bin" of="${ddr_bin}" conv=notrunc status=none
dd if="${DTB}" of="${ddr_bin}" bs=1 seek="${dtb_offset}" conv=notrunc status=none
python3 "${ELF2HEX}" "${ddr_bin}" "${RUN_DIR}/ddr.hex"

cat >"${RUN_DIR}/image_manifest.txt" <<EOF
KERNEL=${KERNEL}
KERNEL_ENTRY=${entry}
KERNEL_LOAD_VIRTUAL=0x88000000
KERNEL_LOAD_PHYSICAL=${KERNEL_LOAD_PHYSICAL}
DTB_LOAD_VIRTUAL=0x88f00000
DTB_LOAD_PHYSICAL=0x08f00000
DTB_OFFSET=${dtb_offset}
KERNEL_SIZE=${kernel_size}
EOF
sha256sum "${RUN_DIR}/bootrom.hex" "${RUN_DIR}/ddr.hex" >"${RUN_DIR}/sha256sums.txt"
echo "RTL Linux image: PASS"
