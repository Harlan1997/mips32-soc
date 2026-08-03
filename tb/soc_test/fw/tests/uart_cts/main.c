/* SoC UART CTS flow-control integration gate.
 * The testbench holds external CTS inactive until firmware has queued TX data.
 */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define UART_BASE 0x40000000
#define UART_THR  (UART_BASE + 0x00)
#define UART_DLL  (UART_BASE + 0x00)
#define UART_IER  (UART_BASE + 0x04)
#define UART_DLM  (UART_BASE + 0x04)
#define UART_FCR  (UART_BASE + 0x08)
#define UART_LCR  (UART_BASE + 0x0C)
#define UART_MCR  (UART_BASE + 0x10)
#define UART_LSR  (UART_BASE + 0x14)

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

    REG32(UART_IER) = 0x00;
    REG32(UART_LCR) = 0x83;
    REG32(UART_DLL) = 0x01;
    REG32(UART_DLM) = 0x00;
    REG32(UART_LCR) = 0x03;
    REG32(UART_FCR) = 0x07;
    REG32(UART_MCR) = 0x20;  /* MCR[5]: hardware CTS gate, no loopback */

    REG32(UART_THR) = 0xA6;

    for (timeout = 0; timeout < 200000; timeout++) {
        lsr = REG32(UART_LSR) & 0xFF;
        if ((lsr & 0x60) == 0x60)
            break;
    }
    if (timeout == 200000)
        fail("FAIL: UART CTS TX completion timeout LSR=", lsr);

    print_str("uart_cts: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
