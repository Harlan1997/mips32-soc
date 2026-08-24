#include <stdint.h>
#include "print.h"
#include "soc_addr.h"

static volatile uint32_t scratch[4];

int main(void) {
    uint32_t version = PERF_VERSION;
    uint32_t cycle_before = PERF_CYCLE_COUNT;
    uint32_t retire_before = PERF_RETIRE_COUNT;
    uint32_t i;
    uint32_t accumulator = 0;

    for (i = 0; i < 32; ++i) {
        scratch[i & 3] = i * 3U + 1U;
        accumulator += scratch[i & 3] ^ (i << 2);
    }

    uint32_t cycle_after = PERF_CYCLE_COUNT;
    uint32_t retire_after = PERF_RETIRE_COUNT;
    uint32_t failures = 0;
    if (version != 0x50430001U) failures |= 1U;
    if (cycle_after <= cycle_before) failures |= 2U;
    if (retire_after <= retire_before) failures |= 4U;
    if (accumulator == 0U) failures |= 8U;

    print_str("perf_cpu: version="); print_hex(version);
    print_str("perf_cpu: cycle_delta="); print_hex(cycle_after - cycle_before);
    print_str("perf_cpu: retire_delta="); print_hex(retire_after - retire_before);
    print_str("perf_cpu: icache_miss="); print_hex(PERF_ICACHE_MISS_COUNT);
    print_str("perf_cpu: dcache_miss="); print_hex(PERF_DCACHE_MISS_COUNT);
    print_str("perf_cpu: branch_mispredict="); print_hex(PERF_BRANCH_MISPREDICT);
    print_str("perf_cpu: mdu_stall="); print_hex(PERF_MDU_STALL_COUNT);

    if (failures == 0U) {
        print_str("perf_cpu: REGRESSION_TEST_SUCCESS\n");
        mailbox_exit();
    }
    print_str("perf_cpu: REGRESSION_TEST_FAIL\n");
    *MAILBOX_EXIT = 0xDEADDEADU;
    while (1) { }
    return 0;
}
