/* -----------------------------------------------------------------------------
 * dma_cpu — focused product firmware test for DMA commercial closure (Phase 4C).
 *
 * Verifies:
 *   1. Direct v1 alias copy and self-clearing EN / W1C DONE
 *   2. v2 direct copy with STATUS register polling
 *   3. Zero-length direct transfer completion
 *   4. W1C re-arm sequence
 *   5. DMA interrupt generation visible via PIC status/active registers
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define REG32(addr) (*(volatile uint32_t*)(addr))

#define DMA_BASE            0x40003000

#define DMA_V1_SRC          (DMA_BASE + 0x00)
#define DMA_V1_DST          (DMA_BASE + 0x04)
#define DMA_V1_LEN          (DMA_BASE + 0x08)
#define DMA_V1_CTRL         (DMA_BASE + 0x0C)

#define DMA_V2_CH0_CTRL     (DMA_BASE + 0x40)
#define DMA_V2_CH0_SRC      (DMA_BASE + 0x44)
#define DMA_V2_CH0_DST      (DMA_BASE + 0x48)
#define DMA_V2_CH0_LEN      (DMA_BASE + 0x4C)
#define DMA_V2_CH0_STATUS   (DMA_BASE + 0x54)

#define DMA_V2_CH1_CTRL     (DMA_BASE + 0x80)
#define DMA_V2_CH1_SRC      (DMA_BASE + 0x84)
#define DMA_V2_CH1_DST      (DMA_BASE + 0x88)
#define DMA_V2_CH1_LEN      (DMA_BASE + 0x8C)
#define DMA_V2_CH1_STATUS   (DMA_BASE + 0x94)
#define DMA_V2_CH2_CTRL     (DMA_BASE + 0xC0)
#define DMA_V2_CH2_DESC     (DMA_BASE + 0xD0)
#define DMA_V2_CH2_STATUS   (DMA_BASE + 0xD4)

#define DMA_GLOBAL_CTRL     (DMA_BASE + 0x100)
#define DMA_IRQ_STATUS      (DMA_BASE + 0x104)

#define PIC_REG_STATUS      0x40004000
#define PIC_REG_MASK        0x40004004
#define PIC_REG_ACTIVE      0x40004008

static uint32_t src_buffer[8] __attribute__((aligned(4)));
static uint32_t dst_buffer[8] __attribute__((aligned(4)));
static uint32_t sg_desc[8] __attribute__((aligned(16)));

static void mailbox_fail(void) {
    *((volatile uint32_t*)0xA000FFFC) = 0xDEADDEAD;
    while (1) { /* halt */ }
}

static int test_v1_alias_copy(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    int i;
    for (i = 0; i < 8; i++) {
        src[i] = 0x12345678 + i;
        dst[i] = 0x0;
    }

    REG32(DMA_V1_SRC)  = (uint32_t)src;
    REG32(DMA_V1_DST)  = (uint32_t)dst;
    REG32(DMA_V1_LEN)  = 32;
    REG32(DMA_V1_CTRL) = 0x1; // start

    int timeout = 10000;
    while (timeout > 0) {
        uint32_t ctrl = REG32(DMA_V1_CTRL);
        if ((ctrl & 0x4) && !(ctrl & 0x1)) break;
        timeout--;
    }
    if (timeout == 0) {
        print_str("FAIL: v1 alias copy timed out\n");
        return -1;
    }

    for (i = 0; i < 8; i++) {
        if (dst[i] != src[i]) {
            print_str("FAIL: v1 copy mismatch at word "); print_hex(i); print_str("\n");
            return -1;
        }
    }

    // W1C DONE
    REG32(DMA_V1_CTRL) = 0x4;
    if (REG32(DMA_V1_CTRL) & 0x4) {
        print_str("FAIL: v1 copy W1C DONE failed\n");
        return -1;
    }

    return 0;
}

