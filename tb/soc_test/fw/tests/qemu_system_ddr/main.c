#include <stdint.h>
#include "print.h"

#define R(a) (*(volatile uint32_t *)(a))
#define DDR_BASE 0x08000000u
#define DDR_KSEG1 0xA8000000u
#define DDR_VERSION R(0x40006000)
#define DDR_STATUS R(0x40006004)
#define DDR_ERROR R(0x40006008)
#define DDR_CONTROL R(0x4000600c)

#ifndef QEMU_DDR_EXPECTED_ERROR
#define QEMU_DDR_EXPECTED_ERROR 0x00040004u
#endif
#define MAILBOX R(0xA000fffc)

static int fail(const char *name)
{
    print_str("QEMU_SYSTEM_DDR: FAIL ");
    print_str(name);
    print_str("\n");
    return 1;
}

int main(void)
{
    volatile uint32_t *cached = (volatile uint32_t *)DDR_BASE;
    volatile uint32_t *uncached = (volatile uint32_t *)DDR_KSEG1;

    if (DDR_VERSION != 0x44445201) return fail("VERSION");
    if ((DDR_STATUS & 7) != 7) return fail("READY");
#ifndef QEMU_DDR_FAULT_TEST
    if (DDR_ERROR != 0) return fail("ERROR_RESET");
#endif

#ifdef QEMU_DDR_FAULT_TEST
    if (!(DDR_STATUS & (1u << 5)) || DDR_ERROR != QEMU_DDR_EXPECTED_ERROR)
        return fail("FAULT_STATUS");
    DDR_CONTROL = 1;
    if (DDR_ERROR != 0 || (DDR_STATUS & (1u << 5)))
        return fail("FAULT_W1C");
    print_str("QEMU_SYSTEM_DDR: FAULT_W1C_PASS\n");
#endif

    cached[0] = 0x11223344;
    cached[1] = 0xa5a55a5a;
    if (cached[0] != 0x11223344 || cached[1] != 0xa5a55a5a)
        return fail("DDR_RW");
    if (uncached[0] != 0x11223344 || uncached[1] != 0xa5a55a5a)
        return fail("DDR_ALIAS");

    /* The reference machine starts with no sticky fault. W1C is harmless and
     * is part of the software-visible controller status contract. */
    DDR_CONTROL = 1;
    if (DDR_ERROR != 0 || (DDR_STATUS & 7) != 7) return fail("W1C");

#ifdef QEMU_DDR_FAULT_TEST
    print_str("QEMU_SYSTEM_DDR: FAULT_WINDOW_PASS\n");
#else
    print_str("QEMU_SYSTEM_DDR: WINDOW_PASS\n");
#endif
    R(0xA000fffc) = 0xdeadbeef;
    return 0;
}
