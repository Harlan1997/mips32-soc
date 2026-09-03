/* Copyright 2018 EEMBC. Licensed under Apache-2.0; SoC adaptations below. */
#include "coremark.h"
#include "core_portme.h"
#include "soc_addr.h"

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = 1;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static CORE_TICKS start_time_val;
static CORE_TICKS stop_time_val;

CORETIMETYPE baremetal_clock(void) { return PERF_CYCLE_COUNT; }
void start_time(void) { start_time_val = baremetal_clock(); }
void stop_time(void) { stop_time_val = baremetal_clock(); }
CORE_TICKS get_time(void) { return stop_time_val - start_time_val; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks; }

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    p->portable_id = 1;
}
void portable_fini(core_portable *p) {
    p->portable_id = 0;
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    while (1) { }
}
