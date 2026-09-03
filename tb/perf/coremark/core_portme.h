/* SoC bare-metal port for the official CoreMark source. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>

#define HAS_FLOAT 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define USE_CLOCK 0
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#ifndef TOTAL_DATA_SIZE
#define TOTAL_DATA_SIZE 2000
#endif
#define SEED_METHOD SEED_VOLATILE
#define CORETIMETYPE ee_u32
#define CORE_TICKS ee_u32
#define TIMER_RES_DIVIDER 1
#define EE_TICKS_PER_SEC 1
#define MEM_LOCATION "SRAM"
#define COMPILER_VERSION "mips64-linux-gnu-gcc"
#define COMPILER_FLAGS "-mips32 -mabi=32 -O2 -ffreestanding"
#define PARALLEL_METHOD "1 CPU"

typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef unsigned int ee_u32;
typedef unsigned char ee_u8;
typedef unsigned int ee_ptr_int;
typedef size_t ee_size_t;
typedef ee_u32 secs_ret;

typedef struct CORE_PORTABLE_S { ee_u8 portable_id; } core_portable;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3U))
extern ee_u32 default_num_contexts;
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
void start_time(void);
void stop_time(void);
CORE_TICKS get_time(void);
secs_ret time_in_secs(CORE_TICKS ticks);
int ee_printf(const char *fmt, ...);

#endif
