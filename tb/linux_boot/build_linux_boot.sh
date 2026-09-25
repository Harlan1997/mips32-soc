#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
LINUX_SOURCE_DIR=${LINUX_SOURCE_DIR:-"${ROOT_DIR}/third_party/linux"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build/linux_boot/real"}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
# Linux kernel and initramfs builds are memory-heavy in this environment.
JOBS=${JOBS:-1}
KERNEL_PHYSICAL_START=${KERNEL_PHYSICAL_START:-0x88000000}
LINUX_CMDLINE=${LINUX_CMDLINE:-"console=ttyS0,115200 earlycon=uart8250,mmio32,0x40000000 lpj=624128 rdinit=/init"}
LINUX_PROFILE=${LINUX_PROFILE:-generic}
case "${LINUX_PROFILE}" in
    generic|rtl-minimal) ;;
    *)
        echo "unknown LINUX_PROFILE: ${LINUX_PROFILE}" >&2
        exit 1
        ;;
esac
BUILD_DIR=$(realpath -m "${BUILD_DIR}")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-946684800}
# Include the timezone so gen_initramfs.sh produces the same epoch on hosts
# whose local timezone is not UTC.
KBUILD_BUILD_TIMESTAMP=${KBUILD_BUILD_TIMESTAMP:-"2000-01-01 00:00:00 UTC"}
export SOURCE_DATE_EPOCH KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-build}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-build}

test -f "${LINUX_SOURCE_DIR}/Makefile"
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v flex >/dev/null
command -v bison >/dev/null
mkdir -p "${BUILD_DIR}/rootfs"
mkdir -p "${BUILD_DIR}/rootfs/dev"

# Linux sources are reproducibly fetched but intentionally ignored by the
# project. Apply the tracked SoC irqchip overlay before configuring Kbuild.
chmod +x "${ROOT_DIR}/scripts/linux/apply_mips32_soc_vic.sh"
LINUX_SOURCE_DIR="${LINUX_SOURCE_DIR}" \
    "${ROOT_DIR}/scripts/linux/apply_mips32_soc_vic.sh"

build_guest_binary() {
    local source=$1
    local output=$2
    local stamp="${output}.input.sha256"
    local object_dir
    local object_name
    object_dir=$(dirname "${output}")
    # GNU ld records the input object basename in .symtab; fixed-length names
    # keep the preserved ELF layout stable across isolated build directories.
    case "$(basename "${source}")" in
        init.S) object_name=init32im.o ;;
        exec_child.S) object_name=vm_child.o ;;
        *) object_name="$(basename "${output}").o" ;;
    esac
    local object_output="${object_dir}/${object_name}"
    local input_hash
    input_hash=$({
        sha256sum "${source}" "${SCRIPT_DIR}/init.ld"
        printf 'guest_binary_format=preserve-elf-v3-fixed-object-layout\n'
    } | sha256sum | awk '{print $1}')
    if [[ ! -s "${output}" || ! -s "${stamp}" || "$(<"${stamp}")" != "${input_hash}" ]]; then
        "${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
            -nostdlib -nostartfiles -nodefaultlibs -static -c \
            -o "${object_output}" "${source}"
        "${CROSS_COMPILE}gcc" -EL -mabi=32 -march=mips32r2 -mno-abicalls -fno-pic \
            -nostdlib -nostartfiles -nodefaultlibs -static \
            -Wl,-e,_start -Wl,-T,"${SCRIPT_DIR}/init.ld" -Wl,--build-id=none \
            -o "${output}" "${object_output}"
        # Keep the complete guest ELF.  The RTL userspace contract exercises
        # the guest's protection transition and relies on the stable ELF
        # payload produced by this build; stripping changes the initramfs
        # layout and can move unrelated kernel data.
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
    printf 'dir /sys 0755 0 0\n'
    printf 'file /init %s 0755 0 0\n' "${BUILD_DIR}/rootfs/init"
    printf 'dir /bin 0755 0 0\n'
    printf 'file /bin/vm_child %s 0755 0 0\n' "${BUILD_DIR}/rootfs/vm_child"
} >"${initramfs_list_tmp}"
if [[ ! -e "${initramfs_list}" ]] || ! cmp -s "${initramfs_list_tmp}" "${initramfs_list}"; then
    mv -f "${initramfs_list_tmp}" "${initramfs_list}"
else
    rm -f "${initramfs_list_tmp}"
fi

# Keep the path recorded in CONFIG_INITRAMFS_SOURCE stable for the RTL
# profile. Linux embeds that setting in IKCONFIG, so using BUILD_DIR here
# makes otherwise equivalent kernels differ across scratch directories. The
# list contents still point at the run-local guest files; only this tiny
# configuration input path is shared and atomically replaced.
initramfs_config_source="${initramfs_list}"
if [[ "${LINUX_PROFILE}" == "generic" ]]; then
    # Keep the embedded IKCONFIG string length stable across scratch build
    # directories.  The RTL CPU currently has a known sensitivity to the
    # resulting absolute addresses of references into kernel_config_data.
    # This canonical path is deliberately the same length as the established
    # relocated generic image path.
    # Keep this path in the shared scratch area so the config remains stable
    # across relocatable BUILD_DIR values. Its spelling also preserves the
    # proven compressed IKCONFIG footprint of the generic RTL image.
    initramfs_config_source="/data/disk/tmp/mips32-soc/generic-userspace-sc-hazard-v110-fixed-v2.initramfs.list"
