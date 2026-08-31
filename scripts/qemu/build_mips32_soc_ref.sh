#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QEMU_SRC=${QEMU_SRC:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0"}
QEMU_BUILD=${QEMU_BUILD:-"${QEMU_SRC}/build-mipsel-softmmu"}
QEMU_BUILD_JOBS=${QEMU_BUILD_JOBS:-1}

# All system-mode gates share one patched QEMU build directory.  Serialize
# configure/ninja so concurrent Make invocations cannot partially overwrite
# Meson's native file or the generated build graph.
mkdir -p "${QEMU_BUILD}"
exec 9>"${QEMU_BUILD}.lock"
flock 9

if [[ ! -x "${QEMU_SRC}/configure" ]]; then
    echo "missing QEMU source tree: ${QEMU_SRC}" >&2
    exit 2
fi

# The aggregate invokes this helper once per child gate. Avoid re-running the
# idempotent-looking sed/patch/configure sequence, since those commands still
# update QEMU source timestamps and can force a full Ninja rebuild.
INPUT_STAMP="${QEMU_BUILD}/.mips32_soc_ref_project_inputs.sha256"
project_inputs_hash() {
    sha256sum \
        "${ROOT_DIR}/scripts/qemu/build_mips32_soc_ref.sh" \
        "${ROOT_DIR}/scripts/qemu/mips32_soc_ref.c" \
        "${ROOT_DIR}/scripts/qemu/mips32_soc_core.xml" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-branch-likely-link.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-srs.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-align-r2.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-bitswap-r2.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-wsbw-r2.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-fpu-int32-indefinite.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips-fpe-sticky-flags.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips-fpe-double-underflow.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-prefx-no-fpu.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-lladdr-virtual.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-sc-consume-reservation.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-cop1x-memory-fields.patch" \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips-round-w-ties-away.patch" |
        sha256sum | awk '{print $1}'
}

PROJECT_INPUTS_HASH=$(project_inputs_hash)
if [[ -s "${INPUT_STAMP}" && -x "${QEMU_BUILD}/qemu-system-mipsel" ]] &&
   rg -q 'SOC_REF_BITSWAP_R2' "${QEMU_SRC}/target/mips/tcg/translate.c" &&
   rg -q 'SOC_REF_WSBW_R2' "${QEMU_SRC}/target/mips/tcg/translate.c" &&
   rg -q 'SOC_REF_ALIGN_R2' "${QEMU_SRC}/target/mips/tcg/translate.c" &&
   rg -q 'SOC_REF_PREFX_NO_FPU' "${QEMU_SRC}/target/mips/tcg/translate.c" &&
   rg -q 'SOC_REF_FPU_INT32_INDEFINITE' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c" &&
   rg -q 'SOC_REF_FPU_ROUND_W_TIES_AWAY' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c" &&
   rg -q 'SOC_REF_FPU_FPE_STICKY_FLAGS' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c" &&
   rg -q 'SOC_REF_LLADDR_VIRTUAL' "${QEMU_SRC}/target/mips/tcg/ldst_helper.c" &&
   rg -q 'SOC_REF_SC_CONSUMES_RESERVATION' "${QEMU_SRC}/target/mips/tcg/translate.c" &&
   [[ "$(<"${INPUT_STAMP}")" == "${PROJECT_INPUTS_HASH}" ]]; then
    echo "QEMU mips32-soc-ref build is up to date: ${QEMU_BUILD}/qemu-system-mipsel"
    exit 0
fi

copy_if_changed() {
    local source=$1
    local destination=$2
    if [[ ! -e "${destination}" ]] || ! cmp -s "${source}" "${destination}"; then
        install -m 0644 "${source}" "${destination}"
    fi
}

copy_if_changed "${ROOT_DIR}/scripts/qemu/mips32_soc_ref.c" \
    "${QEMU_SRC}/hw/mips/mips32_soc_ref.c"
copy_if_changed "${ROOT_DIR}/scripts/qemu/mips32_soc_core.xml" \
    "${QEMU_SRC}/gdb-xml/mips32_soc_core.xml"

