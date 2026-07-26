/* -----------------------------------------------------------------------------
 * isa_r2_sweep — isolated ISA R2 instruction sweep (Phase A coverage helper).
 *
 * Exercises MIPS32 R2 additions the base firmware doesn't reach: CLZ / CLO /
 * SEB / SEH / WSBH / ROTR / ROTRV / MOVN / MOVZ / BAL. Plus a static MFC0
 * of PRId / Config / Config1 / EBase to hit CP0 read paths.
 *
 * Terminates via mailbox exit; uses weak default exception handler.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

static uint32_t isa_r2_sweep(void) {
    uint32_t clz_r, clo_r, seb_r, seh_r, wsbh_r, rotr_r, rotrv_r;
    uint32_t movn_r, movz_r, bal_r;
    uint32_t prid_v, cfg0_v, cfg1_v, ebase_v;

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

    asm volatile(".set push; .set mips32r2; rotr %0, %1, 8; .set pop"
                 : "=r"(rotr_r) : "r"(0xAABBCCDDU));
    asm volatile(".set push; .set mips32r2; rotrv %0, %1, %2; .set pop"
                 : "=r"(rotrv_r) : "r"(0x11223344U), "r"(4U));

    /* MOVN / MOVZ */
    uint32_t movn_dst = 0xAAAA, movz_dst = 0xBBBB;
    asm volatile("movn %0, %1, %2" : "+r"(movn_dst) : "r"(0xCCCC), "r"(1));
    movn_r = movn_dst;
    asm volatile("movz %0, %1, %2" : "+r"(movz_dst) : "r"(0xDDDD), "r"(0));
    movz_r = movz_dst;

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

    /* Static CP0 reads */
    asm volatile("mfc0 %0, $15, 0" : "=r"(prid_v));
    asm volatile("mfc0 %0, $16, 0" : "=r"(cfg0_v));
    asm volatile("mfc0 %0, $16, 1" : "=r"(cfg1_v));
    asm volatile("mfc0 %0, $15, 1" : "=r"(ebase_v));

    return clz_r ^ clo_r ^ seb_r ^ seh_r ^ wsbh_r ^ rotr_r ^ rotrv_r
         ^ movn_r ^ movz_r ^ bal_r
         ^ prid_v ^ cfg0_v ^ cfg1_v ^ ebase_v;
}

int main(void) {
    print_str("isa_r2_sweep: ");
    print_hex(isa_r2_sweep());
    print_str("REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
