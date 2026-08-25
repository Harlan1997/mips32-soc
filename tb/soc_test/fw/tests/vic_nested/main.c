#include <stdint.h>
#include "print.h"
#include "soc_addr.h"

#define REG32(a) (*(volatile uint32_t *)(a))
#define VIC_BASE 0x40004000u
#define VIC_ENABLE (VIC_BASE + 0x004u)
#define VIC_SOFT (VIC_BASE + 0x01Cu)
#define VIC_SOFT_CLR (VIC_BASE + 0x020u)
#define VIC_PRIO(n) (VIC_BASE + 0x100u + ((n) << 2))
#define VIC_VEC_ID (VIC_BASE + 0x200u)
#define VIC_ACTIVE (VIC_BASE + 0x20Cu)
#define VIC_ACK (VIC_BASE + 0x208u)

static volatile uint32_t phase;
static volatile uint32_t nested_count;
static volatile uint32_t sequence[4];
static volatile uint32_t handler_timeout;
static volatile uint32_t saved_epc[4];

/* The generic exception entry saves caller-saved GPRs and is deliberately
 * re-entrant: each nested exception allocates another frame on the SRAM
 * stack. The handler owns EXL/IE only for the short nesting window. */
void c_interrupt_handler(void)
{
    uint32_t cause, status, vec, epc;
    __asm__ volatile("mfc0 %0, $13" : "=r"(cause));
    if (((cause >> 2) & 0x1fu) != 0u) return;

    vec = REG32(VIC_VEC_ID);
    if (phase == 0u && vec == 9u) {
        sequence[0] = vec;
        phase = 1u;

        /* CP0 has one EPC register. Save this frame's return PC before
         * enabling nested delivery; each nested entry overwrites EPC. */
        __asm__ volatile("mfc0 %0, $14" : "=r"(epc));
        saved_epc[0] = epc;

        /* Accept source 9, then permit a higher-priority source to preempt
         * this handler. EXL is cleared explicitly; ERET will clear it again
         * when the nested frame returns. */
        __asm__ volatile("mfc0 %0, $12" : "=r"(status));
        status = (status | 1u) & ~2u;
        __asm__ volatile("mtc0 %0, $12\n\tnop\n\tnop" :: "r"(status));
        REG32(VIC_SOFT) = (1u << 8);
        while (nested_count < 1u && handler_timeout++ < 20000u) {
            __asm__ volatile("nop");
        }
        __asm__ volatile("mtc0 %0, $14\n\tnop\n\tnop" :: "r"(saved_epc[0]));
        REG32(VIC_ACK) = (1u << 9);
        REG32(VIC_SOFT_CLR) = (1u << 9);
        phase = 4u;
        return;
    }

    if (phase == 1u && vec == 8u) {
        sequence[1] = vec;
        __asm__ volatile("mfc0 %0, $14" : "=r"(epc));
        saved_epc[1] = epc;
        phase = 2u;
        __asm__ volatile("mfc0 %0, $12" : "=r"(status));
        status = (status | 1u) & ~2u;
        __asm__ volatile("mtc0 %0, $12\n\tnop\n\tnop" :: "r"(status));
        REG32(VIC_SOFT) = (1u << 7);
        while (nested_count < 2u && handler_timeout++ < 20000u) {
            __asm__ volatile("nop");
        }
        __asm__ volatile("mtc0 %0, $14\n\tnop\n\tnop" :: "r"(saved_epc[1]));
        REG32(VIC_ACK) = (1u << 8);
        REG32(VIC_SOFT_CLR) = (1u << 8);
        return;
    }

    if (phase == 2u && vec == 7u) {
        sequence[2] = vec;
        __asm__ volatile("mfc0 %0, $14" : "=r"(epc));
        saved_epc[2] = epc;
        phase = 3u;
        __asm__ volatile("mfc0 %0, $12" : "=r"(status));
        status = (status | 1u) & ~2u;
        __asm__ volatile("mtc0 %0, $12\n\tnop\n\tnop" :: "r"(status));
        REG32(VIC_SOFT) = (1u << 6);
        while (nested_count < 3u && handler_timeout++ < 20000u) {
            __asm__ volatile("nop");
        }
        __asm__ volatile("mtc0 %0, $14\n\tnop\n\tnop" :: "r"(saved_epc[2]));
        REG32(VIC_ACK) = (1u << 7);
        REG32(VIC_SOFT_CLR) = (1u << 7);
        return;
    }

    if (phase == 3u && vec == 6u) {
        sequence[3] = vec;
        nested_count = 3u;
        __asm__ volatile("mfc0 %0, $14" : "=r"(epc));
        saved_epc[3] = epc;
        __asm__ volatile("mtc0 %0, $14\n\tnop\n\tnop" :: "r"(saved_epc[3]));
        REG32(VIC_ACK) = (1u << 6);
        REG32(VIC_SOFT_CLR) = (1u << 6);
        return;
    }
}

static void fail(uint32_t code)
{
    print_str("vic_nested: FAIL ");
    print_hex(code);
    *MAILBOX_EXIT = 0xDEADDEADu;
    while (1) { }
}

int main(void)
{
    uint32_t status = 0x00000401u; /* IE + CP0 IM2, the SoC VIC input */

    REG32(VIC_PRIO(9)) = 4u;
    REG32(VIC_PRIO(8)) = 8u;
    REG32(VIC_PRIO(7)) = 12u;
    REG32(VIC_PRIO(6)) = 15u;
    REG32(VIC_ENABLE) = (1u << 6) | (1u << 7) | (1u << 8) | (1u << 9);
    REG32(VIC_SOFT) = (1u << 9);
    __asm__ volatile("mtc0 %0, $12\n\tnop\n\tnop" :: "r"(status));

    while (phase != 4u && handler_timeout++ < 50000u) {
        __asm__ volatile("nop");
    }
    __asm__ volatile("mtc0 %0, $12\n\tnop\n\tnop" :: "r"(0u));

    if (phase != 4u || nested_count != 3u || sequence[0] != 9u ||
        sequence[1] != 8u || sequence[2] != 7u || sequence[3] != 6u ||
        REG32(VIC_ACTIVE) != 0u) {
        fail((phase << 24) | (nested_count << 16) |
             (sequence[0] << 12) | (sequence[1] << 8) |
             (sequence[2] << 4) | sequence[3]);
    }
    print_str("vic_nested: sequence 9->8->7->6 reverse-ACK PASS\n");
    print_str("vic_nested: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
