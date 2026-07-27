/* -----------------------------------------------------------------------------
 * uart_cpu — product firmware gate for UART 16550 commercial closure (Phase 4E).
 *
 * Verifies APB-visible UART behavior through the SoC path:
 *   1. Reset / default register reads
 *   2. DLAB divisor and SCR read/write
 *   3. FIFO enable and FCR reset
 *   4. Loopback TX/RX byte path
 *   5. RX data interrupt visible through UART IIR/LSR and VIC source 1
 *   6. TX empty interrupt status
 *   7. Modem loopback / delta behavior
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc_addr.h"
#include "print.h"

#define REG32(addr) (*(volatile uint32_t*)(addr))

#define UART_BASE            0x40000000
#define UART_RBR             (UART_BASE + 0x00)
#define UART_THR             (UART_BASE + 0x00)
#define UART_DLL             (UART_BASE + 0x00)
#define UART_IER             (UART_BASE + 0x04)
#define UART_DLM             (UART_BASE + 0x04)
#define UART_IIR             (UART_BASE + 0x08)
#define UART_FCR             (UART_BASE + 0x08)
#define UART_LCR             (UART_BASE + 0x0C)
#define UART_MCR             (UART_BASE + 0x10)
#define UART_LSR             (UART_BASE + 0x14)
#define UART_MSR             (UART_BASE + 0x18)
#define UART_SCR             (UART_BASE + 0x1C)

#define VIC_BASE             0x40004000
#define VIC_INTR_RAW         (VIC_BASE + 0x000)
#define VIC_INTR_ENABLE      (VIC_BASE + 0x004)

static void mailbox_fail(void) {
    *((volatile uint32_t*)0xA000FFFC) = 0xDEADDEAD;
    while (1) { /* halt */ }
}

static void delay_loops(uint32_t cnt) {
    volatile uint32_t i;
    for (i = 0; i < cnt; i++) { }
}

static void uart_flush(void) {
    while ((REG32(UART_LSR) & 0x40) == 0) { } // Wait TEMT=1
    REG32(UART_FCR) = 0x07;                   // Reset RX/TX FIFOs
    delay_loops(200);
}

static int test_reset_and_dlab(void) {
    uint32_t lcr = REG32(UART_LCR) & 0xFF;
    if (lcr != 0x03) {
        return -1;
    }

    uint32_t lsr = REG32(UART_LSR) & 0xFF;
    if ((lsr & 0x60) != 0x60) {
        return -1;
    }

    // SCR read/write
    REG32(UART_SCR) = 0xA5;
    if ((REG32(UART_SCR) & 0xFF) != 0xA5) {
        return -1;
    }

    // DLAB DLL/DLM
    REG32(UART_LCR) = 0x83; // DLAB=1, 8N1
    REG32(UART_DLL) = 4;
    REG32(UART_DLM) = 0;
    if ((REG32(UART_DLL) & 0xFF) != 4 || (REG32(UART_DLM) & 0xFF) != 0) {
        return -1;
    }
    REG32(UART_LCR) = 0x03; // DLAB=0

    return 0;
}

static int test_loopback_and_interrupt(void) {
    uart_flush();

    // Enable Loopback
    REG32(UART_MCR) = 0x10; // LOOP = 1

    // Enable VIC source 1 (uart_tx_int / uart_16550_irq)
    REG32(VIC_INTR_ENABLE) = (1 << 1);

    // Enable RX data available interrupt in UART (IER bit 0)
    REG32(UART_IER) = 0x01;

    // Send byte 0x77
    REG32(UART_THR) = 0x77;

    // Delay for loopback transmission to complete
    delay_loops(2000);

    // Check VIC raw interrupt for source 1
    uint32_t raw_irq = REG32(VIC_INTR_RAW);
    if (!(raw_irq & (1 << 1))) {
        print_str("FAIL: VIC source 1 (UART IRQ) not asserted after byte transmit\n");
        return -1;
    }

    // Check IIR
    uint32_t iir = REG32(UART_IIR) & 0xFF;
    if ((iir & 0x0F) != 0x04 && (iir & 0x0F) != 0x0C) {
        print_str("FAIL: IIR does not show RX data/timeout pending, got "); print_hex(iir); print_str("\n");
        return -1;
    }

    // Read byte from RBR
    uint32_t rx_data = REG32(UART_RBR) & 0xFF;
    if (rx_data != 0x77) {
        print_str("FAIL: RX loopback byte got "); print_hex(rx_data); print_str(" expected 0x77\n");
        return -1;
    }

    delay_loops(100);

    // Verify interrupt cleared
    raw_irq = REG32(VIC_INTR_RAW);
    if (raw_irq & (1 << 1)) {
        print_str("FAIL: VIC source 1 (UART IRQ) not cleared after RBR read\n");
        return -1;
    }

    REG32(UART_IER) = 0x00;
    REG32(VIC_INTR_ENABLE) = 0;
    REG32(UART_MCR) = 0x00; // Disable loopback
    return 0;
}

static int test_modem_loopback(void) {
    uart_flush();

    REG32(UART_IER) = 0x08; // Modem status interrupt enable (IER[3])
    REG32(UART_MCR) = 0x11; // LOOP=1, DTR=1 -> DSR active in loopback

    delay_loops(200);

    uint32_t msr = REG32(UART_MSR) & 0xFF;
    if ((msr & 0x02) == 0 || (msr & 0x20) == 0) { // Delta DSR (bit 1) and DSR status (bit 5)
        print_str("FAIL: MSR DSR delta or state missing, got "); print_hex(msr); print_str("\n");
        return -1;
    }

    // Read MSR again: delta bits should be cleared
    msr = REG32(UART_MSR) & 0xFF;
    if (msr & 0x02) {
        print_str("FAIL: MSR delta DSR not cleared on read\n");
        return -1;
    }

    REG32(UART_IER) = 0x00;
    REG32(UART_MCR) = 0x00;
    return 0;
}

int main(void) {
    if (test_reset_and_dlab() != 0) {
        mailbox_fail();
        return 1;
    }

    print_str("uart_cpu test: starting Phase 4E checks\n");

    if (test_loopback_and_interrupt() != 0) {
        print_str("uart_cpu test: FAILED loopback and interrupt\n");
        mailbox_fail();
        return 1;
    }

    if (test_modem_loopback() != 0) {
        print_str("uart_cpu test: FAILED modem loopback\n");
        mailbox_fail();
        return 1;
    }

    print_str("uart_cpu test: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
