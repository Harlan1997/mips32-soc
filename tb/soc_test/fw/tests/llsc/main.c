/* Single-core MIPS32 LL/SC reservation contract gate. */
#include <stdint.h>
#include "print.h"

#define TEST_WORD ((volatile uint32_t *)0xA0002000)

static void fail(const char *msg, uint32_t value)
{
    print_str(msg);
    print_hex(value);
    print_str("\n");
    *((volatile uint32_t *)0xA000FFFC) = 0xDEADDEAD;
    while (1) { }
}

static uint32_t ll_word(volatile uint32_t *addr)
{
    uint32_t value;
    __asm__ volatile("ll %0, 0(%1)" : "=r"(value) : "r"(addr) : "memory");
    return value;
}

static uint32_t sc_word(volatile uint32_t *addr, uint32_t value)
{
    uint32_t result;
    __asm__ volatile("sc %0, 0(%1)\n\tnop\n\tnop\n\tnop" : "=r"(result) : "r"(addr), "0"(value) : "memory");
    return result;
}

static uint32_t read_lladdr(void)
{
    uint32_t value;
    __asm__ volatile("mfc0 %0, $17, 0" : "=r"(value));
    return value;
}

static void write_lladdr(uint32_t value)
{
    __asm__ volatile("mtc0 %0, $17, 0" : : "r"(value));
}

int main(void)
{
    uint32_t result;

    *TEST_WORD = 0x11223344;
    if (ll_word(TEST_WORD) != 0x11223344)
        fail("FAIL: LL read=", *TEST_WORD);
    if (read_lladdr() != (uint32_t)TEST_WORD)
        fail("FAIL: LLAddr after LL=", read_lladdr());

    /* LLAddr is diagnostic read-only state, not a software reservation setter. */
    write_lladdr(0xDEADBEEFU);
    if (read_lladdr() != (uint32_t)TEST_WORD)
        fail("FAIL: LLAddr accepted MTC0=", read_lladdr());

    result = sc_word(TEST_WORD, 0x55667788);
    if (result != 1)
        fail("FAIL: reserved SC result=", result);
    if (*TEST_WORD != 0x55667788)
        fail("FAIL: reserved SC value=", *TEST_WORD);

    /* SC without a preceding LL must fail and leave memory unchanged. */
    *TEST_WORD = 0xA5A5A5A5;
    result = sc_word(TEST_WORD, 0xCAFEBABE);
    if (result != 0 || *TEST_WORD != 0xA5A5A5A5)
        fail("FAIL: unreserved SC result/value=", (result << 31) | (*TEST_WORD & 0x7fffffff));

    /* Every SC attempt consumes LL state, including a failed attempt to a
     * different aligned word.  A retry must not inherit the old reservation. */
    *TEST_WORD = 0x13579BDF;
    *(TEST_WORD + 1) = 0x0A0B0C0D;
    (void)ll_word(TEST_WORD);
    result = sc_word(TEST_WORD + 1, 0x2468ACE0);
    if (result != 0 || *(TEST_WORD + 1) != 0x0A0B0C0D)
        fail("FAIL: mismatched SC unexpectedly succeeded=", result);
    result = sc_word(TEST_WORD, 0xCAFED00D);
    if (result != 0 || *TEST_WORD != 0x13579BDF)
        fail("FAIL: failed SC retained reservation=", (result << 31) | (*TEST_WORD & 0x7fffffff));

    /* Any completed ordinary store clears the reservation. */
    *TEST_WORD = 0x01020304;
    (void)ll_word(TEST_WORD);
    *TEST_WORD = 0x05060708;
    result = sc_word(TEST_WORD, 0xDEADBEEF);
    if (result != 0 || *TEST_WORD != 0x05060708)
        fail("FAIL: cleared reservation result/value=", (result << 31) | (*TEST_WORD & 0x7fffffff));

    /* An exception boundary terminates an LL/SC sequence.  The common
     * firmware handler returns with ERET, so this exercises the real CPU
     * exception flush rather than a software reservation reset. */
    *TEST_WORD = 0x0BADB002;
    (void)ll_word(TEST_WORD);
    __asm__ volatile("syscall\n\tnop\n\tnop\n\tnop" ::: "memory");
    result = sc_word(TEST_WORD, 0xFACEFEED);
    if (result != 0 || *TEST_WORD != 0x0BADB002)
        fail("FAIL: exception retained reservation=", (result << 31) | (*TEST_WORD & 0x7fffffff));

    /* Peer store notification clears reservation test. */
#ifdef LL_SC_COHERENCY
    *TEST_WORD = 0x12345678;
    (void)ll_word(TEST_WORD);
    /* Register-only delay loop: no memory stores to avoid clearing reservation locally. */
    __asm__ volatile(
        "li $t0, 50\n\t"
        "1:\n\t"
        "addiu $t0, $t0, -1\n\t"
        "bnez $t0, 1b\n\t"
        "nop\n\t"
        : : : "t0"
    );
    result = sc_word(TEST_WORD, 0x87654321);
    if (result != 0)
        fail("FAIL: peer notification did not invalidate SC=", result);
    if (*TEST_WORD != 0x12345678)
        fail("FAIL: peer invalidated SC value=", *TEST_WORD);
    print_str("LLSC_COHERENCY_PEER_INVALIDATED_SC_FAILED\n");
#endif

    print_str("llsc test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
