// =============================================================================
// File Name: soc_config.vh
// Design:    Project-wide SoC configuration contract
// =============================================================================

`ifndef SOC_CONFIG_VH
`define SOC_CONFIG_VH

// AXI/APB interface contract
`define SOC_AXI_ID_WIDTH      4
`define SOC_AXI_ADDR_WIDTH    32
`define SOC_AXI_DATA_WIDTH    32
`define SOC_AXI_LEN_WIDTH     8
`define SOC_APB_ADDR_WIDTH    12
`define SOC_APB_DATA_WIDTH    32

// Top-level address decode nibbles
`define SOC_ADDR_NIBBLE_SRAM       4'h0
`define SOC_ADDR_NIBBLE_FLASH      4'h1
`define SOC_ADDR_NIBBLE_APB        4'h4
`define SOC_ADDR_NIBBLE_SRAM_ALIAS 4'hA

// AXI response encodings
`define SOC_AXI_RESP_OKAY          2'b00
`define SOC_AXI_RESP_EXOKAY        2'b01
`define SOC_AXI_RESP_SLVERR        2'b10
`define SOC_AXI_RESP_DECERR        2'b11

// Memory map
`define SOC_BOOT_BASE         32'h0000_0000
`define SOC_FLASH_BASE        32'h1000_0000
`define SOC_APB_BASE          32'h4000_0000
`define SOC_SRAM_ALIAS_BASE   32'hA000_0000
`define SOC_DEBUG_BASE        32'hE000_0000

// Address decode masks
`define SOC_64KB_REGION_MASK  32'hFFFF_0000
`define SOC_256MB_REGION_MASK 32'hF000_0000

// APB peripheral offsets
`define SOC_APB_UART_OFFSET   16'h0000
`define SOC_APB_TIMER_OFFSET  16'h1000
`define SOC_APB_GPIO_OFFSET   16'h2000
`define SOC_APB_DMA_OFFSET    16'h3000
`define SOC_APB_PIC_OFFSET    16'h4000
// Verification-only APB fault slot. Product builds leave the injector disabled.
`define SOC_APB_FAULT_OFFSET   16'hF000

// GPIO register offsets
`define SOC_GPIO_DATA_OFFSET  12'h000
`define SOC_GPIO_DIR_OFFSET   12'h004

// DMA register offsets
`define SOC_DMA_SRC_OFFSET     12'h000
`define SOC_DMA_DST_OFFSET     12'h004
`define SOC_DMA_LEN_OFFSET     12'h008
`define SOC_DMA_CTRL_OFFSET    12'h00C

// UART register offsets
`define SOC_UART_TX_OFFSET     12'h000
`define SOC_UART_STATUS_OFFSET 12'h004
`define SOC_UART_IRQ_STATUS_OFFSET 12'h008
`define SOC_UART_IRQ_CLEAR_OFFSET  12'h00C

// Timer register offsets
`define SOC_TIMER_CTRL_OFFSET  12'h000
`define SOC_TIMER_LOAD_OFFSET  12'h004
`define SOC_TIMER_VAL_OFFSET   12'h008
`define SOC_TIMER_INT_OFFSET   12'h00C

// PIC register offsets
`define SOC_PIC_STATUS_OFFSET  12'h000
`define SOC_PIC_MASK_OFFSET    12'h004
`define SOC_PIC_ACTIVE_OFFSET  12'h008

`endif
