#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/rtl"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
KERNEL=${KERNEL:-"${ROOT_DIR}/build/linux_boot/rtl_prep/kernel/vmlinux"}
DTB=${DTB:-"${RUN_DIR}/mips32_soc_ref_rtl.dtb"}
DTB_SOURCE=${DTB_SOURCE:-"${SCRIPT_DIR}/mips32_soc_ref_rtl.dts"}
DTC=${DTC:-"${ROOT_DIR}/build/linux_boot/real/kernel/scripts/dtc/dtc"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
ELF2HEX=${ELF2HEX:-"${ROOT_DIR}/tb/soc_test/fw/common/elf2hex.py"}
dtb_load_virtual_input=${DTB_LOAD_VIRTUAL-}
dtb_offset_input=${DTB_OFFSET-}
if [[ -z "${dtb_load_virtual_input}" && -z "${dtb_offset_input}" ]]; then
    DTB_LOAD_VIRTUAL=0x89f00000
    DTB_OFFSET=0x01f00000
elif [[ -z "${dtb_load_virtual_input}" ]]; then
    DTB_OFFSET=${dtb_offset_input}
    DTB_LOAD_VIRTUAL=$(printf '0x%08x' "$((0x80000000 + 0x08000000 + DTB_OFFSET))")
elif [[ -z "${dtb_offset_input}" ]]; then
    DTB_LOAD_VIRTUAL=${dtb_load_virtual_input}
    DTB_OFFSET=$(printf '0x%x' "$((DTB_LOAD_VIRTUAL - 0x80000000 - 0x08000000))")
else
    DTB_LOAD_VIRTUAL=${dtb_load_virtual_input}
    DTB_OFFSET=${dtb_offset_input}
fi
DDR_BASE=0x08000000
DDR_WINDOW_SIZE=0x08000000

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

# Linux links the image in kseg0.  The RTL crossbar presents the low physical
# aliases in the first DDR window, so derive the backing-image offset from the
# ELF load address instead of assuming that the first byte belongs at DDR[0].
kernel_load_virtual=$(${CROSS_COMPILE}readelf -l "${KERNEL}" | \
    awk '$1 == "LOAD" {print $3; exit}')
test -n "${kernel_load_virtual}"
kernel_load_physical=$((kernel_load_virtual - 0x80000000))
if (( kernel_load_physical < DDR_BASE )); then
    echo "kernel load address ${kernel_load_virtual} is below DDR base ${DDR_BASE}" >&2
    exit 1
fi
kernel_image_offset=$((kernel_load_physical - DDR_BASE))
dtb_load_physical=$((DTB_LOAD_VIRTUAL - 0x80000000))
expected_dtb_offset=$((dtb_load_physical - DDR_BASE))
if (( expected_dtb_offset != DTB_OFFSET )); then
    echo "DTB virtual address ${DTB_LOAD_VIRTUAL} does not match offset ${DTB_OFFSET}" >&2
    exit 1
fi
dtb_offset=${DTB_OFFSET}
if (( dtb_offset < 0 )); then
    echo "DTB virtual address ${DTB_LOAD_VIRTUAL} is below the DDR window" >&2
    exit 1
fi

${CROSS_COMPILE}gcc -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -DKERNEL_ENTRY=${entry} \
    -DDTB_LOAD_VIRTUAL=${DTB_LOAD_VIRTUAL} \
    -Wl,-T,"${SCRIPT_DIR}/rtl_bootrom.ld" -Wl,-Map,"${RUN_DIR}/bootrom.map" \
    -o "${RUN_DIR}/bootrom.elf" "${SCRIPT_DIR}/rtl_bootrom.S"
${CROSS_COMPILE}objcopy -O binary "${RUN_DIR}/bootrom.elf" "${RUN_DIR}/bootrom.bin"
python3 "${ELF2HEX}" "${RUN_DIR}/bootrom.bin" "${RUN_DIR}/bootrom.hex"

${CROSS_COMPILE}objcopy -O binary "${KERNEL}" "${RUN_DIR}/kernel.bin"
kernel_size=$(stat -c %s "${RUN_DIR}/kernel.bin")
dtb_offset=$((DTB_OFFSET))
dtb_size=$(stat -c %s "${DTB}")
if (( kernel_image_offset + kernel_size > DDR_WINDOW_SIZE )); then
    echo "kernel image exceeds RTL DDR backing window (${DDR_WINDOW_SIZE} bytes)" >&2
    exit 1
fi
if (( kernel_image_offset + kernel_size >= dtb_offset )); then
    echo "kernel image [0x$(printf '%x' "${kernel_image_offset}")..0x$(printf '%x' "$((kernel_image_offset + kernel_size))")] overlaps DTB offset ${dtb_offset}" >&2
    exit 1
fi
if (( dtb_offset + dtb_size > DDR_WINDOW_SIZE )); then
    echo "DTB exceeds RTL DDR backing window (${DDR_WINDOW_SIZE} bytes)" >&2
    exit 1
fi

ddr_bin="${RUN_DIR}/ddr.bin"
truncate -s $((dtb_offset + 0x20000)) "${ddr_bin}"
dd if="${RUN_DIR}/kernel.bin" of="${ddr_bin}" bs=1 seek="${kernel_image_offset}" conv=notrunc status=none
dd if="${DTB}" of="${ddr_bin}" bs=1 seek="${dtb_offset}" conv=notrunc status=none
python3 "${ELF2HEX}" "${ddr_bin}" "${RUN_DIR}/ddr.hex"

cat >"${RUN_DIR}/image_manifest.txt" <<EOF
KERNEL=${KERNEL}
KERNEL_ENTRY=${entry}
KERNEL_LOAD_VIRTUAL=${kernel_load_virtual}
KERNEL_LOAD_PHYSICAL=0x$(printf '%08x' "${kernel_load_physical}")
KERNEL_IMAGE_OFFSET=0x$(printf '%08x' "${kernel_image_offset}")
DTB_LOAD_VIRTUAL=${DTB_LOAD_VIRTUAL}
DTB_LOAD_PHYSICAL=0x$(printf '%08x' "${dtb_load_physical}")
DTB_OFFSET=${dtb_offset}
KERNEL_SIZE=${kernel_size}
EOF
sha256sum "${RUN_DIR}/bootrom.hex" "${RUN_DIR}/ddr.hex" >"${RUN_DIR}/sha256sums.txt"
echo "RTL Linux image: PASS"
