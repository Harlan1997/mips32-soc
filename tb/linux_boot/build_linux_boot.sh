#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
LINUX_SOURCE_DIR=${LINUX_SOURCE_DIR:-"${ROOT_DIR}/third_party/linux"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build/linux_boot/real"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
JOBS=${JOBS:-2}

test -f "${LINUX_SOURCE_DIR}/Makefile"
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v flex >/dev/null
command -v bison >/dev/null
mkdir -p "${BUILD_DIR}/rootfs"
mkdir -p "${BUILD_DIR}/rootfs/dev"

"${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -static \
    -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" \
    -o "${BUILD_DIR}/rootfs/init" "${SCRIPT_DIR}/init.S"
chmod 0755 "${BUILD_DIR}/rootfs/init"

"${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
    -nostdlib -nostartfiles -nodefaultlibs -static \
    -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" \
    -o "${BUILD_DIR}/rootfs/vm_child" "${SCRIPT_DIR}/exec_child.S"
chmod 0755 "${BUILD_DIR}/rootfs/vm_child"

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
"${scripts_config}" --file "${BUILD_DIR}/kernel/.config" \
    --enable CONFIG_SERIAL_8250 \
    --enable CONFIG_SERIAL_8250_CONSOLE \
    --enable CONFIG_DEVTMPFS \
    --enable CONFIG_DEVTMPFS_MOUNT \
    --enable CONFIG_INITRAMFS_COMPRESSION_NONE \
    --set-str CONFIG_INITRAMFS_SOURCE "${initramfs_list}" \
    --enable CONFIG_CMDLINE_BOOL \
    --set-str CONFIG_CMDLINE "console=ttyS0,115200 earlycon=uart8250,mmio32,0x40000000 rdinit=/init"
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
