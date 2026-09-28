#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/rtl"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
KERNEL=${KERNEL:-"${ROOT_DIR}/build/linux_boot/rtl_prep/kernel/vmlinux"}
DTB=${DTB:-"${RUN_DIR}/mips32_soc_ref_rtl.dtb"}
DTB_SOURCE=${DTB_SOURCE:-"${SCRIPT_DIR}/mips32_soc_ref_rtl.dts"}
DTC=${DTC:-}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
ELF2HEX=${ELF2HEX:-"${ROOT_DIR}/tb/soc_test/fw/common/elf2hex.py"}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-}
# Keep the UHI environment above the relocated kernel image and below the DTB.
# The generic image is currently about 14 MiB at 0x88800000, so 0x89d00000
# leaves a stable gap without consuming the DTB slot at 0x89f00000.
RNG_ENV_LOAD_VIRTUAL=${RNG_ENV_LOAD_VIRTUAL:-0x89d00000}
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
rng_env_load_physical=$((RNG_ENV_LOAD_VIRTUAL - 0x80000000))
rng_env_offset=$((rng_env_load_physical - DDR_BASE))
if (( rng_env_offset < 0 || rng_env_offset >= DDR_WINDOW_SIZE )); then
    echo "RNG environment address is outside the RTL DDR window: ${RNG_ENV_LOAD_VIRTUAL}" >&2
    exit 1
