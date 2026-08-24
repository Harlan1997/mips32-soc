#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QEMU_SRC=${QEMU_SRC:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0"}
QEMU_BUILD=${QEMU_BUILD:-"${QEMU_SRC}/build-mipsel-linux-user"}

if [[ ! -x "${QEMU_SRC}/configure" ]]; then
    echo "missing QEMU source tree: ${QEMU_SRC}" >&2
    exit 2
fi

mkdir -p "${QEMU_BUILD}"
exec 9>"${QEMU_BUILD}.lock"
flock 9

# QEMU 9.2 carries a fallback sched_attr definition for older libc headers.
# Newer Linux headers expose the same type through sched.h, so guard only the
# fallback and keep this source adjustment reproducible for a fresh build.
if ! rg -q 'SOC_LINUX_USER_SCHED_ATTR_COMPAT' "${QEMU_SRC}/linux-user/syscall.c"; then
    sed -i '/\/\* sched_attr is not defined in glibc \*\//a\/* SOC_LINUX_USER_SCHED_ATTR_COMPAT */\n#ifndef _LINUX_SCHED_TYPES_H' \
        "${QEMU_SRC}/linux-user/syscall.c"
    sed -i '/^#define __NR_sys_sched_getattr/i\#endif /* _LINUX_SCHED_TYPES_H */' \
        "${QEMU_SRC}/linux-user/syscall.c"
fi

# The project SRS patch is system-mode only. Keep its helper declarations and
# translator cases out of the linux-user target, where sysemu helper bodies are
# intentionally not linked.
if ! rg -q 'SOC_LINUX_USER_SRS_COMPAT' "${QEMU_SRC}/target/mips/helper.h"; then
    sed -i '/^DEF_HELPER_2(rdpgpr, tl, env, i32)$/i\#ifndef CONFIG_USER_ONLY\n/* SOC_LINUX_USER_SRS_COMPAT */' \
        "${QEMU_SRC}/target/mips/helper.h"
    sed -i '/^DEF_HELPER_3(wrpgpr, void, env, tl, i32)$/a\#endif /* !CONFIG_USER_ONLY */' \
        "${QEMU_SRC}/target/mips/helper.h"
fi
# An older invocation used a broad sed range and could leave this guard at the
# beginning of the following COP1 switch. Remove that exact misplaced form;
# the SRS cases below have their own scoped guard.
perl -0pi -e 's/\n# endif \/\* !CONFIG_USER_ONLY \*\/\n        default:\n            MIPS_INVAL\("cp1"\);/\n        default:\n            MIPS_INVAL("cp1");/g; s/\n#endif \/\* !CONFIG_USER_ONLY \*\/\n        default:\n            MIPS_INVAL\("cp1"\);/\n        default:\n            MIPS_INVAL("cp1");/g' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"
if ! rg -q 'SOC_LINUX_USER_SRS_TRANSLATOR_COMPAT' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    # Remove an accidental broad-range insertion from an earlier invocation,
    # then apply the guard around only the two CP0 SRS cases.
    sed -i '/^#endif \/\* !CONFIG_USER_ONLY \*\/$/{N;/^#endif \/\* !CONFIG_USER_ONLY \*\/\n        default:$/d;}' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    sed -i '/^        case OPC_RDPGPR:$/i\#ifndef CONFIG_USER_ONLY\n        /* SOC_LINUX_USER_SRS_TRANSLATOR_COMPAT */' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    sed -i '/^        case OPC_WRPGPR:/,$!b; /^        default:/i\#endif /* !CONFIG_USER_ONLY */' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi
if ! rg -q 'SOC_LINUX_USER_SRS_FUNCTION_COMPAT' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    sed -i '/^static inline void gen_load_srsgpr/i\#ifndef CONFIG_USER_ONLY\n/* SOC_LINUX_USER_SRS_FUNCTION_COMPAT */' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    sed -i '/^\/\* Tests \*\//i\#endif /* !CONFIG_USER_ONLY */' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi
if ! rg -q 'SOC_LINUX_USER_SRS_MICROMIPS_COMPAT' "${QEMU_SRC}/target/mips/tcg/micromips_translate.c.inc"; then
    # The shared microMIPS decoder still sees these encodings in linux-user,
    # but their generators reference sysemu-only SRS helpers.  Treat them as
    # reserved there while retaining the system-mode implementation.
    perl -0pi -e 's{(    case 0x05:\n        switch \(minor\) \{\n)(        case RDPGPR:.*?        case WRPGPR:.*?        break;\n)(        default:)}{$1#ifndef CONFIG_USER_ONLY\n        /* SOC_LINUX_USER_SRS_MICROMIPS_COMPAT */\n$2#endif /* !CONFIG_USER_ONLY */\n$3}s' \
        "${QEMU_SRC}/target/mips/tcg/micromips_translate.c.inc"
fi

if [[ ! -f "${QEMU_BUILD}/build.ninja" ]]; then
    (
        cd "${QEMU_BUILD}"
        "${QEMU_SRC}/configure" \
            --target-list=mipsel-linux-user \
            --disable-werror \
            --enable-fdt=disabled
    )
fi

ninja -C "${QEMU_BUILD}" qemu-mipsel
echo "${QEMU_BUILD}/qemu-mipsel"
