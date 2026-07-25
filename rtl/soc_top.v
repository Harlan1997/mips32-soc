// =============================================================================
// File Name: soc_top.v
// Design:    Product-facing SoC top-level wrapper
// =============================================================================

`include "soc_config.vh"

module soc_top (
    input  wire clk,
    input  wire rst_n,

    inout  wire [31:0] gpio_pins,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo
);

    mips_soc u_soc (
        .clk          (clk),
        .rst_n        (rst_n),

        .gpio_pins    (gpio_pins),

        .spi_sclk     (spi_sclk),
        .spi_cs_n     (spi_cs_n),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso),

        .tck          (tck),
        .tms          (tms),
        .tdi          (tdi),
        .tdo          (tdo)
    );

endmodule
