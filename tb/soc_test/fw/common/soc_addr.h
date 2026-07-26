/* -----------------------------------------------------------------------------
 * soc_addr.h — memory-mapped peripheral base addresses
 * Shared by all firmware variants under tb/soc_test/fw/tests/*
 * -------------------------------------------------------------------------- */
#ifndef SOC_ADDR_H
#define SOC_ADDR_H

#include <stdint.h>

#define UART_TX_DATA   (*(volatile uint32_t*)0x40000000)
#define TIMER_CTRL     (*(volatile uint32_t*)0x40001000)
#define TIMER_LOAD     (*(volatile uint32_t*)0x40001004)
#define TIMER_VAL      (*(volatile uint32_t*)0x40001008)
#define TIMER_INTCLR   (*(volatile uint32_t*)0x4000100C)
#define GPIO_DATA      (*(volatile uint32_t*)0x40002000)
#define GPIO_DIR       (*(volatile uint32_t*)0x40002004)
#define DMA_SRC        (*(volatile uint32_t*)0x40003000)
#define DMA_DST        (*(volatile uint32_t*)0x40003004)
#define DMA_LEN        (*(volatile uint32_t*)0x40003008)
#define DMA_CTRL       (*(volatile uint32_t*)0x4000300C)
#define PIC_STATUS     (*(volatile uint32_t*)0x40004000)
#define PIC_MASK       (*(volatile uint32_t*)0x40004004)
#define PIC_ACTIVE     (*(volatile uint32_t*)0x40004008)

#define MAILBOX_EXIT   ((volatile uint32_t*)0xA000FFFC)
#define MAILBOX_MAGIC  0xDEADBEEF

#endif