static int test_v2_direct_copy(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    int i;
    for (i = 0; i < 8; i++) {
        src[i] = 0xABCD0000 + i;
        dst[i] = 0x0;
    }

    REG32(DMA_V2_CH0_SRC)  = (uint32_t)src;
    REG32(DMA_V2_CH0_DST)  = (uint32_t)dst;
    REG32(DMA_V2_CH0_LEN)  = 32;
    REG32(DMA_V2_CH0_CTRL) = 0x1; // EN=1

    int timeout = 10000;
    while (timeout > 0) {
        uint32_t status = REG32(DMA_V2_CH0_STATUS);
        if (status & 0x2) break; // DONE
        timeout--;
    }
    if (timeout == 0) {
        print_str("FAIL: v2 copy timed out\n");
        return -1;
    }

    uint32_t st = REG32(DMA_V2_CH0_STATUS);
    if ((st & 0x7) != 0x2) { // BUSY=0, DONE=1, ERR=0
        print_str("FAIL: v2 copy status incorrect: "); print_hex(st); print_str("\n");
        return -1;
    }

    for (i = 0; i < 8; i++) {
        if (dst[i] != src[i]) {
            print_str("FAIL: v2 copy mismatch at word "); print_hex(i); print_str("\n");
            return -1;
        }
    }

    // W1C DONE
    REG32(DMA_V2_CH0_CTRL) = (1 << 3);
    if (REG32(DMA_V2_CH0_STATUS) & 0x2) {
        print_str("FAIL: v2 copy W1C DONE failed\n");
        return -1;
    }

    return 0;
}

static int test_zero_length_completion(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    REG32(DMA_V2_CH1_SRC)  = (uint32_t)src;
    REG32(DMA_V2_CH1_DST)  = (uint32_t)dst;
    REG32(DMA_V2_CH1_LEN)  = 0;
    REG32(DMA_V2_CH1_CTRL) = 0x1; // EN=1

    int timeout = 100;
    while (timeout > 0) {
        uint32_t status = REG32(DMA_V2_CH1_STATUS);
        if (status & 0x2) break;
        timeout--;
    }
    if (timeout == 0) {
        print_str("FAIL: zero-length transfer timed out\n");
        return -1;
    }

    uint32_t st = REG32(DMA_V2_CH1_STATUS);
    if ((st & 0x7) != 0x2) {
        print_str("FAIL: zero-length status incorrect: "); print_hex(st); print_str("\n");
        return -1;
    }

    REG32(DMA_V2_CH1_CTRL) = (1 << 3);
    return 0;
}

static int test_sg_copy(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    volatile uint32_t *desc = (volatile uint32_t*)((uint32_t)sg_desc | 0xA0000000);
    int i;

    for (i = 0; i < 8; i++) {
        src[i] = 0x5A5A0000 + i;
        dst[i] = 0;
    }
    /* Two 16-byte descriptors, linked by NEXT; cover all 8 words. */
    desc[0] = (uint32_t)src;
    desc[1] = (uint32_t)dst;
    desc[2] = 16;
    desc[3] = (uint32_t)(desc + 4);
    desc[4] = (uint32_t)(src + 4);
    desc[5] = (uint32_t)(dst + 4);
    desc[6] = 16;
    desc[7] = 0;

    REG32(DMA_V2_CH2_DESC) = (uint32_t)desc;
    REG32(DMA_V2_CH2_CTRL) = 0x3; /* EN=1, SG_MODE=1 */
    int timeout = 20000;
    while (timeout > 0) {
        if (REG32(DMA_V2_CH2_STATUS) & 0x2) break;
        timeout--;
    }
    if (timeout == 0) {
        print_str("FAIL: SG transfer timed out\n");
        return -1;
    }
    for (i = 0; i < 8; i++) {
        if (dst[i] != src[i]) {
            print_str("FAIL: SG copy mismatch at word "); print_hex(i); print_str("\n");
            return -1;
        }
    }
    if (REG32(DMA_V2_CH2_STATUS) & 0x1c) {
        print_str("FAIL: SG status error\n");
        return -1;
    }
    REG32(DMA_V2_CH2_CTRL) = (1 << 3);
    return 0;
}

