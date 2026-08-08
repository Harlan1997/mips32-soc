/* Focused CPU/L1/L2/DDR transaction evidence for the L2 integration. */
#include <stdint.h>
#include "soc_addr.h"

#define DATA_BASE 0x00008000U

static void fail(void) {
    *MAILBOX_EXIT = 0xDEADDEADU;
    while (1) { }
}

static uint32_t load_word(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

static void store_word(uint32_t addr, uint32_t value) {
    *(volatile uint32_t *)addr = value;
}

int main(void) {
    volatile uint32_t *a = (volatile uint32_t *)DATA_BASE;
    uint32_t value;
    uint32_t i;

    /* Cold line read, followed by an L1 hit. */
    value = load_word((uint32_t)a);
    if (load_word((uint32_t)a) != value)
        fail();

    /* Four 2KB-spaced lines conflict in the 4-way L1.  The final A access
     * must miss in L1 but hit in L2, so it must not create another DDR AR. */
    for (i = 1; i <= 4; i++)
        (void)load_word(DATA_BASE + i * 0x800U);
    if (load_word(DATA_BASE) != value)
        fail();

    /* Make A dirty in L1, then evict it through the same L1 conflict set.
     * WB consequently receives a dirty line; WT forwards the store directly. */
    store_word(DATA_BASE, 0xC0DE4000U);
    if (load_word(DATA_BASE) != 0xC0DE4000U)
        fail();
    for (i = 1; i <= 4; i++)
        (void)load_word(DATA_BASE + i * 0x800U);

    /* KSEG1 read bypasses L1 and exercises the L2-visible post-eviction data. */
    if (load_word(0xA0008000U) != 0xC0DE4000U)
        fail();
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    while (1) { }
    return 0;
}
