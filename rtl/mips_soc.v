// =============================================================================
// File Name: mips_soc.v
// Design:    Product-facing MIPS32 SoC integration
// =============================================================================

module mips_soc #(
    parameter ENABLE_UART_PINS = 1'b0,
    parameter integer SPI_READ_TIMEOUT_CYCLES = 512
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

    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo
);

    wire        ext_awready;
    wire        ext_wready;
    wire [3:0]  ext_bid;
    wire [1:0]  ext_bresp;
    wire        ext_bvalid;
    wire        ext_arready;
    wire [3:0]  ext_rid;
    wire [31:0] ext_rdata;
    wire [1:0]  ext_rresp;
    wire        ext_rlast;
    wire        ext_rvalid;

    mips_soc_impl #(
        .ENABLE_EXT_AXI_MASTER     (1'b0),
        .ENABLE_APB_FAULT_INJECTOR (1'b0),
        .ENABLE_FLASH_IMAGE_MODEL  (1'b0),
        .ENABLE_UART_PINS          (ENABLE_UART_PINS),
        .SPI_READ_TIMEOUT_CYCLES   (SPI_READ_TIMEOUT_CYCLES)
    ) u_impl (
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

        .tck          (tck),
        .tms          (tms),
        .tdi          (tdi),
        .tdo          (tdo),

        .ext_awid     (4'd0),
        .ext_awaddr   (32'd0),
        .ext_awlen    (8'd0),
        .ext_awsize   (3'd0),
        .ext_awburst  (2'd0),
        .ext_awlock   (2'd0),
        .ext_awcache  (4'd0),
        .ext_awprot   (3'd0),
        .ext_awvalid  (1'b0),
        .ext_awready  (ext_awready),
        .ext_wdata    (32'd0),
        .ext_wstrb    (4'd0),
        .ext_wlast    (1'b0),
        .ext_wvalid   (1'b0),
        .ext_wready   (ext_wready),
        .ext_bid      (ext_bid),
        .ext_bresp    (ext_bresp),
        .ext_bvalid   (ext_bvalid),
        .ext_bready   (1'b1),
        .ext_arid     (4'd0),
        .ext_araddr   (32'd0),
        .ext_arlen    (8'd0),
        .ext_arsize   (3'd0),
        .ext_arburst  (2'd0),
        .ext_arlock   (2'd0),
        .ext_arcache  (4'd0),
        .ext_arprot   (3'd0),
        .ext_arvalid  (1'b0),
        .ext_arready  (ext_arready),
        .ext_rid      (ext_rid),
        .ext_rdata    (ext_rdata),
        .ext_rresp    (ext_rresp),
        .ext_rlast    (ext_rlast),
        .ext_rvalid   (ext_rvalid),
        .ext_rready   (1'b1)
    );

    // synopsys translate_off
    task preload_sram_hex;
        input [1023:0] hex_path;
        begin
            u_impl.preload_sram_hex(hex_path);
        end
    endtask
    // synopsys translate_on

endmodule
