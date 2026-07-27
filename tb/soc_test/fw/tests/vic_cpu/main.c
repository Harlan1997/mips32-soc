/* -----------------------------------------------------------------------------
 * vic_cpu — product firmware gate for VIC commercial closure (Phase 4D).
 *
 * Verifies APB-visible VIC behavior through the SoC path:
 *   1. Reset / default register reads
 *   2. Enable set / clear & legacy mask/status reads
 *   3. Soft interrupt source acceptance via VEC_ID, ACTIVE, RUNNING_PRIO, and ACK
 *   4. Priority arbitration and lower-ID tie-break behavior
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define REG32(addr) (*(volatile uint32_t*)(addr))

#define VIC_BASE             0x40004000
#define VIC_INTR_RAW         (VIC_BASE + 0x000)
#define VIC_INTR_ENABLE      (VIC_BASE + 0x004)
#define VIC_INTR_MASKED      (VIC_BASE + 0x008)
#define VIC_ENABLE_SET       (VIC_BASE + 0x00C)
#define VIC_ENABLE_CLR       (VIC_BASE + 0x010)
#define VIC_TYPE             (VIC_BASE + 0x014)
#define VIC_POLARITY         (VIC_BASE + 0x018)
#define VIC_SOFT             (VIC_BASE + 0x01C)
#define VIC_SOFT_CLR         (VIC_BASE + 0x020)
#define VIC_PRIO(n)          (VIC_BASE + 0x100 + ((n) << 2))
#define VIC_VEC_ID           (VIC_BASE + 0x200)
#define VIC_VEC_IPRIO        (VIC_BASE + 0x204)
#define VIC_ACK              (VIC_BASE + 0x208)
#define VIC_ACTIVE           (VIC_BASE + 0x20C)
#define VIC_RUNNING_PRIO     (VIC_BASE + 0x210)

static void mailbox_fail(void) {
    *((volatile uint32_t*)0xA000FFFC) = 0xDEADDEAD;
    while (1) { /* halt */ }
}

static int test_reset_defaults(void) {
    if (REG32(VIC_INTR_RAW) != 0) {
        print_str("FAIL: VIC_INTR_RAW reset != 0\n");
        return -1;
    }
    if (REG32(VIC_INTR_ENABLE) != 0) {
        print_str("FAIL: VIC_INTR_ENABLE reset != 0\n");
        return -1;
    }
    if (REG32(VIC_INTR_MASKED) != 0) {
        print_str("FAIL: VIC_INTR_MASKED reset != 0\n");
        return -1;
    }
    if (REG32(VIC_VEC_ID) != 0xFF) {
        print_str("FAIL: VIC_VEC_ID reset != 0xFF\n");
        return -1;
    }
    if (REG32(VIC_VEC_IPRIO) != 0) {
        print_str("FAIL: VIC_VEC_IPRIO reset != 0\n");
        return -1;
    }
    if (REG32(VIC_ACTIVE) != 0) {
        print_str("FAIL: VIC_ACTIVE reset != 0\n");
        return -1;
    }
    if (REG32(VIC_RUNNING_PRIO) != 0) {
        print_str("FAIL: VIC_RUNNING_PRIO reset != 0\n");
        return -1;
    }
    return 0;
}

static int test_enable_set_clr(void) {
    REG32(VIC_INTR_ENABLE) = 0x0000000F;
    if (REG32(VIC_INTR_ENABLE) != 0x0000000F) {
        print_str("FAIL: ENABLE direct write failed\n");
        return -1;
    }

    REG32(VIC_ENABLE_SET) = 0x000000F0;
    if (REG32(VIC_INTR_ENABLE) != 0x000000FF) {
        print_str("FAIL: ENABLE_SET failed\n");
        return -1;
    }

    REG32(VIC_ENABLE_CLR) = 0x0000000F;
    if (REG32(VIC_INTR_ENABLE) != 0x000000F0) {
        print_str("FAIL: ENABLE_CLR failed\n");
        return -1;
    }

    REG32(VIC_INTR_ENABLE) = 0x0;
    return 0;
}

