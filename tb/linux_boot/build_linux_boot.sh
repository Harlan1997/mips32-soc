#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
LINUX_SOURCE_DIR=${LINUX_SOURCE_DIR:-"${ROOT_DIR}/third_party/linux"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build/linux_boot/real"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
JOBS=${JOBS:-2}
KERNEL_PHYSICAL_START=${KERNEL_PHYSICAL_START:-0x88000000}
BUILD_DIR=$(realpath -m "${BUILD_DIR}")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-946684800}
KBUILD_BUILD_TIMESTAMP=${KBUILD_BUILD_TIMESTAMP:-"2000-01-01 00:00:00"}
export SOURCE_DATE_EPOCH KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-build}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-build}

test -f "${LINUX_SOURCE_DIR}/Makefile"
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v flex >/dev/null
command -v bison >/dev/null
mkdir -p "${BUILD_DIR}/rootfs"
mkdir -p "${BUILD_DIR}/rootfs/dev"

build_guest_binary() {
    local source=$1
    local output=$2
    local stamp="${output}.input.sha256"
    local input_hash
    input_hash=$(sha256sum "${source}" "${SCRIPT_DIR}/init.ld" | sha256sum | awk '{print $1}')
    if [[ ! -s "${output}" || ! -s "${stamp}" || "$(<"${stamp}")" != "${input_hash}" ]]; then
        "${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
            -nostdlib -nostartfiles -nodefaultlibs -static \
            -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" -Wl,--build-id=none \
            -o "${output}" "${source}"
        chmod 0755 "${output}"
        # Keep generated cpio metadata stable across isolated build roots.
        touch -d "@${SOURCE_DATE_EPOCH}" "${output}"
        printf '%s\n' "${input_hash}" >"${stamp}"
    fi
}

build_guest_binary "${SCRIPT_DIR}/init.S" "${BUILD_DIR}/rootfs/init"
build_guest_binary "${SCRIPT_DIR}/exec_child.S" "${BUILD_DIR}/rootfs/vm_child"

# Let the kernel's gen_init_cpio create device nodes without requiring the
# build host to permit mknod in the output directory.
initramfs_list="${BUILD_DIR}/initramfs.list"
initramfs_list_tmp="${initramfs_list}.tmp"
init_hash=$(sha256sum "${BUILD_DIR}/rootfs/init" | awk '{print $1}')
child_hash=$(sha256sum "${BUILD_DIR}/rootfs/vm_child" | awk '{print $1}')
{
    printf '# init_sha256=%s\n' "${init_hash}"
    printf '# vm_child_sha256=%s\n' "${child_hash}"
    printf 'dir /dev 0755 0 0\n'
    printf 'nod /dev/console 0600 0 0 c 5 1\n'
    printf 'nod /dev/ttyS0 0600 0 0 c 4 64\n'
    printf 'file /init %s 0755 0 0\n' "${BUILD_DIR}/rootfs/init"
    printf 'dir /bin 0755 0 0\n'
    printf 'file /bin/vm_child %s 0755 0 0\n' "${BUILD_DIR}/rootfs/vm_child"
} >"${initramfs_list_tmp}"
if [[ ! -e "${initramfs_list}" ]] || ! cmp -s "${initramfs_list_tmp}" "${initramfs_list}"; then
    mv -f "${initramfs_list_tmp}" "${initramfs_list}"
else
    rm -f "${initramfs_list_tmp}"
fi

scripts_config="${LINUX_SOURCE_DIR}/scripts/config"
test -x "${scripts_config}"
config_stamp="${BUILD_DIR}/kernel/.mips32_soc_config.sha256"
crash_dump_config=disabled
if [[ "${KERNEL_PHYSICAL_START}" != "0x80000000" &&
      "${KERNEL_PHYSICAL_START}" != "0X80000000" ]]; then
    crash_dump_config=enabled
fi
config_inputs_hash=$({
    sha256sum \
        "${LINUX_SOURCE_DIR}/arch/mips/configs/generic_defconfig" \
        "${LINUX_SOURCE_DIR}/arch/mips/configs/generic/32r2.config" \
        "${LINUX_SOURCE_DIR}/arch/mips/configs/generic/el.config"
    printf 'KERNEL_PHYSICAL_START=%s\n' "${KERNEL_PHYSICAL_START}"
    printf 'CONFIG_CRASH_DUMP=%s\n' "${crash_dump_config}"
} | sha256sum | awk '{print $1}')
kernel_config_args=()
# PHYSICAL_START is conditionally visible in the MIPS Kconfig and is gated by
# CRASH_DUMP. Enable the dependency for every explicitly relocated image. The
# default 0x88000000 image is the RTL DDR layout, so treating that value as an
# unrelocated build silently produces a kernel linked at 0x80100000.
if [[ "${crash_dump_config}" == enabled ]]; then
    kernel_config_args+=(--enable CONFIG_CRASH_DUMP)
fi
if [[ ! -s "${config_stamp}" || "$(<"${config_stamp}")" != "${config_inputs_hash}" ]]; then
    make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
        ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" 32r2el_defconfig
    make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
        ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" scripts
    "${scripts_config}" --file "${BUILD_DIR}/kernel/.config" \
        "${kernel_config_args[@]}" \
        --enable CONFIG_SERIAL_8250 \
        --enable CONFIG_SERIAL_8250_CONSOLE \
        --enable CONFIG_DEVTMPFS \
        --enable CONFIG_DEVTMPFS_MOUNT \
        --enable CONFIG_INITRAMFS_COMPRESSION_NONE \
        --set-str CONFIG_INITRAMFS_SOURCE "${initramfs_list}" \
        --enable CONFIG_CMDLINE_BOOL \
        --set-str CONFIG_CMDLINE "console=ttyS0,115200 earlycon=uart8250,mmio32,0x40000000 rdinit=/init" \
        --set-val CONFIG_PHYSICAL_START "${KERNEL_PHYSICAL_START}"
    make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
        ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
    printf '%s\n' "${config_inputs_hash}" >"${config_stamp}"
fi
make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
    ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" -j"${JOBS}" vmlinux
make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
    ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" -j"${JOBS}" scripts_dtc
"${BUILD_DIR}/kernel/scripts/dtc/dtc" -I dts -O dtb \
    -o "${BUILD_DIR}/mips32_soc_ref.dtb" "${SCRIPT_DIR}/mips32_soc_ref.dts"
test -s "${BUILD_DIR}/kernel/vmlinux"
test -s "${BUILD_DIR}/mips32_soc_ref.dtb"

kernel_load_virtual=$(${CROSS_COMPILE}readelf -l "${BUILD_DIR}/kernel/vmlinux" | \
    awk '$1 == "LOAD" {print $3; exit}')
test -n "${kernel_load_virtual}"
expected_kernel_virtual=$((KERNEL_PHYSICAL_START))
if (( kernel_load_virtual != expected_kernel_virtual )); then
    echo "kernel load address ${kernel_load_virtual} does not match CONFIG_PHYSICAL_START ${KERNEL_PHYSICAL_START}" >&2
    exit 1
fi
echo "Linux kernel build: PASS (physical start ${KERNEL_PHYSICAL_START})"
