/* -----------------------------------------------------------------------------
 * mdu_cpu — focused firmware test for CPU-visible MDU R2 instructions (Phase 4B).
 *
 * Exercises MADD, MADDU, MSUB, MSUBU, and MUL rd, rs, rt via GCC inline assembly.
 * Verifies accumulation into HI/LO and GPR destination writeback for MUL.
 *
 * Terminates via mailbox exit.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

static void mailbox_fail(void) {
    *((volatile uint32_t*)0xA000FFFC) = 0xDEADDEAD;
    while (1) { }
}

static void set_hilo(uint32_t hi, uint32_t lo) {
    asm volatile("mthi %0" :: "r"(hi));
    asm volatile("mtlo %0" :: "r"(lo));
}

static void get_hilo(uint32_t *hi, uint32_t *lo) {
    asm volatile("mfhi %0" : "=r"(*hi));
    asm volatile("mflo %0" : "=r"(*lo));
}

static int test_madd_maddu_msub_msubu(void) {
    uint32_t hi = 0, lo = 0;

    // 1. MADD (signed accumulate)
    set_hilo(0, 100);
    int32_t rs_s = -5, rt_s = 6;
    asm volatile(".set push; .set mips32r2; madd %0, %1; .set pop" :: "r"(rs_s), "r"(rt_s));
    get_hilo(&hi, &lo);
    if (hi != 0 || lo != 70) {
        print_str("FAIL: MADD got HI="); print_hex(hi); print_str(" LO="); print_hex(lo); print_str("\n");
        return -1;
    }

    // 2. MADDU (unsigned accumulate)
    set_hilo(0, 100);
    uint32_t rs_u = 5, rt_u = 6;
    asm volatile(".set push; .set mips32r2; maddu %0, %1; .set pop" :: "r"(rs_u), "r"(rt_u));
    get_hilo(&hi, &lo);
    if (hi != 0 || lo != 130) {
        print_str("FAIL: MADDU got HI="); print_hex(hi); print_str(" LO="); print_hex(lo); print_str("\n");
        return -1;
    }

    // 3. MSUB (signed subtract accumulate)
    set_hilo(0, 100);
    asm volatile(".set push; .set mips32r2; msub %0, %1; .set pop" :: "r"(rs_s), "r"(rt_s));
    get_hilo(&hi, &lo);
    if (hi != 0 || lo != 130) {
        print_str("FAIL: MSUB got HI="); print_hex(hi); print_str(" LO="); print_hex(lo); print_str("\n");
        return -1;
    }

    // 4. MSUBU (unsigned subtract accumulate)
    set_hilo(0, 100);
    rs_u = 2; rt_u = 10;
    asm volatile(".set push; .set mips32r2; msubu %0, %1; .set pop" :: "r"(rs_u), "r"(rt_u));
    get_hilo(&hi, &lo);
    if (hi != 0 || lo != 80) {
        print_str("FAIL: MSUBU got HI="); print_hex(hi); print_str(" LO="); print_hex(lo); print_str("\n");
        return -1;
    }

    return 0;
}

static int test_mul(void) {
    uint32_t rd = 0;

    // 1. Positive MUL: 7 * 8 = 56
    uint32_t a = 7, b = 8;
    asm volatile(".set push; .set mips32r2; mul %0, %1, %2; .set pop" : "=r"(rd) : "r"(a), "r"(b));
    if (rd != 56) {
        print_str("FAIL: MUL pos got "); print_hex(rd); print_str("\n");
        return -1;
    }

    // 2. Negative MUL: -5 * 6 = -30 (0xFFFFFFE2)
    int32_t sa = -5, sb = 6;
    asm volatile(".set push; .set mips32r2; mul %0, %1, %2; .set pop" : "=r"(rd) : "r"(sa), "r"(sb));
    if (rd != (uint32_t)(-30)) {
        print_str("FAIL: MUL neg got "); print_hex(rd); print_str("\n");
        return -1;
    }

    // 3. Large MUL: 0x12345678 * 2 = 0x2468ACF0
    a = 0x12345678; b = 2;
    asm volatile(".set push; .set mips32r2; mul %0, %1, %2; .set pop" : "=r"(rd) : "r"(a), "r"(b));
    if (rd != 0x2468ACF0) {
        print_str("FAIL: MUL large got "); print_hex(rd); print_str("\n");
        return -1;
    }

    return 0;
}

static int test_div(void) {
    int32_t quotient = 0;
    int32_t remainder = 0;
    int32_t dividend = 100;
    int32_t divisor = 3;

    asm volatile(".set push\n"
                 ".set noreorder\n"
                 ".set nomacro\n"
                 "div $0, %2, %3\n"
                 "mflo %0\n"
                 "mfhi %1\n"
                 ".set pop"
                 : "=&r"(quotient), "=&r"(remainder)
                 : "r"(dividend), "r"(divisor));
    if (quotient != 33 || remainder != 1) {
        print_str("FAIL: DIV 100/3 got LO="); print_hex((uint32_t)quotient);
        print_str(" HI="); print_hex((uint32_t)remainder); print_str("\n");
        return -1;
    }

    dividend = -100;
    asm volatile(".set push\n"
                 ".set noreorder\n"
                 ".set nomacro\n"
                 "div $0, %2, %3\n"
                 "mflo %0\n"
                 "mfhi %1\n"
                 ".set pop"
                 : "=&r"(quotient), "=&r"(remainder)
                 : "r"(dividend), "r"(divisor));
    if (quotient != -33 || remainder != -1) {
        print_str("FAIL: DIV -100/3 got LO="); print_hex((uint32_t)quotient);
        print_str(" HI="); print_hex((uint32_t)remainder); print_str("\n");
        return -1;
    }

    dividend = 100;
    divisor = -3;
    asm volatile(".set push\n"
                 ".set noreorder\n"
                 ".set nomacro\n"
                 "div $0, %2, %3\n"
                 "mflo %0\n"
                 "mfhi %1\n"
                 ".set pop"
                 : "=&r"(quotient), "=&r"(remainder)
                 : "r"(dividend), "r"(divisor));
    if (quotient != -33 || remainder != 1) {
        print_str("FAIL: DIV 100/-3 got LO="); print_hex((uint32_t)quotient);
        print_str(" HI="); print_hex((uint32_t)remainder); print_str("\n");
        return -1;
    }

    return 0;
}

int main(void) {
    print_str("mdu_cpu test: starting\n");
    if (test_madd_maddu_msub_msubu() != 0) {
        print_str("mdu_cpu test: FAILED accumulate tests\n");
        mailbox_fail();
        return 1;
    }
    if (test_mul() != 0) {
        print_str("mdu_cpu test: FAILED mul tests\n");
        mailbox_fail();
        return 1;
    }
    if (test_div() != 0) {
        print_str("mdu_cpu test: FAILED divide tests\n");
        mailbox_fail();
        return 1;
    }
    print_str("mdu_cpu test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
