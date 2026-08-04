/* -----------------------------------------------------------------------------
 * cp0_sweep — isolated CP0 MFC0 sub-select decode exercise.
 *
 * Read-only MFC0 across PRId / BadVAddr / Random / Context / EBase /
 * Config[0..3]. Writes only Compare + ErrorEPC with immediate restore.
 * Includes the UserLocal/HWREna path used by the RDHWR TLS contract.
 *
 * Now safe to isolate here because this firmware doesn't run alongside
 * peripheral tests — the timing-race pattern that broke signoff #8 does
 * not apply.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

static uint32_t cp0_sweep(void) {
    uint32_t v = 0, tmp;
    uint32_t save_compare;

    asm volatile("mfc0 %0, $11, 0" : "=r"(save_compare));

    asm volatile("mfc0 %0, $15, 0" : "=r"(tmp)); v ^= tmp;   /* PRId */
    asm volatile("mfc0 %0, $8,  0" : "=r"(tmp)); v ^= tmp;   /* BadVAddr */
    asm volatile("mfc0 %0, $1,  0" : "=r"(tmp)); v ^= tmp;   /* Random */
    asm volatile("mfc0 %0, $4,  0" : "=r"(tmp)); v ^= tmp;   /* Context */
    asm volatile(".set push; .set mips32r2; mfc0 %0, $15, 1; .set pop"
                 : "=r"(tmp)); v ^= tmp;                     /* EBase */
    asm volatile(".set push; .set mips32r2; mfc0 %0, $16, 0; .set pop"
                 : "=r"(tmp)); v ^= tmp;                     /* Config */
    asm volatile(".set push; .set mips32r2; mfc0 %0, $16, 1; .set pop"
                 : "=r"(tmp)); v ^= tmp;                     /* Config1 */
    asm volatile(".set push; .set mips32r2; mfc0 %0, $16, 2; .set pop"
                 : "=r"(tmp)); v ^= tmp;                     /* Config2 */
    asm volatile(".set push; .set mips32r2; mfc0 %0, $16, 3; .set pop"
                 : "=r"(tmp)); v ^= tmp;                     /* Config3 */

    /* ErrorEPC poke + restore */
    asm volatile("mtc0 %0, $30, 0" :: "r"(0xABCD1234U));
    asm volatile("mfc0 %0, $30, 0" : "=r"(tmp)); v ^= tmp;
    asm volatile("mtc0 %0, $30, 0" :: "r"(0));

    /* Compare short-value poke + restore */
    asm volatile("mtc0 %0, $11, 0" :: "r"(0x0000FFFFU));
    asm volatile("mfc0 %0, $11, 0" : "=r"(tmp)); v ^= tmp;
    asm volatile("mtc0 %0, $11, 0" :: "r"(save_compare));

    /* Kernel establishes a thread pointer and enables user RDHWR $29.
     * The explicit word keeps this test independent of assembler RDHWR aliases:
     * SPECIAL3 rs=3, rt=$8, rd=$29, funct=0x3b. */
    {
        uint32_t userlocal = 0x81234567U;
        uint32_t hwrena = 0x20000000U;
        uint32_t tls_read;
        asm volatile("mtc0 %0, $4, 2\n\t"
                     "mtc0 %1, $7, 0\n\t"
                     "ehb\n\t"
                     :: "r"(userlocal), "r"(hwrena));
        asm volatile(".word 0x7c68e83b\n\t"
                     "move %0, $8\n\t"
                     : "=r"(tls_read) : : "$8");
        if (tls_read != userlocal) {
            print_str("FAIL: RDHWR UserLocal got ");
            print_hex(tls_read);
            print_str(" expected ");
            print_hex(userlocal);
            print_str("\n");
            return 0;
        }
    }

    return v;
}

int main(void) {
    print_str("cp0_sweep: ");
    print_hex(cp0_sweep());
    print_str("REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
