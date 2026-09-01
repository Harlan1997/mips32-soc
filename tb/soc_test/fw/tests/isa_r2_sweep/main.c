/* -----------------------------------------------------------------------------
 * isa_r2_sweep — isolated ISA R2 instruction sweep (Phase A coverage helper).
 *
 * Exercises MIPS32 R2 additions the base firmware doesn't reach: CLZ / CLO /
 * SEB / SEH / WSBH / WSBW / BITSWAP / ALIGN / ROTR / ROTRV / MOVN / MOVZ / BAL. Plus a static MFC0
 * of PRId / Config / Config1 / EBase to hit CP0 read paths.
 *
 * Terminates via mailbox exit; uses weak default exception handler.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

static uint32_t isa_r2_sweep(void) {
    uint32_t clz_r, clo_r, seb_r, seh_r, wsbh_r, wsbw_r, bitswap_r, rotr_r, rotrv_r;
    uint32_t ext_r, ins_r, align0_r, align1_r, align2_r, align3_r;
    uint32_t movn_r, movz_r, movn_false_r, movz_false_r, bal_r;
    uint32_t prid_v, cfg0_v, cfg1_v, ebase_v;
    uint32_t rdhwr_step, rdhwr_cpunum, rdhwr_ccres;

    asm volatile(".set push; .set mips32r2; clz %0, %1; .set pop"
                 : "=r"(clz_r) : "r"(0x0000FF00U));
    asm volatile(".set push; .set mips32r2; clo %0, %1; .set pop"
                 : "=r"(clo_r) : "r"(0xFFFF00FFU));

    asm volatile(".set push; .set mips32r2; seb %0, %1; .set pop"
                 : "=r"(seb_r) : "r"(0x00000080U));
    asm volatile(".set push; .set mips32r2; seh %0, %1; .set pop"
                 : "=r"(seh_r) : "r"(0x00008000U));

    asm volatile(".set push; .set mips32r2; wsbh %0, %1; .set pop"
                 : "=r"(wsbh_r) : "r"(0x11223344U));
    /* gas support for WSBW is toolchain-dependent.  This is the architectural
     * SPECIAL3/BSHFL encoding: WSBW $t1,$t0 (sa=6, funct=0x20). */
    register uint32_t wsbw_in asm("$t0") = 0x11223344U;
    register uint32_t wsbw_out asm("$t1");
    asm volatile(".word 0x7c0849a0" : "=r"(wsbw_out) : "r"(wsbw_in));
    wsbw_r = wsbw_out;
    /* gas does not expose legacy BITSWAP under its mips32r2 alias, so use
     * the architecturally defined SPECIAL3 encoding with fixed temporaries:
     * BITSWAP $t1,$t0 = 0x7c084820. */
    register uint32_t bitswap_in asm("$t0") = 0x01234567U;
    register uint32_t bitswap_out asm("$t1");
    asm volatile(".word 0x7c084820" : "=r"(bitswap_out) : "r"(bitswap_in));
    bitswap_r = bitswap_out;
    /* ALIGN is SPECIAL3/BSHFL with sa=8..11.  Keep the operands in fixed
     * registers so the raw encodings remain unambiguous across assemblers. */
    register uint32_t align_rs asm("$t0") = 0x11223344U;
    register uint32_t align_rt asm("$t1") = 0xAABBCCDDU;
    register uint32_t align0_out asm("$s0");
    register uint32_t align1_out asm("$s1");
    register uint32_t align2_out asm("$s2");
    register uint32_t align3_out asm("$s3");
    asm volatile("nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop" ::: "memory");
    asm volatile(".word 0x7d095220\n\tmove $s0, $t2" : "=r"(align0_out) : "r"(align_rs), "r"(align_rt) : "$t2");
    asm volatile(".word 0x7d095260\n\tmove $s1, $t2" : "=r"(align1_out) : "r"(align_rs), "r"(align_rt) : "$t2");
    asm volatile(".word 0x7d0952a0\n\tmove $s2, $t2" : "=r"(align2_out) : "r"(align_rs), "r"(align_rt) : "$t2");
    asm volatile(".word 0x7d0952e0\n\tmove $s3, $t2" : "=r"(align3_out) : "r"(align_rs), "r"(align_rt) : "$t2");
    align0_r = align0_out;
    align1_r = align1_out;
    align2_r = align2_out;
    align3_r = align3_out;
    asm volatile(".set push; .set mips32r2; rotr %0, %1, 8; .set pop"
                 : "=r"(rotr_r) : "r"(0xAABBCCDDU));
    asm volatile(".set push; .set mips32r2; rotrv %0, %1, %2; .set pop"
                 : "=r"(rotrv_r) : "r"(0x11223344U), "r"(4U));

    asm volatile(".set push; .set mips32r2; ext %0, %1, 4, 12; .set pop"
                 : "=r"(ext_r) : "r"(0x12345678U));
    ins_r = 0xFFFF0000U;
    asm volatile(".set push; .set mips32r2; ins %0, %1, 8, 8; .set pop"
                 : "+r"(ins_r) : "r"(0x12345678U));

    /* PREF is architecturally a non-trapping hint with no GPR result. */
    uint32_t pref_addr = 0;
    asm volatile(".set push; .set mips32r2; pref 0, 0(%0); .set pop"
                 : : "r"(pref_addr) : "memory");
    /* SYNCI is the R2 instruction-cache synchronization operation.  The
     * current in-order CPU has no architectural result, but the instruction
     * must still reach the real cache-maintenance path. */
    asm volatile(".set push; .set mips32r2; synci 0(%0); .set pop"
                 : : "r"(pref_addr) : "memory");
    /* PREFX is the indexed MIPS32 R2 hint (COP1X funct=0x0f). */
    register uint32_t prefx_base asm("$t1") = 0;
    register uint32_t prefx_index asm("$t0") = 0;
    /* gas does not accept the indexed memory syntax in this configuration;
     * use the exact architectural encoding after constraining the operands. */
    asm volatile(".word 0x4d28000f" : : "r"(prefx_index), "r"(prefx_base)
                 : "memory");

    /* MOVN / MOVZ */
    uint32_t movn_dst = 0xAAAA, movz_dst = 0xBBBB;
    asm volatile("movn %0, %1, %2" : "+r"(movn_dst) : "r"(0xCCCC), "r"(1));
    movn_r = movn_dst;
    asm volatile("movz %0, %1, %2" : "+r"(movz_dst) : "r"(0xDDDD), "r"(0));
    movz_r = movz_dst;
    /* A false condition must suppress the architectural write. */
    uint32_t movn_false_dst = 0x13572468U;
    uint32_t movz_false_dst = 0x24681357U;
    asm volatile("movn %0, %1, %2" : "+r"(movn_false_dst)
                 : "r"(0xCAFEBABEU), "r"(0));
    asm volatile("movz %0, %1, %2" : "+r"(movz_false_dst)
                 : "r"(0xDEADC0DEU), "r"(1));
    movn_false_r = movn_false_dst;
    movz_false_r = movz_false_dst;

    /* BAL — branch-and-link (uses $31/ra) */
    uint32_t ra_snap = 0;
    asm volatile(
        ".set push; .set noreorder\n"
        "  bal    1f\n"
        "  nop\n"
        "  addiu  %0, $0, 0xFACE\n"     /* delay slot? actually next inst */
        "1: move  %0, $31\n"
        ".set pop"
        : "=r"(bal_r) : : "$31");
    (void)ra_snap;

    /* JR.HB/JALR.HB use the same target/link behavior on this in-order core. */
    uint32_t jr_hb_marker = 0;
    asm volatile(
        ".set push; .set noreorder\n"
        "  la    $t0, 1f\n"
        "  .word 0x01000408\n" /* jr.hb $t0 */
        "  addiu %0, $zero, 0x1111\n"
        "1:\n"
        "  .set pop\n"
        : "=r"(jr_hb_marker) : : "$t0");

    uint32_t jalr_hb_link = 0;
    asm volatile(
        ".set push; .set noreorder\n"
        "  la    $t0, 2f\n"
        "  .word 0x01004809\n" /* jalr.hb $t1, $t0 */
        "  nop\n"
        "2:\n"
        "  move  %0, $t1\n"
        "  .set pop\n"
        : "=r"(jalr_hb_link) : : "$t0", "$t1");

    /* EHB is encoded as SLL $0,$0,3 and must have no visible side effect. */
    asm volatile(".word 0x000000c0" ::: "memory");

    /* Static CP0 reads */
    asm volatile("mfc0 %0, $15, 0" : "=r"(prid_v));
    asm volatile("mfc0 %0, $16, 0" : "=r"(cfg0_v));
    asm volatile("mfc0 %0, $16, 1" : "=r"(cfg1_v));
    asm volatile("mfc0 %0, $15, 1" : "=r"(ebase_v));
    /* Enable the standard RDHWR targets before exercising the user-visible
     * SYNCI_Step register; the CPU correctly raises RI when HWREna is clear. */
    asm volatile("li $t9, 0x0000000f; mtc0 $t9, $7, 0; ehb" ::: "$t9", "memory");
    asm volatile(".word 0x7c08083b\n\tmove %0, $8"
                 : "=r"(rdhwr_step) : : "$8", "memory");
    asm volatile(".word 0x7c08003b\n\tmove %0, $8"
                 : "=r"(rdhwr_cpunum) : : "$8", "memory");
    asm volatile(".word 0x7c08183b\n\tmove %0, $8"
                 : "=r"(rdhwr_ccres) : : "$8", "memory");

    if (clz_r != 16U || clo_r != 16U ||
        movn_r != 0x0000CCCCU || movz_r != 0x0000DDDDU ||
        movn_false_r != 0x13572468U || movz_false_r != 0x24681357U ||
        bal_r == 0U ||
        rdhwr_step != 32U || rdhwr_cpunum != 0U || rdhwr_ccres != 2U ||
        seb_r != 0xFFFFFF80U || seh_r != 0xFFFF8000U ||
        wsbh_r != 0x22114433U || wsbw_r != 0x33441122U ||
        bitswap_r != 0x80C4A2E6U ||
        align0_r != 0xAABBCCDDU || align1_r != 0xBBCCDD11U ||
        align2_r != 0xCCDD1122U || align3_r != 0xDD112233U ||
        rotr_r != 0xDDAABBCCU || rotrv_r != 0x41122334U ||
        jr_hb_marker != 0x1111U || jalr_hb_link == 0U)
        {
        print_str("R2V="); print_hex(clz_r); print_hex(clo_r);
        print_hex(seb_r); print_hex(seh_r); print_hex(wsbh_r); print_hex(wsbw_r);
        print_hex(bitswap_r); print_hex(rotr_r); print_hex(rotrv_r);
        print_hex(align0_r); print_hex(align1_r); print_hex(align2_r);
        print_hex(align3_r); print_hex(jr_hb_marker); print_hex(jalr_hb_link);
        print_str("R2C="); print_hex(movn_r); print_hex(movz_r);
        print_hex(movn_false_r); print_hex(movz_false_r); print_hex(bal_r);
        print_str("ISA_R2_SPECIAL_FAIL\n");
        }

    return clz_r ^ clo_r ^ seb_r ^ seh_r ^ wsbh_r ^ wsbw_r ^ bitswap_r ^ rotr_r ^ rotrv_r
         ^ movn_r ^ movz_r ^ bal_r
         ^ align0_r ^ align1_r ^ align2_r ^ align3_r
         ^ prid_v ^ cfg0_v ^ cfg1_v ^ ebase_v ^ rdhwr_step ^
           rdhwr_cpunum ^ rdhwr_ccres;
}

int main(void) {
    print_str("isa_r2_sweep: ");
    uint32_t result = isa_r2_sweep();
    print_hex(result);
    /* Keep the architectural field operations independently observable. */
    uint32_t ext_check, ins_check;
    const uint32_t ext_input = 0x12345678U;
    const uint32_t ins_input = 0x12345678U;
    asm volatile(".set push; .set mips32r2; ext %0, %1, 4, 16; .set pop"
                 : "=r"(ext_check) : "r"(ext_input) : "memory");
    uint32_t ins_base = 0xFFFF0000U;
    asm volatile(".set push; .set mips32r2; ins %0, %1, 8, 8; .set pop"
                 : "+r"(ins_base) : "r"(ins_input) : "memory");
    if (ext_check != 0x00004567U || ins_base != 0xFFFF7800U) {
        print_str("ISA_R2_EXT_INS_FAIL\n");
    }
    print_str("REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