if ! rg -q "mips32_soc_ref\.c" "${QEMU_SRC}/hw/mips/meson.build"; then
    sed -i "/if 'CONFIG_TCG' in config_all_accel/a\\mips_ss.add(files('mips32_soc_ref.c'))" \
        "${QEMU_SRC}/hw/mips/meson.build"
fi

if ! rg -q "mips32_soc_core.xml" "${QEMU_SRC}/configs/targets/mipsel-softmmu.mak"; then
    printf '\nTARGET_XML_FILES=gdb-xml/mips32_soc_core.xml\n' \
        >>"${QEMU_SRC}/configs/targets/mipsel-softmmu.mak"
fi

if ! rg -q 'gdb_core_xml_file = "mips32_soc_core.xml"' "${QEMU_SRC}/target/mips/cpu.c"; then
    sed -i '/cc->gdb_num_core_regs = 73;/a\    cc->gdb_core_xml_file = "mips32_soc_core.xml";\n    cc->gdb_num_core_regs = 77;' \
        "${QEMU_SRC}/target/mips/cpu.c"
    sed -i '/cc->gdb_num_core_regs = 73;/d' "${QEMU_SRC}/target/mips/cpu.c"
fi

# The project source tree tracks the target patch separately because upstream
# QEMU 9.2 does not publish a MIPS core XML feature list for plugin register
# access. Apply it idempotently with exact context rather than line ranges.
if ! rg -q 'case 73: return gdb_get_regl\(mem_buf, env->CP0_EPC\)' "${QEMU_SRC}/target/mips/gdbstub.c"; then
    sed -i '/^[[:space:]]*case 72:$/i\    case 73: return gdb_get_regl(mem_buf, env->CP0_EPC);\n    case 74: return gdb_get_regl(mem_buf, env->CP0_Index);\n    case 75: return gdb_get_regl(mem_buf, env->CP0_EntryHi);\n    case 76: return gdb_get_regl(mem_buf, env->CP0_PageMask);' \
        "${QEMU_SRC}/target/mips/gdbstub.c"
    sed -i '/^[[:space:]]*case 72: \/\* fp, ignored \*\/$/i\    case 73: env->CP0_EPC = tmp; break;\n    case 74: env->CP0_Index = tmp; break;\n    case 75: env->CP0_EntryHi = tmp; break;\n    case 76: env->CP0_PageMask = tmp; break;' \
        "${QEMU_SRC}/target/mips/gdbstub.c"
fi

if ! rg -q 'qemu_mips32_soc_ref_retire_tick' "${QEMU_SRC}/accel/tcg/cpu-exec.c"; then
    sed -i '/#include "internal-target.h"/a\
\
#ifndef CONFIG_USER_ONLY\
/* Project-local system-mode retire hook; absent machines are unaffected. */\
void qemu_mips32_soc_ref_retire_tick(CPUState *cpu) __attribute__((weak));\
#endif' "${QEMU_SRC}/accel/tcg/cpu-exec.c"
    sed -i '/tb = cpu_tb_exec(cpu, tb, tb_exit);/a\
#ifndef CONFIG_USER_ONLY\
    if (*tb_exit <= TB_EXIT_IDX1 && qemu_mips32_soc_ref_retire_tick) {\
        qemu_mips32_soc_ref_retire_tick(cpu);\
    }\
#endif' "${QEMU_SRC}/accel/tcg/cpu-exec.c"
fi

if ! rg -q 'qemu_mips32_soc_ref_wait' "${QEMU_SRC}/target/mips/tcg/exception.c"; then
    perl -0pi -e 's/(void helper_wait\(CPUMIPSState \*env\)\n\{\n    CPUState \*cs = env_cpu\(env\);\n)/$1\n    extern void qemu_mips32_soc_ref_wait(CPUMIPSState *env) __attribute__((weak));\n    extern bool qemu_mips32_soc_ref_irq_replay_active(void) __attribute__((weak));\n    if (qemu_mips32_soc_ref_wait) {\n        qemu_mips32_soc_ref_wait(env);\n    }\n/s' \
        "${QEMU_SRC}/target/mips/tcg/exception.c"
fi

if ! rg -q 'extern bool qemu_mips32_soc_ref_irq_replay_active\(void\)' \
        "${QEMU_SRC}/target/mips/tcg/exception.c"; then
    sed -i '/extern void qemu_mips32_soc_ref_wait/a\    extern bool qemu_mips32_soc_ref_irq_replay_active(void) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/exception.c"
