#include <stdint.h>
#include "print.h"

#define REG32(a) (*(volatile uint32_t *)(a))
#define DMA_BASE 0x40003000U
#define DMA_CTRL (DMA_BASE + 0x40U)
#define DMA_SRC  (DMA_BASE + 0x44U)
#define DMA_DST  (DMA_BASE + 0x48U)
#define DMA_LEN  (DMA_BASE + 0x4cU)
#define DMA_STAT (DMA_BASE + 0x54U)

static volatile uint32_t src[64] __attribute__((aligned(4)));
static volatile uint32_t dst[64] __attribute__((aligned(4)));

static void fail(const char *msg, uint32_t value)
{
    print_str(msg); print_hex(value); mailbox_exit();
}

int main(void)
{
    unsigned i;
    volatile uint32_t *src_u = (volatile uint32_t *)((uint32_t)src | 0xA0000000U);
    volatile uint32_t *dst_u = (volatile uint32_t *)((uint32_t)dst | 0xA0000000U);
    for (i = 0; i < 64; ++i) { src_u[i] = 0xD00D0000U + i; dst_u[i] = 0; }
    REG32(DMA_SRC) = (uint32_t)src_u;
    REG32(DMA_DST) = (uint32_t)dst_u;
    REG32(DMA_LEN) = sizeof(src);
    REG32(DMA_CTRL) = 0x1U;

    unsigned timeout = 100000U;
    uint32_t status;
    do { status = REG32(DMA_STAT); } while (!(status & 0x2U) && --timeout != 0U);
    if (!timeout) fail("dma_reset_inflight: TIMEOUT ", status);
    if ((status & 0x7U) != 0x2U) fail("dma_reset_inflight: STATUS ", status);
    for (i = 0; i < 64; ++i)
        if (dst_u[i] != src_u[i]) fail("dma_reset_inflight: DATA ", i);
    REG32(DMA_CTRL) = 0x8U;
    print_str("dma_reset_inflight: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
