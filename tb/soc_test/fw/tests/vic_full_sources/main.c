#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define APB32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define VIC_BASE       0x40004000U
#define VIC_ENABLE     APB32(VIC_BASE + 0x004)
#define VIC_MASKED     APB32(VIC_BASE + 0x008)
#define VIC_ENABLE_SET APB32(VIC_BASE + 0x00c)
#define VIC_ENABLE_CLR APB32(VIC_BASE + 0x010)
#define VIC_SOFT       APB32(VIC_BASE + 0x01c)
#define VIC_SOFT_CLR   APB32(VIC_BASE + 0x020)
#define VIC_PRIO(n)    APB32(VIC_BASE + 0x100U + ((uint32_t)(n) * 4U))
#define VIC_VEC_ID     APB32(VIC_BASE + 0x200)
#define VIC_VEC_PRIO   APB32(VIC_BASE + 0x204)
#define VIC_ACK        APB32(VIC_BASE + 0x208)
#define VIC_ACTIVE     APB32(VIC_BASE + 0x20c)
#define VIC_RUNNING    APB32(VIC_BASE + 0x210)

static int fail(const char *what, uint32_t got, uint32_t want)
{
    print_str("VIC_FULL_SOURCES_FAIL ");
    print_str(what);
    print_str(" got=");
    print_hex(got);
    print_str(" want=");
    print_hex(want);
    print_str("\n");
    return 1;
}

static int check(uint32_t got, uint32_t want, const char *what)
{
    return got == want ? 0 : fail(what, got, want);
}

int main(void)
{
    uint32_t i;

    /* Start from a known state and enable every architectural source. */
    VIC_SOFT_CLR = 0xffffffffU;
    VIC_ACK = 0xffffffffU;
    VIC_ENABLE = 0;
    VIC_ENABLE_SET = 0xffffffffU;
    if (check(VIC_ENABLE, 0xffffffffU, "enable")) return 1;

    /* Directed priority stress: source 12 wins, then lower-ID source 3
     * wins a tie against source 7. */
    for (i = 0; i < 32; ++i)
        VIC_PRIO(i) = 4;
    VIC_PRIO(3) = 9;
    VIC_PRIO(7) = 9;
    VIC_PRIO(12) = 15;
    VIC_SOFT = (1U << 3) | (1U << 7) | (1U << 12);
    if (check(VIC_MASKED, (1U << 3) | (1U << 7) | (1U << 12), "masked")) return 1;
    if (check(VIC_VEC_ID, 12, "highest-priority-id")) return 1;
    if (check(VIC_VEC_PRIO, 15, "highest-priority-value")) return 1;
    if (check(VIC_ACTIVE, 1U << 12, "active-after-accept")) return 1;
    if (check(VIC_RUNNING, 15, "running-priority")) return 1;

    VIC_ACK = 1U << 12;
    if (check(VIC_VEC_ID, 3, "tie-lower-id")) return 1;
    if (check(VIC_ACTIVE, 1U << 3, "tie-active")) return 1;
    VIC_ACK = 1U << 3;

    /* All 32 sources are exercised in the same-priority order.  The
     * architectural tie-break is deterministic: lowest source ID first. */
    for (i = 0; i < 32; ++i)
        VIC_PRIO(i) = 4;
    VIC_SOFT = 0xffffffffU;
    if (check(VIC_MASKED, 0xffffffffU, "all-source-masked")) return 1;
    for (i = 0; i < 32; ++i) {
        if (check(VIC_VEC_ID, i, "all-source-order")) return 1;
        if (check(VIC_ACTIVE, 1U << i, "all-source-active")) return 1;
        if (check(VIC_RUNNING, 4, "all-source-running-prio")) return 1;
        VIC_ACK = 1U << i;
    }
    if (check(VIC_MASKED, 0, "all-source-drained")) return 1;
    if (check(VIC_ACTIVE, 0, "active-cleared")) return 1;

    /* W1C and enable-clear semantics are part of the same source-width
     * contract, including the top source bit. */
    VIC_SOFT = (1U << 31);
    VIC_ENABLE_CLR = (1U << 31);
    if (check(VIC_MASKED, 0, "masked-after-disable")) return 1;
    VIC_SOFT_CLR = (1U << 31);
    VIC_ENABLE_SET = (1U << 31);
    if (check(VIC_ENABLE, 0xffffffffU, "enable-top-source")) return 1;

    print_str("VIC_FULL_SOURCES_PASS sources=32 tie=lower-id\n");
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    return 0;
}