fi
sed -i '/^[[:space:]]*cs->halted = 1;$/c\    cs->halted = !(qemu_mips32_soc_ref_irq_replay_active && qemu_mips32_soc_ref_irq_replay_active());' \
    "${QEMU_SRC}/target/mips/tcg/exception.c"

if ! rg -q 'qemu_mips32_soc_ref_irq_replay_active' "${QEMU_SRC}/hw/mips/mips_int.c"; then
    sed -i '/#include "kvm_mips.h"/a\
\
bool qemu_mips32_soc_ref_irq_replay_active(void) __attribute__((weak));' \
        "${QEMU_SRC}/hw/mips/mips_int.c"
    sed -i '/if (env->CP0_Cause \& CP0Ca_IP_mask) {/a\
        if (qemu_mips32_soc_ref_irq_replay_active &&\
            qemu_mips32_soc_ref_irq_replay_active()) {\
            return;\
        }' "${QEMU_SRC}/hw/mips/mips_int.c"
fi

if ! rg -q 'qemu_mips32_soc_ref_interrupt_fixup' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/#include "exec\/helper-proto.h"/a\
void qemu_mips32_soc_ref_interrupt_fixup(CPUMIPSState *env) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
    sed -i '/env->CP0_EPC = exception_resume_pc(env);/a\
            if (qemu_mips32_soc_ref_interrupt_fixup) {\
                qemu_mips32_soc_ref_interrupt_fixup(env);\
            }' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

if ! rg -q 'SOC_REF_INTERRUPT_BD_HOOK' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/void qemu_mips32_soc_ref_interrupt_fixup/a\bool qemu_mips32_soc_ref_interrupt_bd(void) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
    perl -0pi -e 's{(            if \(env->hflags & MIPS_HFLAG_BMASK\) \{\n                env->CP0_Cause \|= \(1U << CP0Ca_BD\);\n            \} else \{\n                env->CP0_Cause &= ~\(1U << CP0Ca_BD\);\n            \}\n)}{$1            /* SOC_REF_INTERRUPT_BD_HOOK */\n            if (qemu_mips32_soc_ref_interrupt_bd &&\n                qemu_mips32_soc_ref_interrupt_bd()) {\n                env->CP0_Cause |= (1U << CP0Ca_BD);\n            }\n}s' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi
if ! rg -q 'SOC_REF_INTERRUPT_FORCE_BD' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/void qemu_mips32_soc_ref_interrupt_fixup/a\bool qemu_mips32_soc_ref_interrupt_force_bd(void) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
    perl -0pi -e 's{(            if \(env->hflags & MIPS_HFLAG_BMASK\) \{\n                env->CP0_Cause \|= \(1U << CP0Ca_BD\);\n            \} else \{\n                env->CP0_Cause &= ~\(1U << CP0Ca_BD\);\n            \}\n)}{$1            if (cs->exception_index == EXCP_EXT_INTERRUPT &&\n                qemu_mips32_soc_ref_interrupt_force_bd &&\n                qemu_mips32_soc_ref_interrupt_force_bd()) {\n                env->CP0_Cause |= (1U << CP0Ca_BD);\n            } /* SOC_REF_INTERRUPT_FORCE_BD */\n}s' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi
# Normalize an interrupted, previously partially patched source tree to the
# single hook block above.  This repair is idempotent and runs before the
# marker check on subsequent invocations.
if rg -q 'qemu_mips32_soc_ref_interrupt_bd &&' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c" &&
   ! rg -q 'SOC_REF_INTERRUPT_BD_HOOK' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    perl -0pi -e 's{\n\s*if \(qemu_mips32_soc_ref_interrupt_bd &&\n\s*qemu_mips32_soc_ref_interrupt_bd\(\)\) \{\n\s*env->CP0_Cause \|= \(1U << CP0Ca_BD\);\n\s*\}\n}{}g' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

if ! rg -q 'qemu_mips32_soc_ref_bootrom_mmu_guest' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/#include "exec\/helper-proto.h"/a\bool qemu_mips32_soc_ref_bootrom_mmu_guest(void) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