fi
if [[ -n "${LINUX_RNG_SEED}" ]] &&
   ! [[ "${LINUX_RNG_SEED}" =~ ^[0-9a-fA-F]+$ ]] ||
   (( ${#LINUX_RNG_SEED} % 2 != 0 )); then
    echo "LINUX_RNG_SEED must be an even-length hexadecimal string" >&2
    exit 1
fi
if (( ${#LINUX_RNG_SEED} > 1024 )); then
    echo "LINUX_RNG_SEED exceeds the 512-byte UHI seed limit" >&2
    exit 1
fi

mkdir -p "${RUN_DIR}"
command -v "${CROSS_COMPILE}gcc" >/dev/null
dtb_artifact="${RUN_DIR}/mips32_soc_ref_rtl.dtb"
if [[ -f "${DTB}" && "$(realpath "${DTB}")" != "$(realpath -m "${dtb_artifact}")" ]]; then
    cp -f "${DTB}" "${dtb_artifact}"
fi
command -v "${CROSS_COMPILE}objcopy" >/dev/null
test -f "${KERNEL}"
# Prefer the DTC built alongside the supplied kernel.  This keeps an isolated
# RUN_DIR self-contained and avoids silently selecting a stale DTC from an
# unrelated Linux build directory.
if [[ -z "${DTC}" ]]; then
    DTC="$(dirname "${KERNEL}")/scripts/dtc/dtc"
fi
if [[ ! -x "${DTC}" ]]; then
    echo "missing executable DTC: ${DTC} (set DTC=/path/to/dtc to override)" >&2
    exit 1
fi
if [[ ! -f "${dtb_artifact}" || "${DTB_SOURCE}" -nt "${dtb_artifact}" ]]; then
    "${DTC}" -I dts -O dtb -o "${dtb_artifact}" "${DTB_SOURCE}"
fi
test -f "${dtb_artifact}"
# All later image and manifest operations use the run-local artifact. This
# keeps an externally supplied DTB from leaving the run directory incomplete.
DTB="${dtb_artifact}"

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
    -DRNG_ENV_LOAD_VIRTUAL=${RNG_ENV_LOAD_VIRTUAL} \
    -Wl,-T,"${SCRIPT_DIR}/rtl_bootrom.ld" -Wl,-Map,"${RUN_DIR}/bootrom.map" \
    -o "${RUN_DIR}/bootrom.elf" "${SCRIPT_DIR}/rtl_bootrom.S"
${CROSS_COMPILE}objcopy -O binary "${RUN_DIR}/bootrom.elf" "${RUN_DIR}/bootrom.bin"
python3 "${ELF2HEX}" "${RUN_DIR}/bootrom.bin" "${RUN_DIR}/bootrom.hex"

${CROSS_COMPILE}objcopy -O binary "${KERNEL}" "${RUN_DIR}/kernel.bin"
kernel_size=$(stat -c %s "${RUN_DIR}/kernel.bin")
dtb_offset=$((DTB_OFFSET))
dtb_size=$(stat -c %s "${DTB}")
export RNG_ENV_LOAD_VIRTUAL LINUX_RNG_SEED
python3 - "${RUN_DIR}/rng_env.bin" <<'PY'
import os
import struct
import sys

out = sys.argv[1]
seed = os.environ.get("LINUX_RNG_SEED", "").lower()
base = int(os.environ["RNG_ENV_LOAD_VIRTUAL"], 0)
if not seed:
    data = struct.pack("<I", 0)
else:
    first = b"rngseed=" + seed.encode("ascii") + b"\0"
    second = b"rngdet=1\0"
    string_offset = 12
    second_offset = string_offset + len(first)
    data = struct.pack("<III", base + string_offset,
                       base + second_offset, 0) + first + second
with open(out, "wb") as stream:
    stream.write(data)
PY
env_size=$(stat -c %s "${RUN_DIR}/rng_env.bin")
if (( kernel_image_offset + kernel_size >= rng_env_offset )); then
    echo "kernel image overlaps RNG environment offset ${rng_env_offset}" >&2
    exit 1
fi
if (( rng_env_offset + env_size >= dtb_offset )); then
    echo "RNG environment overlaps DTB offset ${dtb_offset}" >&2
    exit 1
fi
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
ddr_end=$((dtb_offset + 0x20000))
if (( rng_env_offset + env_size > ddr_end )); then
    ddr_end=$((rng_env_offset + env_size))
fi
truncate -s "${ddr_end}" "${ddr_bin}"
dd if="${RUN_DIR}/kernel.bin" of="${ddr_bin}" bs=1 seek="${kernel_image_offset}" conv=notrunc status=none
dd if="${RUN_DIR}/rng_env.bin" of="${ddr_bin}" bs=1 seek="${rng_env_offset}" conv=notrunc status=none
dd if="${DTB}" of="${ddr_bin}" bs=1 seek="${dtb_offset}" conv=notrunc status=none
python3 "${ELF2HEX}" "${ddr_bin}" "${RUN_DIR}/ddr.hex"

cat >"${RUN_DIR}/image_manifest.txt" <<EOF
KERNEL=${KERNEL}
KERNEL_SHA256=$(sha256sum "${KERNEL}" | awk '{print $1}')
DTB=${DTB}
DTB_SHA256=$(sha256sum "${dtb_artifact}" | awk '{print $1}')
KERNEL_ENTRY=${entry}
KERNEL_LOAD_VIRTUAL=${kernel_load_virtual}
KERNEL_LOAD_PHYSICAL=0x$(printf '%08x' "${kernel_load_physical}")
KERNEL_IMAGE_OFFSET=0x$(printf '%08x' "${kernel_image_offset}")
DTB_LOAD_VIRTUAL=${DTB_LOAD_VIRTUAL}
DTB_LOAD_PHYSICAL=0x$(printf '%08x' "${dtb_load_physical}")
DTB_OFFSET=${dtb_offset}
RNG_ENV_LOAD_VIRTUAL=${RNG_ENV_LOAD_VIRTUAL}
RNG_ENV_LOAD_PHYSICAL=0x$(printf '%08x' "${rng_env_load_physical}")
RNG_ENV_OFFSET=0x$(printf '%08x' "${rng_env_offset}")
RNG_ENV_SIZE=${env_size}
RNG_SEED_ID=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
KERNEL_SIZE=${kernel_size}
BOOTROM_SHA256=$(sha256sum "${RUN_DIR}/bootrom.hex" | awk '{print $1}')
DDR_SHA256=$(sha256sum "${RUN_DIR}/ddr.hex" | awk '{print $1}')
EOF
sha256sum "${RUN_DIR}/bootrom.hex" "${RUN_DIR}/ddr.hex" "${RUN_DIR}/rng_env.bin" >"${RUN_DIR}/sha256sums.txt"
echo "RTL Linux image: PASS"