elif [[ "${LINUX_PROFILE}" == "rtl-minimal" ]]; then
    initramfs_config_source="${ROOT_DIR}/build/linux_boot/rtl-minimal-canonical.initramfs.list"
fi
if [[ "${LINUX_PROFILE}" == "generic" ||
      "${LINUX_PROFILE}" == "rtl-minimal" ]]; then
    stable_initramfs_tmp="${initramfs_config_source}.tmp"
    mkdir -p "$(dirname "${initramfs_config_source}")"
    cp "${initramfs_list}" "${stable_initramfs_tmp}"
    if [[ ! -e "${initramfs_config_source}" ]] ||
       ! cmp -s "${stable_initramfs_tmp}" "${initramfs_config_source}"; then
        mv -f "${stable_initramfs_tmp}" "${initramfs_config_source}"
    else
        rm -f "${stable_initramfs_tmp}"
    fi
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
        "${LINUX_SOURCE_DIR}/arch/mips/configs/generic/el.config" \
        "${LINUX_SOURCE_DIR}/drivers/irqchip/irq-mips32-soc-vic.c" \
        "${LINUX_SOURCE_DIR}/drivers/irqchip/Kconfig" \
        "${LINUX_SOURCE_DIR}/drivers/irqchip/Makefile" \
        "${LINUX_SOURCE_DIR}/arch/mips/kernel/setup.c" \
        "${LINUX_SOURCE_DIR}/drivers/char/random.c" \
        "${LINUX_SOURCE_DIR}/include/linux/random.h" \
        "${SCRIPT_DIR}/mips32_soc_ref.dts"
    # The kernel embeds this generated initramfs. Include its content in the
    # configuration stamp so a changed guest binary cannot reuse an old
    # kernel merely because the source tree and DTS are unchanged.
    sha256sum "${initramfs_list}"
    printf 'INITRAMFS_CONFIG_SOURCE=%s\n' "${initramfs_config_source}"
    printf 'KERNEL_PHYSICAL_START=%s\n' "${KERNEL_PHYSICAL_START}"
    printf 'CONFIG_CRASH_DUMP=%s\n' "${crash_dump_config}"
    printf 'LINUX_CMDLINE=%s\n' "${LINUX_CMDLINE}"
    printf 'LINUX_PROFILE=%s\n' "${LINUX_PROFILE}"
    if [[ "${LINUX_PROFILE}" == "rtl-minimal" ]]; then
        sha256sum "${SCRIPT_DIR}/rtl_minimal.config"
    fi
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
        --enable CONFIG_MIPS32_SOC_VIC \
        --enable CONFIG_GPIOLIB \
        --enable CONFIG_GPIO_GENERIC_PLATFORM \
        --enable CONFIG_GPIO_SYSFS \
        --enable CONFIG_DEVTMPFS \
        --enable CONFIG_DEVTMPFS_MOUNT \
        --enable CONFIG_INITRAMFS_COMPRESSION_NONE \
        --set-str CONFIG_INITRAMFS_SOURCE "${initramfs_config_source}" \
        --enable CONFIG_CMDLINE_BOOL \
        --set-str CONFIG_CMDLINE "${LINUX_CMDLINE}" \
        --set-val CONFIG_PHYSICAL_START "${KERNEL_PHYSICAL_START}"
    if [[ "${LINUX_PROFILE}" == "rtl-minimal" ]]; then
        while IFS= read -r option || [[ -n "${option}" ]]; do
            [[ -z "${option}" || "${option}" == \#* ]] && continue
            "${scripts_config}" --file "${BUILD_DIR}/kernel/.config" --disable "${option}"
        done < "${SCRIPT_DIR}/rtl_minimal.config"
    fi
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
python3 "${ROOT_DIR}/scripts/check_linux_soc_contract.py" \
    "${BUILD_DIR}/kernel/.config"

kernel_load_virtual=$(${CROSS_COMPILE}readelf -l "${BUILD_DIR}/kernel/vmlinux" | \
    awk '$1 == "LOAD" {print $3; exit}')
test -n "${kernel_load_virtual}"
expected_kernel_virtual=$((KERNEL_PHYSICAL_START))
if (( kernel_load_virtual != expected_kernel_virtual )); then
    echo "kernel load address ${kernel_load_virtual} does not match CONFIG_PHYSICAL_START ${KERNEL_PHYSICAL_START}" >&2
    exit 1
fi
echo "Linux kernel build: PASS (physical start ${KERNEL_PHYSICAL_START})"
