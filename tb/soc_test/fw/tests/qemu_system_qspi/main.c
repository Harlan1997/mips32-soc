#include <stdint.h>
#include "print.h"

#define R(a) (*(volatile uint32_t *)(a))
#define Q(a) R(0x40005020 + (a))
#define MAILBOX (*(volatile uint32_t *)0xA000FFFC)

#define CTRL 0x000
#define STATUS 0x004
#define IRQ_EN 0x010
#define IRQ_STATUS 0x014
#define TIMEOUT 0x018
#define LUT0 0x020
#define LUT1 0x024
#define TRIG 0x100
#define ADDR 0x104
#define LEN 0x108
#define TX 0x110
#define RX 0x114
#define FIFO_STAT 0x118

static int fail(const char *name)
{
    print_str("QEMU_SYSTEM_QSPI: FAIL ");
    print_str(name);
    print_str("\n");
    return 1;
}

static int wait_done(void)
{
    for (unsigned i = 0; i < 64; ++i) {
        uint32_t st = Q(STATUS);
        if ((st & 1) == 0) return (st & (1u << 4)) ? -1 : 0;
    }
    return -1;
}

int main(void)
{
    uint32_t v;

    if (R(0x40005000) != 0x51535001) return fail("VERSION");
    Q(CTRL) = 1;
    Q(IRQ_EN) = 1;
    Q(TIMEOUT) = 4096;

    /* x1 image-backed read: the firmware image starts with a nonzero word. */
    Q(LUT0) = 0x00000005;
    Q(ADDR) = 0;
    Q(LEN) = 4;
    Q(TRIG) = 0;
    if (wait_done() != 0) return fail("X1_READ");
    if ((Q(IRQ_STATUS) & 1) == 0) return fail("DONE_IRQ");
    v = Q(RX);
    if (v == 0) return fail("RX_DATA");
    Q(RX);
    Q(RX);
    Q(RX);
    if ((Q(FIFO_STAT) & 0x7f00) != 0) return fail("RX_DRAIN");
    Q(IRQ_STATUS) = 7;
    if (Q(STATUS) & 0x78) return fail("DONE_W1C");

    /* 0x6b selects the same image-backed read under the quad data contract. */
    Q(LUT1) = (2u << 22) | 0x0000006b;
    Q(ADDR) = 4;
    Q(LEN) = 4;
    Q(TRIG) = 1;
    if (wait_done() != 0) return fail("QUAD_READ");
    if (Q(RX) == 0) return fail("QUAD_RX");
    Q(RX); Q(RX); Q(RX);
    Q(IRQ_STATUS) = 1;

    /* TX FIFO is consumed by a bounded image-backed write transaction. */
    Q(LUT1) = (1u << 17) | (1u << 8) | 0x00000032;
    Q(ADDR) = 0x100;
    Q(LEN) = 4;
    Q(TX) = 0xa1b2c3d4;
    if ((Q(FIFO_STAT) & 0x7f) == 0) return fail("TX_PUSH");
    Q(TRIG) = 1;
    if (wait_done() != 0) return fail("TX_WRITE");
    if (Q(FIFO_STAT) & 0x7f) return fail("TX_DRAIN");
    Q(IRQ_STATUS) = 1;

    /* Abort must release busy and leave an observable W1C event. */
    Q(LUT0) = 0x00000005;
    Q(LEN) = 4;
    Q(TRIG) = 0;
    Q(CTRL) = 4;
    if (Q(STATUS) & 1) return fail("ABORT_BUSY");
    if ((Q(STATUS) & (1u << 6)) == 0) return fail("ABORT_STATUS");
    Q(IRQ_STATUS) = 4;

    /* A one-cycle budget deterministically classifies the command timeout. */
    Q(CTRL) = 1;
    Q(TIMEOUT) = 1;
    Q(LEN) = 4;
    Q(TRIG) = 0;
    if (Q(STATUS) & 1) return fail("TIMEOUT_BUSY");
    if ((Q(STATUS) & (1u << 5)) == 0) return fail("TIMEOUT_STATUS");
    Q(IRQ_STATUS) = 2;
    Q(0x018) = 4096;

    print_str("QEMU_SYSTEM_QSPI: COMMAND_PASS\n");
    MAILBOX = 0xdeadbeef;
    return 0;
}
