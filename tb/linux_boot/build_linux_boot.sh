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

"${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -static \
    -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" -Wl,--build-id=none \
    -o "${BUILD_DIR}/rootfs/init" "${SCRIPT_DIR}/init.S"
chmod 0755 "${BUILD_DIR}/rootfs/init"

"${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -static \
    -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" -Wl,--build-id=none \
    -o "${BUILD_DIR}/rootfs/vm_child" "${SCRIPT_DIR}/exec_child.S"
chmod 0755 "${BUILD_DIR}/rootfs/vm_child"

# Keep the generated cpio metadata stable across isolated build roots. The
# binaries already have deterministic linker metadata above; fixing mtimes
# also prevents initramfs contents from changing solely because a rebuild ran
# at a different wall-clock time.
touch -d "@${SOURCE_DATE_EPOCH}" \
    "${BUILD_DIR}/rootfs/init" "${BUILD_DIR}/rootfs/vm_child"

# Let the kernel's gen_init_cpio create device nodes without requiring the
# build host to permit mknod in the output directory.
initramfs_list="${BUILD_DIR}/initramfs.list"
{
    printf 'dir /dev 0755 0 0\n'
    printf 'nod /dev/console 0600 0 0 c 5 1\n'
    printf 'nod /dev/ttyS0 0600 0 0 c 4 64\n'
    printf 'file /init %s 0755 0 0\n' "${BUILD_DIR}/rootfs/init"
    printf 'dir /bin 0755 0 0\n'
    printf 'file /bin/vm_child %s 0755 0 0\n' "${BUILD_DIR}/rootfs/vm_child"
} >"${initramfs_list}"

make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
    ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" 32r2el_defconfig
make -C "${LINUX_SOURCE_DIR}" O="${BUILD_DIR}/kernel" \
    ARCH=mips CROSS_COMPILE="${CROSS_COMPILE}" scripts
scripts_config="${LINUX_SOURCE_DIR}/scripts/config"
test -x "${scripts_config}"
kernel_config_args=()
# PHYSICAL_START is conditionally visible in the MIPS Kconfig and is gated by
# CRASH_DUMP. Enable the dependency for every explicitly relocated image. The
# default 0x88000000 image is the RTL DDR layout, so treating that value as an
# unrelocated build silently produces a kernel linked at 0x80100000.
if [[ "${KERNEL_PHYSICAL_START}" != "0x80000000" &&
      "${KERNEL_PHYSICAL_START}" != "0X80000000" ]]; then
    kernel_config_args+=(--enable CONFIG_CRASH_DUMP)
fi
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