static int test_w1c_rearm(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    // 1st transfer
    REG32(DMA_V2_CH0_SRC)  = (uint32_t)src;
    REG32(DMA_V2_CH0_DST)  = (uint32_t)dst;
    REG32(DMA_V2_CH0_LEN)  = 16;
    REG32(DMA_V2_CH0_CTRL) = 0x1;

    while (!(REG32(DMA_V2_CH0_STATUS) & 0x2));
    REG32(DMA_V2_CH0_CTRL) = (1 << 3); // W1C DONE
    if (REG32(DMA_V2_CH0_STATUS) & 0x2) {
        print_str("FAIL: rearm 1st W1C failed\n");
        return -1;
    }

    // 2nd transfer re-arm
    REG32(DMA_V2_CH0_CTRL) = 0x1;
    while (!(REG32(DMA_V2_CH0_STATUS) & 0x2));
    REG32(DMA_V2_CH0_CTRL) = (1 << 3);
    if (REG32(DMA_V2_CH0_STATUS) & 0x2) {
        print_str("FAIL: rearm 2nd W1C failed\n");
        return -1;
    }

    return 0;
}

static int test_pic_interrupt_path(void) {
    volatile uint32_t *src = (volatile uint32_t*)((uint32_t)src_buffer | 0xA0000000);
    volatile uint32_t *dst = (volatile uint32_t*)((uint32_t)dst_buffer | 0xA0000000);
    // Enable PIC mask bit 3 for DMA
    REG32(PIC_REG_MASK) = (1 << 3);

    // Program ch0 with INT_EN=1 (CTRL = 0x5)
    REG32(DMA_V2_CH0_SRC)  = (uint32_t)src;
    REG32(DMA_V2_CH0_DST)  = (uint32_t)dst;
    REG32(DMA_V2_CH0_LEN)  = 16;
    REG32(DMA_V2_CH0_CTRL) = 0x5; // EN=1, INT_EN=1

    int timeout = 10000;
    while (timeout > 0) {
        if (REG32(DMA_V2_CH0_STATUS) & 0x2) break;
        timeout--;
    }

    if (!(REG32(PIC_REG_STATUS) & (1 << 3))) {
        print_str("FAIL: PIC_STATUS bit 3 not set on DMA completion\n");
        return -1;
    }
    if (!(REG32(PIC_REG_ACTIVE) & (1 << 3))) {
        print_str("FAIL: PIC_ACTIVE bit 3 not set on DMA completion\n");
        return -1;
    }

    // W1C DONE on DMA
    REG32(DMA_V2_CH0_CTRL) = (1 << 3);

    if (REG32(PIC_REG_STATUS) & (1 << 3)) {
        print_str("FAIL: PIC_STATUS bit 3 not cleared after DMA W1C\n");
        return -1;
    }

    // Restore PIC_MASK
    REG32(PIC_REG_MASK) = 0x0;
    return 0;
}

int main(void) {
    print_str("dma_cpu test: starting Phase 4C checks\n");

    if (test_v1_alias_copy() != 0) {
        print_str("dma_cpu test: FAILED v1 alias copy\n");
        mailbox_fail();
        return 1;
    }

    if (test_v2_direct_copy() != 0) {
        print_str("dma_cpu test: FAILED v2 direct copy\n");
        mailbox_fail();
        return 1;
    }

    if (test_zero_length_completion() != 0) {
        print_str("dma_cpu test: FAILED zero-length completion\n");
        mailbox_fail();
        return 1;
    }

    if (test_sg_copy() != 0) {
        print_str("dma_cpu test: FAILED SG copy\n");
        mailbox_fail();
        return 1;
    }

    if (test_w1c_rearm() != 0) {
        print_str("dma_cpu test: FAILED W1C rearm\n");
        mailbox_fail();
        return 1;
    }

    if (test_pic_interrupt_path() != 0) {
        print_str("dma_cpu test: FAILED PIC interrupt path\n");
        mailbox_fail();
        return 1;
    }

    print_str("dma_cpu test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