# With BEV set, QEMU contributes the fixed BFC00200 base before `offset`.
# Boot-ROM MMU guests use refill offset zero; SRAM MMU guests use the RTL
# general handler at EBase+0x180.  Patch both TLBL/TLBS assignments, since
# QEMU's upstream MIPS32 path overwrites the initial default offset.
if ! rg -q 'SOC_REF_BOOTROM_TLB_VECTOR' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    perl -0pi -e 's/                offset = 0x000;\n/                offset = (qemu_mips32_soc_ref_bootrom_mmu_guest && qemu_mips32_soc_ref_bootrom_mmu_guest()) ? 0x000 : 0x180; \/\* SOC_REF_BOOTROM_TLB_VECTOR *\/\n/g' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

# QEMU 9.2 unconditionally writes the link register for BLTZALL/BGEZALL
# before resolving the likely condition. MIPS32 links only when taken.
if ! rg -q 'SOC_REF_FIX_BLIKELY_LINK' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    perl -0pi -e 's{(        case OPC_BGEZALL:\n            tcg_gen_setcondi_tl\(TCG_COND_GE, bcond, t0, 0\);)\n            blink = 31;\n            goto likely;}{$1\n            /* SOC_REF_FIX_BLIKELY_LINK: link only on the taken path. */\n            tcg_gen_movcond_tl(TCG_COND_NE, cpu_gpr[31], bcond,\n                               tcg_constant_tl(0),\n                               tcg_constant_tl(ctx->base.pc_next + 8),\n                               cpu_gpr[31]);\n            goto likely;}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    perl -0pi -e 's{(        case OPC_BLTZALL:\n            tcg_gen_setcondi_tl\(TCG_COND_LT, bcond, t0, 0\);)\n            blink = 31;\n        likely:}{$1\n            /* SOC_REF_FIX_BLIKELY_LINK: link only on the taken path. */\n            tcg_gen_movcond_tl(TCG_COND_NE, cpu_gpr[31], bcond,\n                               tcg_constant_tl(0),\n                               tcg_constant_tl(ctx->base.pc_next + 8),\n                               cpu_gpr[31]);\n        likely:}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi

if ! rg -q 'srs_gpr\[16\]\[32\]' "${QEMU_SRC}/target/mips/cpu.h"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-srs.patch"
fi

if ! rg -q 'SOC_REF_ALIGN_R2' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    perl -0pi -e 's{(    case OPC_BSHFL:\n        op2 = MASK_BSHFL\(ctx->opcode\);\n        switch \(op2\) \{\n        case OPC_ALIGN:\n        case OPC_ALIGN_1:\n        case OPC_ALIGN_2:\n        case OPC_ALIGN_3:\n)            check_insn\(ctx, ISA_MIPS_R6\);\n            decode_opc_special3_r6\(env, ctx\);}{$1            check_insn(ctx, ISA_MIPS_R2); /* SOC_REF_ALIGN_R2 */\n            gen_align(ctx, 32, rd, rs, rt, sa \& 3);}' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi

if ! rg -q 'SOC_REF_BITSWAP_R2' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    perl -0pi -e 's{case OPC_ALIGN:\n        case OPC_ALIGN_1:\n        case OPC_ALIGN_2:\n        case OPC_ALIGN_3:\n        case OPC_BITSWAP:\n            check_insn\(ctx, ISA_MIPS_R6\);\n            decode_opc_special3_r6\(env, ctx\);\n            break;}{case OPC_ALIGN:\n        case OPC_ALIGN_1:\n        case OPC_ALIGN_2:\n        case OPC_ALIGN_3:\n            check_insn(ctx, ISA_MIPS_R6);\n            decode_opc_special3_r6(env, ctx);\n            break;\n        case OPC_BITSWAP:\n            /* SOC_REF_BITSWAP_R2: legacy MIPS32 R2 encoding. */\n            check_insn(ctx, ISA_MIPS_R2);\n            gen_bitswap(ctx, op2, rd, rt);\n            break;}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    # ALIGN is applied first above, so a clean upstream tree reaches this
    # second shape instead of the original combined R6 ALIGN/BITSWAP case.
    perl -0pi -e 's{(        case OPC_ALIGN:\n        case OPC_ALIGN_1:\n        case OPC_ALIGN_2:\n        case OPC_ALIGN_3:\n            check_insn\(ctx, ISA_MIPS_R2\); /\* SOC_REF_ALIGN_R2 \*/\n            gen_align\(ctx, 32, rd, rs, rt, sa & 3\);\n            break;\n)        case OPC_BITSWAP:\n            check_insn\(ctx, ISA_MIPS_R6\);\n            decode_opc_special3_r6\(env, ctx\);\n            break;}{$1        case OPC_BITSWAP:\n            /* SOC_REF_BITSWAP_R2: legacy MIPS32 R2 encoding. */\n            check_insn(ctx, ISA_MIPS_R2);\n            gen_bitswap(ctx, op2, rd, rt);\n            break;}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi

if ! rg -q 'SOC_REF_WSBW_R2' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-wsbw-r2.patch"
    sed -i '/OPC_WSBW      =/a\    /* SOC_REF_WSBW_R2 */' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi

if ! rg -q 'SOC_REF_FPU_INT32_INDEFINITE' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"; then
    sed -i 's/^#define FP_TO_INT32_OVERFLOW 0x7fffffff$/\/\* SOC_REF_FPU_INT32_INDEFINITE: MIPS invalid W conversion result. \*\/\n#define FP_TO_INT32_OVERFLOW 0x80000000/' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"
fi

if ! rg -q 'SOC_REF_FPU_ROUND_W_TIES_AWAY' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"; then
    # The vendored QEMU tree is not a git checkout. Apply the small source
    # change by function body so this remains deterministic for extracted
    # release archives as well as git worktrees.
    sed -i '/uint32_t helper_float_round_w_d(CPUMIPSState \*env, uint64_t fdt0)/,/^}/ s/float_round_nearest_even/float_round_ties_away/' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"
    sed -i '/uint32_t helper_float_round_w_s(CPUMIPSState \*env, uint32_t fst0)/,/^}/ s/float_round_nearest_even/float_round_ties_away/' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"
    sed -i '/set_float_rounding_mode(float_round_ties_away,/a\    /* SOC_REF_FPU_ROUND_W_TIES_AWAY */' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"
fi
rg -q 'SOC_REF_FPU_ROUND_W_TIES_AWAY' "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"

if ! rg -Uq 'if \(GET_FP_ENABLE\(env->active_fpu.fcr31\) & mips_exception_flags\) \{\n            /\* SOC_REF_FPU_FPE_STICKY_FLAGS \*/' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips-fpe-sticky-flags.patch"
    sed -i '/if (GET_FP_ENABLE(env->active_fpu.fcr31) \& mips_exception_flags) {/a\
            /* SOC_REF_FPU_FPE_STICKY_FLAGS */\
            UPDATE_FP_FLAGS(env->active_fpu.fcr31, mips_exception_flags);' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"
fi

if ! rg -q 'SOC_REF_FPU_DOUBLE_UNDERFLOW' \
        "${QEMU_SRC}/target/mips/tcg/fpu_helper.c"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips-fpe-double-underflow.patch"
fi

if ! rg -q 'SOC_REF_PREFX_NO_FPU' "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-prefx-no-fpu.patch"
fi

if ! rg -q 'SOC_REF_LLADDR_VIRTUAL' \
        "${QEMU_SRC}/target/mips/tcg/ldst_helper.c"; then
    if ! rg -q 'qemu_mips32_soc_ref_lladdr_virtual' \
            "${QEMU_SRC}/target/mips/tcg/ldst_helper.c"; then
        sed -i '/#include "internal.h"/a\
bool qemu_mips32_soc_ref_lladdr_virtual(void) __attribute__((weak));' \
            "${QEMU_SRC}/target/mips/tcg/ldst_helper.c"
    fi
    perl -0pi -e 's{(    env->lladdr = arg;)}{    if (qemu_mips32_soc_ref_lladdr_virtual &&\\\n        qemu_mips32_soc_ref_lladdr_virtual()) {\\\n        /* RTL exposes the aligned virtual LL address through MFC0. */\\\n        env->CP0_LLAddr = (uint64_t)arg << env->CP0_LLAddr_shift;\\\n    } /* SOC_REF_LLADDR_VIRTUAL */\\\n$1}s' \
        "${QEMU_SRC}/target/mips/tcg/ldst_helper.c"