static int test_soft_irq_accept_nesting(void) {
    // Set PRIO[4] = 7, PRIO[5] = 9
    REG32(VIC_PRIO(4)) = 7;
    REG32(VIC_PRIO(5)) = 9;

    REG32(VIC_INTR_ENABLE) = (1 << 4) | (1 << 5);
    REG32(VIC_SOFT) = (1 << 4) | (1 << 5);

    // VEC_ID read should return 5 (higher priority 9) and accept it
    uint32_t vec = REG32(VIC_VEC_ID);
    if (vec != 5) {
        print_str("FAIL: soft IRQ VEC_ID expected 5, got "); print_hex(vec); print_str("\n");
        return -1;
    }
    if (REG32(VIC_VEC_IPRIO) != 9) {
        print_str("FAIL: VEC_IPRIO expected 9\n");
        return -1;
    }
    if (REG32(VIC_ACTIVE) != (1 << 5)) {
        print_str("FAIL: ACTIVE expected 0x20\n");
        return -1;
    }
    if (REG32(VIC_RUNNING_PRIO) != 9) {
        print_str("FAIL: RUNNING_PRIO expected 9\n");
        return -1;
    }

    // ACK source 5
    REG32(VIC_ACK) = (1 << 5);
    REG32(VIC_SOFT_CLR) = (1 << 5);

    // Now VEC_ID read should return 4
    vec = REG32(VIC_VEC_ID);
    if (vec != 4) {
        print_str("FAIL: post-ACK VEC_ID expected 4, got "); print_hex(vec); print_str("\n");
        return -1;
    }
    if (REG32(VIC_ACTIVE) != (1 << 4)) {
        print_str("FAIL: ACTIVE expected 0x10 post-ACK 5\n");
        return -1;
    }
    if (REG32(VIC_RUNNING_PRIO) != 7) {
        print_str("FAIL: RUNNING_PRIO expected 7 post-ACK 5\n");
        return -1;
    }

    // ACK source 4
    REG32(VIC_ACK) = (1 << 4);
    REG32(VIC_SOFT_CLR) = (1 << 4);

    if (REG32(VIC_ACTIVE) != 0) {
        print_str("FAIL: ACTIVE expected 0 post-ACK all\n");
        return -1;
    }
    if (REG32(VIC_RUNNING_PRIO) != 0) {
        print_str("FAIL: RUNNING_PRIO expected 0 post-ACK all\n");
        return -1;
    }

    REG32(VIC_INTR_ENABLE) = 0;
    return 0;
}

static int test_tie_break(void) {
    REG32(VIC_PRIO(6)) = 5;
    REG32(VIC_PRIO(7)) = 5;

    REG32(VIC_INTR_ENABLE) = (1 << 6) | (1 << 7);
    REG32(VIC_SOFT) = (1 << 6) | (1 << 7);

    uint32_t vec = REG32(VIC_VEC_ID);
    if (vec != 6) {
        print_str("FAIL: tie break VEC_ID expected 6 (lower ID wins), got "); print_hex(vec); print_str("\n");
        return -1;
    }

    REG32(VIC_ACK) = (1 << 6);
    REG32(VIC_SOFT_CLR) = (1 << 6);

    vec = REG32(VIC_VEC_ID);
    if (vec != 7) {
        print_str("FAIL: post ACK 6 VEC_ID expected 7, got "); print_hex(vec); print_str("\n");
        return -1;
    }

    REG32(VIC_ACK) = (1 << 7);
    REG32(VIC_SOFT_CLR) = (1 << 7);
    REG32(VIC_INTR_ENABLE) = 0;
    return 0;
}

int main(void) {
    print_str("vic_cpu test: starting Phase 4D checks\n");

    if (test_reset_defaults() != 0) {
        print_str("vic_cpu test: FAILED reset defaults\n");
        mailbox_fail();
        return 1;
    }

    if (test_enable_set_clr() != 0) {
        print_str("vic_cpu test: FAILED enable set/clr\n");
        mailbox_fail();
        return 1;
    }

    if (test_soft_irq_accept_nesting() != 0) {
        print_str("vic_cpu test: FAILED soft irq accept & nesting\n");
        mailbox_fail();
        return 1;
    }

    if (test_tie_break() != 0) {
        print_str("vic_cpu test: FAILED tie break\n");
        mailbox_fail();
        return 1;
    }

    print_str("vic_cpu test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
