/* SoC external UART RX integration gate.
 * The testbench supplies one asynchronous 8N1 frame after RX is enabled.
 */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define UART_BASE       0x40000000
#define UART_RBR        (UART_BASE + 0x00)
#define UART_IER        (UART_BASE + 0x04)
#define UART_FCR        (UART_BASE + 0x08)
#define UART_LCR        (UART_BASE + 0x0C)
#define UART_MCR        (UART_BASE + 0x10)
#define UART_LSR        (UART_BASE + 0x14)
#define VIC_BASE        0x40004000
#define VIC_INTR_RAW    (VIC_BASE + 0x000)
#define VIC_INTR_ENABLE (VIC_BASE + 0x004)

static void fail(const char *message, uint32_t value) {
    print_str(message);
    print_hex(value);
    print_str("\n");
    *((volatile uint32_t *)0xA000FFFC) = 0xDEADDEAD;
    while (1) { }
}

int main(void) {
    uint32_t timeout;
    uint32_t lsr;
    uint32_t raw;
    uint32_t value;

    REG32(UART_LCR) = 0x03;       // 8N1, divisor=1
    REG32(UART_FCR) = 0x01;       // FIFO enabled, trigger level 1
    REG32(UART_MCR) = 0x00;       // external pin path, no loopback
    REG32(VIC_INTR_ENABLE) = 0x01; // PIC bit 0 is UART RX-specific source
    REG32(UART_IER) = 0x01;       // RX data available interrupt

    for (timeout = 0; timeout < 200000; timeout++) {
        lsr = REG32(UART_LSR) & 0xFF;
        if (lsr & 0x01)
            break;
    }
    if (timeout == 200000)
        fail("FAIL: external RX timeout LSR=", lsr);

    raw = REG32(VIC_INTR_RAW);
    if ((raw & 0x01) == 0)
        fail("FAIL: PIC RX source not asserted RAW=", raw);

    if (lsr & 0x0E)
        fail("FAIL: external RX line error LSR=", lsr);

    value = REG32(UART_RBR) & 0xFF;
    if (value != 0x5A)
        fail("FAIL: external RX data=", value);

    for (timeout = 0; timeout < 1000; timeout++) {
        if ((REG32(VIC_INTR_RAW) & 0x01) == 0)
            break;
    }
    if (timeout == 1000)
        fail("FAIL: PIC RX source did not clear RAW=", REG32(VIC_INTR_RAW));

    print_str("uart_external_rx: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