fi
rg -q 'SOC_REF_LLADDR_VIRTUAL' \
    "${QEMU_SRC}/target/mips/tcg/ldst_helper.c"

if ! rg -q 'SOC_REF_COP1X_MEMORY_FIELDS' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    git -C "${QEMU_SRC}" apply --no-index --recount \
        "${ROOT_DIR}/scripts/qemu/patches/qemu-9.2-mips32-cop1x-memory-fields.patch"
fi
rg -q 'SOC_REF_COP1X_MEMORY_FIELDS' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"

if ! rg -q 'SOC_REF_SC_CONSUMES_RESERVATION' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    perl -0pi -e 's{(    gen_store_gpr\(tcg_constant_tl\(0\), rt\);\n)(    tcg_gen_br\(done\);)}{$1    /* MIPS32 SoC contract: every completed SC attempt consumes LL state. */\n    tcg_gen_movi_tl(cpu_lladdr, -1); /* SOC_REF_SC_CONSUMES_RESERVATION */\n$2}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
    perl -0pi -e 's{(    gen_store_gpr\(t0, rt\);\n)(\n    gen_set_label\(done\);)}{$1    /* Successful and failed compare-exchange attempts both consume LL. */\n    tcg_gen_movi_tl(cpu_lladdr, -1); /* SOC_REF_SC_CONSUMES_RESERVATION */\n$2}s' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"
fi
rg -q 'SOC_REF_SC_CONSUMES_RESERVATION' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"

# Keep the opt-in custom-machine PREFX contract correct even when an older
# build tree contains the marker but not the final ISA check.
perl -0pi -e 's{(case OPC_PREFX:\n\s*(?:/\*[^\n]*\*/\n\s*)?)check_insn\(ctx, ISA_MIPS4 \| ISA_MIPS_R2\);}{$1check_insn(ctx, ISA_MIPS_R2);}s' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"
# Older partially patched trees can retain the inner case without the outer
# COP1-disabled dispatch. Add that dispatch idempotently before rebuilding.
if ! rg -q 'SOC_REF_PREFX_NO_FPU: PREFX is legal without COP1' \
        "${QEMU_SRC}/target/mips/tcg/translate.c"; then
    perl -0pi -e 's{(    case OPC_CP3:\n)(        if \(ctx->CP0_Config1 & \(1 << CP0C1_FP\)\) \{\n\s*check_cp1_enabled\(ctx\);\n\s*op1 = MASK_CP3\(ctx->opcode\);\n)}{$1        op1 = MASK_CP3(ctx->opcode);\n        /* SOC_REF_PREFX_NO_FPU: PREFX is legal without COP1. */\n        if (op1 == OPC_PREFX) {\n            check_insn(ctx, ISA_MIPS_R2);\n            break;\n        }\n$2}s' "${QEMU_SRC}/target/mips/tcg/translate.c"
fi

# Keep the SRS reference model aligned with the RTL nested-exception policy:
# only the outer exception changes CSS/PSS; an EXL-held nested fault preserves
# that context while still redirecting to the handler.
if ! rg -q 'SOC_REF_SRS_NESTED_POLICY' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/^[[:space:]]*mips_srs_exception_entry(env);$/d' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
    sed -i '/^[[:space:]]*mips_srs_exception_entry(env,/i\            /* SOC_REF_SRS_NESTED_POLICY */' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

# The RTL reference contract exposes 64 software-managed TLB entries, while
# the compact 24Kc model normally exposes only 16.  The backing QEMU TLB
# array is larger than both limits, so widen only the opt-in custom-machine
# MMU guest path.  Default QEMU CPU behavior remains unchanged.
if ! rg -q 'qemu_mips32_soc_ref_rtl_mmu_guest' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/#include "exec\/helper-proto.h"/a\bool qemu_mips32_soc_ref_rtl_mmu_guest(void) __attribute__((weak));' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi
if ! rg -q 'SOC_REF_SOFTWARE_TLB_64' "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"; then
    sed -i '/env->tlb->nb_tlb = 1 + ((def->CP0_Config1 >> CP0C1_MMU) \& 63);/c\    env->tlb->nb_tlb = (qemu_mips32_soc_ref_rtl_mmu_guest && qemu_mips32_soc_ref_rtl_mmu_guest()) ? 64 : 1 + ((def->CP0_Config1 >> CP0C1_MMU) \& 63); /* SOC_REF_SOFTWARE_TLB_64 */' \
        "${QEMU_SRC}/target/mips/tcg/sysemu/tlb_helper.c"
