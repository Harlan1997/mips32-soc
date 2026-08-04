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

int main(void)
{
    uint32_t result;

    *TEST_WORD = 0x11223344;
    if (ll_word(TEST_WORD) != 0x11223344)
        fail("FAIL: LL read=", *TEST_WORD);

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

    /* Any completed ordinary store clears the reservation. */
    *TEST_WORD = 0x01020304;
    (void)ll_word(TEST_WORD);
    *TEST_WORD = 0x05060708;
    result = sc_word(TEST_WORD, 0xDEADBEEF);
    if (result != 0 || *TEST_WORD != 0x05060708)
        fail("FAIL: cleared reservation result/value=", (result << 31) | (*TEST_WORD & 0x7fffffff));

    print_str("llsc test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
