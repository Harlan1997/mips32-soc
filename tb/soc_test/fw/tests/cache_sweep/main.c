/* -----------------------------------------------------------------------------
 * cache_sweep — isolated D-cache miss/hit/eviction + uncached alias exercise.
 *
 * Scratches a 4 KB region larger than any single cache set to force refills,
 * evictions, byte/half strobe combos, and uncached-alias (kseg1) crossovers.
 * Terminates via mailbox exit.
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

static uint32_t cache_sweep(void) {
    volatile uint32_t *scratch  = (volatile uint32_t *)0x00008000U;
    volatile uint32_t *uncached = (volatile uint32_t *)0xA0008000U;
    const uint32_t N = 1024;
    uint32_t sum = 0;

    /* Phase 1 — cached write walk */
    for (uint32_t i = 0; i < N; i++) {
        scratch[i] = i * 0x01010101U;
    }
    /* Phase 2 — cached read line-stride */
    for (uint32_t i = 0; i < N; i += 8) {
        sum ^= scratch[i];
    }
    /* Phase 3 — stride to force conflict eviction */
    for (uint32_t i = 0; i < N; i += 65) {
        sum ^= scratch[i];
        scratch[i] = sum;
    }
    /* Phase 4 — uncached alias */
    for (uint32_t i = 0; i < 16; i++) {
        uncached[i] = i ^ 0xA5A5A5A5U;
    }
    for (uint32_t i = 0; i < 16; i++) {
        sum ^= uncached[i];
    }
    /* Phase 5 — alternate cached/uncached */
    for (uint32_t i = 0; i < 8; i++) {
        scratch [i * 8] = i;
        sum ^= uncached[i * 8];
        uncached[i * 8] = i * 2;
        sum ^= scratch [i * 8];
    }
    /* Phase 6 — byte / half strobe */
    volatile uint8_t  *b = (volatile uint8_t  *)scratch;
    volatile uint16_t *h = (volatile uint16_t *)scratch;
    for (uint32_t i = 0; i < 16; i++) {
        b[i] = (uint8_t) (0x11U * i); sum ^= b[i];
        h[i] = (uint16_t)(0x2222U * i); sum ^= h[i];
    }
    return sum;
}

int main(void) {
    print_str("cache_sweep: ");
    print_hex(cache_sweep());
    print_str("REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