fi

sed -i '0,/^DEF_HELPER_1(soc_ref_retire_tick, void, env)$/!{/^DEF_HELPER_1(soc_ref_retire_tick, void, env)$/d;}' \
    "${QEMU_SRC}/target/mips/helper.h"
if rg -q '^DEF_HELPER_1\(soc_ref_retire_tick, void, env\)$' "${QEMU_SRC}/target/mips/helper.h"; then
    perl -0pi -e 's/^DEF_HELPER_1\(soc_ref_retire_tick, void, env\)$/#ifndef CONFIG_USER_ONLY\nDEF_HELPER_1(soc_ref_retire_tick, void, env)\n#endif/m' \
        "${QEMU_SRC}/target/mips/helper.h"
fi
if ! rg -Fq 'DEF_HELPER_1(soc_ref_retire_tick, void, env)' "${QEMU_SRC}/target/mips/helper.h"; then
    sed -i '/DEF_HELPER_1(raise_exception_debug, noreturn, env)/a\
\#ifndef CONFIG_USER_ONLY\
DEF_HELPER_1(soc_ref_retire_tick, void, env)\
\#endif' "${QEMU_SRC}/target/mips/helper.h"
fi

sed -i '/^[[:space:]]*gen_helper_soc_ref_retire_tick(tcg_env);$/d' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"

perl -0pi -e 's{^[[:space:]]*#ifndef CONFIG_USER_ONLY\n[[:space:]]*gen_helper_soc_ref_retire_tick\(tcg_env\);\n[[:space:]]*#endif\n}{}mg' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"
perl -0pi -e 's{(static void mips_tr_translate_insn.*?\n)([ ]{4}if \(ctx->hflags & MIPS_HFLAG_BMASK\))}{$1#ifndef CONFIG_USER_ONLY\n    gen_helper_soc_ref_retire_tick(tcg_env);\n#endif\n$2}s' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"

# Keep retire instrumentation after QEMU's branch-likely annul dispatch.
sed -i '/^[[:space:]]*gen_helper_soc_ref_retire_tick(tcg_env);$/d' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"
sed -i '/^[[:space:]]*if (is_slot) {/i\
#ifndef CONFIG_USER_ONLY\
    if ((ctx->hflags & MIPS_HFLAG_BMASK_BASE) == MIPS_HFLAG_BL) {\
        TCGLabel *soc_ref_skip_retire = gen_new_label();\
        tcg_gen_brcondi_tl(TCG_COND_EQ, bcond, 0, soc_ref_skip_retire);\
        gen_helper_soc_ref_retire_tick(tcg_env);\
        gen_set_label(soc_ref_skip_retire);\
    } else {\
        gen_helper_soc_ref_retire_tick(tcg_env);\
    }\
#endif' \
    "${QEMU_SRC}/target/mips/tcg/translate.c"

if [[ ! -f "${QEMU_BUILD}/build.ninja" ]]; then
    mkdir -p "${QEMU_BUILD}"
    (
        cd "${QEMU_BUILD}"
        ../configure \
            --target-list=mipsel-softmmu \
            --enable-plugins \
            --disable-werror \
            --enable-fdt=disabled
    )
fi

# TARGET_XML_FILES is consumed by configure, so reconfigure after applying the
# project-local MIPS GDB feature description.
( cd "${QEMU_BUILD}" && ../configure --target-list=mipsel-softmmu --enable-plugins --disable-werror --enable-fdt=disabled )

ninja -C "${QEMU_BUILD}" -j"${QEMU_BUILD_JOBS}" qemu-system-mipsel
test -x "${QEMU_BUILD}/qemu-system-mipsel"
printf '%s\n' "${PROJECT_INPUTS_HASH}" >"${INPUT_STAMP}"
echo "${QEMU_BUILD}/qemu-system-mipsel"
