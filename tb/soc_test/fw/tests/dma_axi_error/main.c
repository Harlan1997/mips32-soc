#include <stdint.h>
#include "print.h"

#define REG32(a) (*(volatile uint32_t *)(a))
#define DMA_BASE 0x40003000U
#define DMA_CTRL (DMA_BASE + 0x40U)
#define DMA_SRC  (DMA_BASE + 0x44U)
#define DMA_DST  (DMA_BASE + 0x48U)
#define DMA_LEN  (DMA_BASE + 0x4cU)
#define DMA_STAT (DMA_BASE + 0x54U)
#define DMA_IRQ  (DMA_BASE + 0x104U)
#define PIC_STAT 0x40004000U

#ifndef DMA_EXPECT_ERR_CODE
#define DMA_EXPECT_ERR_CODE 2U
#endif

static void fail(const char *msg, uint32_t value)
{
    print_str(msg);
    print_hex(value);
    print_str("\n");
    mailbox_exit();
}

int main(void)
{
    /* The DDR model fault hook targets this physical cache line. */
    REG32(DMA_SRC) = 0x00008000U;
    REG32(DMA_DST) = 0x00009000U;
    REG32(DMA_LEN) = 4U;
    REG32(DMA_CTRL) = 0x5U; /* EN + interrupt enable */

    unsigned timeout = 20000U;
    uint32_t status;
    do {
        status = REG32(DMA_STAT);
    } while (!(status & 0x4U) && --timeout != 0U);
    if (timeout == 0U)
        fail("dma_axi_error: TIMEOUT ", status);

    status = REG32(DMA_STAT);
    if ((status & 0x3cU) != ((DMA_EXPECT_ERR_CODE << 3) | 0x4U))
        fail("dma_axi_error: STATUS ", status);
    if (!(REG32(DMA_IRQ) & 1U))
        fail("dma_axi_error: IRQ_STATUS ", REG32(DMA_IRQ));
    if (!(REG32(PIC_STAT) & (1U << 3)))
        fail("dma_axi_error: PIC_STATUS ", REG32(PIC_STAT));

    /* Clear the terminal DONE and ERR latches together for re-arm. */
    REG32(DMA_CTRL) = 0x18U; /* DONE_W1C + ERR_W1C */
    status = REG32(DMA_STAT);
    if (status & 0x1cU)
        fail("dma_axi_error: W1C ", status);

    print_str("dma_axi_error: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
