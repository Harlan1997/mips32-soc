// =============================================================================
// File Name: soc_top.v
// Design:    Product-facing SoC top-level wrapper
// =============================================================================

`include "soc_config.vh"

module soc_top #(
    parameter ENABLE_DUAL_CORE = 1'b0,
    parameter ENABLE_VEIC = 1'b0,
    parameter ENABLE_HARDWARE_WALKER = 1'b0,
    parameter [31:0] HARDWARE_WALKER_PTBR = 32'd0
) (
    input  wire clk,
    input  wire rst_n,

    inout  wire [31:0] gpio_pins,

    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        uart_cts_n,
    output wire        uart_rts_n,
    input  wire        uart_dsr_n,
    output wire        uart_dtr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    inout  wire [3:0]  qspi_io,

    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo
);

    mips_soc #(
        .ENABLE_DUAL_CORE (ENABLE_DUAL_CORE),
        .ENABLE_VEIC      (ENABLE_VEIC),
        .ENABLE_HARDWARE_WALKER (ENABLE_HARDWARE_WALKER),
        .HARDWARE_WALKER_PTBR   (HARDWARE_WALKER_PTBR),
        .ENABLE_UART_PINS (1'b1),
        // Frozen RTL baseline: x1 SPI is the default; quad is opt-in per gate.
        .ENABLE_QSPI_QUAD (1'b0)
    ) u_soc (
        .clk          (clk),
        .rst_n        (rst_n),

        .gpio_pins    (gpio_pins),

        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .uart_cts_n   (uart_cts_n),
        .uart_rts_n   (uart_rts_n),
        .uart_dsr_n   (uart_dsr_n),
        .uart_dtr_n   (uart_dtr_n),
        .uart_dcd_n   (uart_dcd_n),
        .uart_ri_n    (uart_ri_n),

        .spi_sclk     (spi_sclk),
        .spi_cs_n     (spi_cs_n),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso),
        .qspi_io      (qspi_io),

        .tck          (tck),
        .tms          (tms),
        .tdi          (tdi),
        .tdo          (tdo)
    );

endmodule
