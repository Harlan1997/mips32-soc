#include <stdint.h>
#include "print.h"
#include "soc_addr.h"

/* This is a repeatable microarchitectural observation workload, not a
 * CoreMark, Dhrystone, or STREAM implementation. Keep each case bounded and
 * independent so counter deltas can be compared across RTL configurations. */
static volatile uint32_t working_set[64];

static uint32_t counter_delta(volatile uint32_t *counter, uint32_t before) {
    return *counter - before;
}

static void report_case(const char *name, uint32_t cycles, uint32_t retires,
                        uint32_t ic_miss, uint32_t dc_miss,
                        uint32_t branch_miss, uint32_t mdu_stall,
                        uint32_t checksum) {
    print_str("perf_workloads: "); print_str(name); print_str(" cycles=");
    print_hex(cycles); print_str(" retires="); print_hex(retires);
    print_str(" icache_miss="); print_hex(ic_miss);
    print_str(" dcache_miss="); print_hex(dc_miss);
    print_str(" branch_mispredict="); print_hex(branch_miss);
    print_str(" mdu_stall="); print_hex(mdu_stall);
    print_str(" checksum="); print_hex(checksum); print_str("\n");
}

static void run_case(const char *name, uint32_t seed, uint32_t mode) {
    uint32_t c0 = PERF_CYCLE_COUNT;
    uint32_t r0 = PERF_RETIRE_COUNT;
    uint32_t i0 = PERF_ICACHE_MISS_COUNT;
    uint32_t d0 = PERF_DCACHE_MISS_COUNT;
    uint32_t b0 = PERF_BRANCH_MISPREDICT;
    uint32_t m0 = PERF_MDU_STALL_COUNT;
    uint32_t checksum = seed;
    uint32_t i;

    for (i = 0; i < 256; ++i) {
        uint32_t index = (mode == 0) ? (i & 63U) :
                         (mode == 1) ? ((i * 7U) & 63U) :
                         ((i * 13U + 3U) & 63U);
        uint32_t value = working_set[index];
        if (mode == 0) {
            value = value + i + seed;
        } else if (mode == 1) {
            value = value ^ (i << 2);
        } else {
            value = value + (i * 3U) ^ (i >> 1);
        }
        working_set[index] = value;
        checksum ^= value + (index << 3);
        if (mode == 2 && (i & 7U) == 0U)
            checksum += i * 5U;
    }

    report_case(name, counter_delta(&PERF_CYCLE_COUNT, c0),
                counter_delta(&PERF_RETIRE_COUNT, r0),
                counter_delta(&PERF_ICACHE_MISS_COUNT, i0),
                counter_delta(&PERF_DCACHE_MISS_COUNT, d0),
                counter_delta(&PERF_BRANCH_MISPREDICT, b0),
                counter_delta(&PERF_MDU_STALL_COUNT, m0), checksum);
}

static uint32_t run_mdu_case(void) {
    uint32_t checksum = 0x13579BDFU;
    uint32_t i;
    for (i = 1; i <= 64; ++i)
        checksum += (i * 17U) ^ (i * 19U) + (i << 4);
    return checksum;
}

int main(void) {
    uint32_t i;
    uint32_t version = PERF_VERSION;
    uint32_t mdu_checksum;

    for (i = 0; i < 64; ++i)
        working_set[i] = 0x10203040U ^ (i * 0x01010101U);

    print_str("perf_workloads: version="); print_hex(version); print_str("\n");
    if (version != 0x50430001U) {
        print_str("perf_workloads: FAIL bad counter version\n");
        *MAILBOX_EXIT = 0xDEADDEADU;
        while (1) { }
    }

    run_case("sequential", 0x11111111U, 0U);
    run_case("strided", 0x22222222U, 1U);
    run_case("branch_mixed", 0x33333333U, 2U);

    {
        uint32_t c0 = PERF_CYCLE_COUNT;
        uint32_t r0 = PERF_RETIRE_COUNT;
        uint32_t i0 = PERF_ICACHE_MISS_COUNT;
        uint32_t d0 = PERF_DCACHE_MISS_COUNT;
        uint32_t b0 = PERF_BRANCH_MISPREDICT;
        uint32_t m0 = PERF_MDU_STALL_COUNT;
        mdu_checksum = run_mdu_case();
        report_case("mdu", counter_delta(&PERF_CYCLE_COUNT, c0),
                    counter_delta(&PERF_RETIRE_COUNT, r0),
                    counter_delta(&PERF_ICACHE_MISS_COUNT, i0),
                    counter_delta(&PERF_DCACHE_MISS_COUNT, d0),
                    counter_delta(&PERF_BRANCH_MISPREDICT, b0),
                    counter_delta(&PERF_MDU_STALL_COUNT, m0), mdu_checksum);
    }

    if (mdu_checksum == 0U) {
        print_str("perf_workloads: FAIL checksum\n");
        *MAILBOX_EXIT = 0xDEADDEADU;
        while (1) { }
    }
    print_str("perf_workloads: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
