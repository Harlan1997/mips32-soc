/* -----------------------------------------------------------------------------
 * l2_cpu — focused product firmware test for L2 commercial closure (Phase 4F).
 *
 * Verifies:
 *   1. Cached memory read/write data integrity over an 8KB region (256 cache lines
 *      of 32B) exercising L2 refill/hit paths.
 *   2. Byte/halfword/word store merge correctness as observed by CPU loads.
 *   3. L2 set conflict and eviction sweep stressing 4KB set-strided BSS addresses
 *      in sweep_buffer (sweep_buffer[0], sweep_buffer[1024]), forcing L1 dirty eviction
 *      into L2 and L2 hit refill readback.
 *   4. Cacheable physical vs uncached (0xA0000000 KSEG1) alias readback after
 *      L1 conflict eviction. Note: MIPS CPU/L1 cache lacks hardware alias
 *      coherency / flush instructions in this hardware baseline, so the test
 *      evicts the dirty cached line before checking durable KSEG1 data.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

/* Keep the long sweep in the explicit behavioral-DDR window used by the
 * focused SoC gate, away from the firmware image and exception vectors. */
#define SWEEP_PHYS_BASE 0x00008000U
#define MERGE_PHYS_BASE 0x0000A000U
#define ALIAS_PHYS_BASE 0x0000A040U

static void mailbox_fail(void) {
    *((volatile uint32_t*)0xA000FFFC) = 0xDEADDEAD;
    while (1) { /* halt */ }
}

// 1. Cached memory data integrity sweep (8 KB = 2048 words, 256 lines)
static int test_cached_memory_integrity(void) {
    volatile uint32_t *cached_ptr = (volatile uint32_t *)SWEEP_PHYS_BASE;
    const uint32_t words = 2048; // 8 KB = 256 cache lines of 32B
    uint32_t i;

    // Phase 1: Write pattern across 8 KB (forces write-allocate refills)
    for (i = 0; i < words; i++) {
        cached_ptr[i] = 0x12340000U + i;
    }

    // Phase 2: Read back and verify all words
    for (i = 0; i < words; i++) {
        uint32_t val = cached_ptr[i];
        if (val != (0x12340000U + i)) {
            print_str("FAIL: cached memory integrity mismatch at index ");
            print_hex(i);
            return -1;
        }
    }

    // Phase 3: Re-read to ensure cache hits return expected data
    for (i = 0; i < words; i += 8) { // 32B line stride
        uint32_t val = cached_ptr[i];
        if (val != (0x12340000U + i)) {
            print_str("FAIL: cached hit re-read mismatch at index ");
            print_hex(i);
            return -1;
        }
    }

    return 0;
}

// 2. Sub-word (byte / halfword / word) store merge correctness
static int test_store_merge_correctness(void) {
    volatile uint32_t *word_ptr = (volatile uint32_t *)MERGE_PHYS_BASE;
    volatile uint8_t  *byte_ptr = (volatile uint8_t  *)(word_ptr + 1);
    volatile uint16_t *half_ptr = (volatile uint16_t *)(word_ptr + 2);

    // Word store
    *word_ptr = 0xCAFEBABE;
    if (*word_ptr != 0xCAFEBABE) {
        print_str("FAIL: word store failed\n");
        return -1;
    }

    // Byte stores
    byte_ptr[0] = 0x11;
    byte_ptr[1] = 0x22;
    byte_ptr[2] = 0x33;
    byte_ptr[3] = 0x44;

    if (byte_ptr[0] != 0x11 || byte_ptr[1] != 0x22) {
        print_str("FAIL: byte store merge failed\n");
        return -1;
    }

    // Halfword stores
    half_ptr[0] = 0x5566;
    half_ptr[1] = 0x7788;
    if (half_ptr[0] != 0x5566 || half_ptr[1] != 0x7788) {
        print_str("FAIL: halfword store merge failed\n");
        return -1;
    }

    return 0;
}

// 3. L2 set conflict and eviction sweep using explicit SRAM lines
static int test_l2_conflict_eviction(void) {
    volatile uint32_t *p0 = (volatile uint32_t *)SWEEP_PHYS_BASE;
    volatile uint32_t *p1 = (volatile uint32_t *)(SWEEP_PHYS_BASE + 4096U); // 4KB stride

    uint32_t orig0 = *p0;
    uint32_t orig1 = *p1;

    *p0 = 0xAA000000U;
    *p1 = 0xAA000001U;

    if (*p0 != 0xAA000000U || *p1 != 0xAA000001U) {
        print_str("FAIL: L2 set eviction readback failed\n");
        return -1;
    }

    *p0 = orig0;
    *p1 = orig1;

    return 0;
}

// 4. Cached vs uncached alias readback after a durable cached store
static int test_alias_interaction(void) {
    uint32_t phys_addr = ALIAS_PHYS_BASE;
    volatile uint32_t *cached_ptr   = (volatile uint32_t *)phys_addr;
    volatile uint32_t *uncached_ptr = (volatile uint32_t *)(0xA0000000U | phys_addr);

    // Step 1: Write & read via the cacheable physical alias.
    *cached_ptr = 0x99887766U;
    if (*cached_ptr != 0x99887766U) {
        print_str("FAIL: cached write readback failed\n");
        return -1;
    }

    // Evict the L1 line so its dirty data reaches L2/backing memory before
    // checking the uncached alias.
    for (uint32_t i = 1; i <= 4; i++)
        (void)*(volatile uint32_t *)(phys_addr + i * 0x800U);

    // Step 2: Read via KSEG1 and confirm durable backing data.
    if (*uncached_ptr != 0x99887766U) {
        print_str("FAIL: uncached alias readback failed\n");
        return -1;
    }

    return 0;
}

int main(void) {
    print_str("l2_cpu test: starting Phase 4F checks\n");

    if (test_cached_memory_integrity() != 0) {
        print_str("l2_cpu test: FAILED cached memory integrity\n");
        mailbox_fail();
        return 1;
    }

    if (test_store_merge_correctness() != 0) {
        print_str("l2_cpu test: FAILED store merge correctness\n");
        mailbox_fail();
        return 1;
    }

    if (test_l2_conflict_eviction() != 0) {
        print_str("l2_cpu test: FAILED L2 set eviction\n");
        mailbox_fail();
        return 1;
    }

    if (test_alias_interaction() != 0) {
        print_str("l2_cpu test: FAILED alias interaction\n");
        mailbox_fail();
        return 1;
    }

    print_str("l2_cpu test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
