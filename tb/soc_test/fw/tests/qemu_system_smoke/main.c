#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

int main(void)
{
    volatile uint32_t *cached = (volatile uint32_t *)0x00000040;
    volatile uint32_t *uncached = (volatile uint32_t *)0xA0000040;

    *cached = 0x13579BDF;
    if (*uncached != 0x13579BDF) {
        print_str("QEMU_SYSTEM_SMOKE: SRAM_ALIAS_FAIL\n");
        return 1;
    }

    print_str("QEMU_SYSTEM_SMOKE: UART_PASS\n");
    print_str("QEMU_SYSTEM_SMOKE: SRAM_PASS\n");
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    return 0;
}
