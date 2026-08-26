#include <stdint.h>
#include "print.h"
#include "soc_addr.h"

#define U32(addr) (*(volatile uint32_t *)(addr))
#define U8(addr)  (*(volatile uint8_t *)(addr))
#define CWORD0    ((volatile uint32_t *)0x00002000u)
#define CWORD1    ((volatile uint32_t *)0x00002004u)
#define CWORD2    ((volatile uint32_t *)0x00002008u)
#define UWORD0    ((volatile uint32_t *)0xA0002000u)
#define UWORD1    ((volatile uint32_t *)0xA0002004u)
#define UWORD2    ((volatile uint32_t *)0xA0002008u)
#define START     U32(0xA0002100u)
#define READY     U32(0xA0002104u)
#define COMMAND   U32(0xA0002108u)
#define ACK_WORD  U32(0xA000210Cu)
#define ACK_PART  U32(0xA0002110u)
#define DONE      U32(0xA0002114u)
#define FAIL_CODE U32(0xA0002118u)
#define CORE0_SEEN U32(0xA0002120u)
#define CORE1_SEEN U32(0xA0002124u)

#define ITERATIONS 8u

static void sync_barrier(void)
{
    __asm__ volatile("sync" ::: "memory");
}

static void wait_for_bus_quiet(void)
{
    __asm__ volatile(
        "li $t0, 10000\n\t"
        "1:\n\t"
        "addiu $t0, $t0, -1\n\t"
        "bnez $t0, 1b\n\t"
        "nop\n\t"
        : : : "$8");
}

static uint32_t read_cpunum(void)
{
    uint32_t value;
    __asm__ volatile(".word 0x7c08003b\n\t"
                     "move %0, $8\n\t"
                     : "=r"(value) : : "$8");
    return value;
}

static void fail(uint32_t code, uint32_t value)
{
    FAIL_CODE = code;
    print_str("COH_STRESS_FAIL code=");
    print_hex(code);
    print_hex(value);
    sync_barrier();
    *MAILBOX_EXIT = 0xDEADDEADu;
    while (1) { }
}

static void wait_equal(volatile uint32_t *addr, uint32_t expected, uint32_t code)
{
    uint32_t guard = 0;
    while (*addr != expected) {
        if (++guard == 0) fail(code, *addr);
    }
}

void core1_test(void)
{
    uint32_t i;
    uint32_t value;

    CORE1_SEEN = 1u;
    wait_equal(&START, 1u, 0x101u);
    READY = 1u;
    wait_equal(&COMMAND, 0x80u, 0x103u);
    value = *CWORD0;
    if (value != 0u) fail(0x102u, value);
    sync_barrier();
    ACK_WORD = 0x80u;

    for (i = 1; i <= ITERATIONS; ++i) {
        uint32_t expected0 = 0xC0000000u | i;
        uint32_t prior2 = (i == 1u) ? 0xA5A5A5A5u :
                          (0xA5A50000u | ((i - 1u) << 8) | 0xA5u);
        uint32_t merged2 = 0xA5A50000u | ((i & 0xFFu) << 8) | 0xA5u;

        wait_equal(&COMMAND, i, 0x110u + i);
        value = *CWORD0;
        if (value != expected0) fail(0x120u + i, value);
        *UWORD1 = 0xB0000000u | i;
        value = *CWORD2;
        if (value != prior2) fail(0x130u + i, value);
        sync_barrier();
        ACK_WORD = i;

        wait_equal(&COMMAND, 0x100u + i, 0x140u + i);
        value = *CWORD2;
        if (value != merged2) fail(0x150u + i, value);
        ACK_PART = i;
    }

    DONE = 1u;
    print_str("COH_STRESS_CORE1_DONE iterations=");
    print_hex(ITERATIONS);
    while (1) { }
}

static void core1_entry(void) __attribute__((naked, noreturn));

static void core1_entry(void)
{
    __asm__ volatile(
        ".set noreorder\n\t"
        "li $sp, 0x8000\n\t"
        "j core1_test\n\t"
        "nop\n\t"
        ".set reorder\n\t"
        ::: "$sp", "memory");
}

static void core0_test(void)
{
    uint32_t i;
    uint32_t value;

    START = 0u;
    READY = 0u;
    COMMAND = 0u;
    ACK_WORD = 0u;
    ACK_PART = 0u;
    DONE = 0u;
    FAIL_CODE = 0u;
    CORE0_SEEN = 1u;
    *UWORD0 = 0u;
    *UWORD1 = 0u;
    *UWORD2 = 0xA5A5A5A5u;
    sync_barrier();
    START = 1u;
    wait_equal(&READY, 1u, 0x201u);
    COMMAND = 0x80u;
    wait_for_bus_quiet();
    wait_equal(&ACK_WORD, 0x80u, 0x202u);

    for (i = 1; i <= ITERATIONS; ++i) {
        uint32_t expected1 = 0xB0000000u | i;
        uint32_t merged2 = 0xA5A50000u | ((i & 0xFFu) << 8) | 0xA5u;

        value = *CWORD1;
        if (value != 0u && i == 1u) fail(0x210u, value);
        *UWORD0 = 0xC0000000u | i;
        sync_barrier();
        COMMAND = i;
        wait_for_bus_quiet();
        wait_equal(&ACK_WORD, i, 0x220u + i);
        value = *CWORD1;
        if (value != expected1) fail(0x230u + i, value);

        U8(0xA0002009u) = (uint8_t)i;
        sync_barrier();
        COMMAND = 0x100u + i;
        wait_for_bus_quiet();
        wait_equal(&ACK_PART, i, 0x240u + i);
        value = *CWORD2;
        if (value != merged2) fail(0x250u + i, value);
    }

    wait_equal(&DONE, 1u, 0x260u);
    print_str("COH_STRESS_CORE0_DONE iterations=");
    print_hex(ITERATIONS);
    print_str("COH_STRESS_SHARED_MEMORY_PASS\n");
    mailbox_exit();
}

int main(void)
{
    uint32_t cpunum = read_cpunum();
    if (cpunum == 1u) {
        core1_entry();
    } else if (cpunum == 0u)
        core0_test();
    else
        fail(0x001u, cpunum);
    return 0;
}
