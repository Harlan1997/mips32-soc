#include <stdint.h>
#include "print.h"

static uint32_t load_merge(const uint8_t *p)
{
    uint32_t value = 0;
    asm volatile("lwl %0, 3(%1)\n" "nop\n" "lwr %0, 0(%1)\n" "nop\n"
                 : "+r"(value) : "r"(p) : "memory");
    return value;
}

static void store_merge(uint8_t *p, uint32_t value)
{
    asm volatile("swl %0, 3(%1)\n" "nop\n" "swr %0, 0(%1)\n" "nop\n"
                 : : "r"(value), "r"(p) : "memory");
}

int main(void)
{
    volatile uint32_t *words = (volatile uint32_t *)0x00005100;
    uint8_t *bytes = (uint8_t *)words;
    uint32_t expect[3] = {0xff8899aaU, 0xeeff8899U, 0xddeeff88U};
    uint32_t got[3];
    unsigned i;

    words[0] = 0x8899aabbU;
    words[1] = 0xccddeeffU;
    words[2] = 0x00112233U;
    for (i = 0; i < 3; ++i)
        got[i] = load_merge(bytes + 1U + i);
    for (i = 0; i < 3; ++i) {
        if (got[i] != expect[i]) {
            print_str("qemu_system_unaligned: LOAD_FAIL\n");
            print_hex(i);
            print_hex(got[i]);
            mailbox_exit();
        }
    }

    words[0] = 0;
    words[1] = 0;
    store_merge(bytes + 1, 0x11223344U);
    if (bytes[0] != 0 || bytes[1] != 0x44 || bytes[2] != 0x33 ||
        bytes[3] != 0x22 || bytes[4] != 0x11) {
        print_str("qemu_system_unaligned: STORE_FAIL\n");
        print_hex(words[0]);
        print_hex(words[1]);
        mailbox_exit();
    }

    print_str("qemu_system_unaligned: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
