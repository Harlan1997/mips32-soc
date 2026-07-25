// =============================================================================
// File Name: soc_memory_subsystem.v
// Design:    SoC memory subsystem integration
// =============================================================================

module soc_memory_subsystem #(
    parameter ENABLE_FLASH_IMAGE_MODEL = 1'b0,
    parameter SRAM_DEPTH_WORDS = 32768
) (
    input  wire        clk,
    input  wire        rst_n,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    input  wire [3:0]  s0_awid,
    input  wire [31:0] s0_awaddr,
    input  wire [7:0]  s0_awlen,
    input  wire [2:0]  s0_awsize,
    input  wire [1:0]  s0_awburst,
    input  wire [1:0]  s0_awlock,
    input  wire [3:0]  s0_awcache,
    input  wire [2:0]  s0_awprot,
    input  wire        s0_awvalid,
    output wire        s0_awready,
    input  wire [31:0] s0_wdata,
    input  wire [3:0]  s0_wstrb,
    input  wire        s0_wlast,
    input  wire        s0_wvalid,
    output wire        s0_wready,
    output wire [3:0]  s0_bid,
    output wire [1:0]  s0_bresp,
    output wire        s0_bvalid,
    input  wire        s0_bready,
    input  wire [3:0]  s0_arid,
    input  wire [31:0] s0_araddr,
    input  wire [7:0]  s0_arlen,
    input  wire [2:0]  s0_arsize,
    input  wire [1:0]  s0_arburst,
    input  wire [1:0]  s0_arlock,
    input  wire [3:0]  s0_arcache,
    input  wire [2:0]  s0_arprot,
    input  wire        s0_arvalid,
    output wire        s0_arready,
    output wire [3:0]  s0_rid,
    output wire [31:0] s0_rdata,
    output wire [1:0]  s0_rresp,
    output wire        s0_rlast,
    output wire        s0_rvalid,
    input  wire        s0_rready,

    input  wire [3:0]  s2_awid,
    input  wire [31:0] s2_awaddr,
    input  wire [7:0]  s2_awlen,
    input  wire [2:0]  s2_awsize,
    input  wire [1:0]  s2_awburst,
    input  wire [1:0]  s2_awlock,
    input  wire [3:0]  s2_awcache,
    input  wire [2:0]  s2_awprot,
    input  wire        s2_awvalid,
    output wire        s2_awready,
    input  wire [31:0] s2_wdata,
    input  wire [3:0]  s2_wstrb,
    input  wire        s2_wlast,
    input  wire        s2_wvalid,
    output wire        s2_wready,
    output wire [3:0]  s2_bid,
    output wire [1:0]  s2_bresp,
    output wire        s2_bvalid,
    input  wire        s2_bready,
    input  wire [3:0]  s2_arid,
    input  wire [31:0] s2_araddr,
    input  wire [7:0]  s2_arlen,
    input  wire [2:0]  s2_arsize,
    input  wire [1:0]  s2_arburst,
    input  wire [1:0]  s2_arlock,
    input  wire [3:0]  s2_arcache,
    input  wire [2:0]  s2_arprot,
    input  wire        s2_arvalid,
    output wire        s2_arready,
    output wire [3:0]  s2_rid,
    output wire [31:0] s2_rdata,
    output wire [1:0]  s2_rresp,
    output wire        s2_rlast,
    output wire        s2_rvalid,
    input  wire        s2_rready
);

    axi_ddr_model #(
        .MEM_DEPTH_WORDS (SRAM_DEPTH_WORDS)
    ) u_axi_sram (
        .clk             (clk),
        .rst_n           (rst_n),

        .s_awid          (s0_awid),
        .s_awaddr        (s0_awaddr),
        .s_awlen         (s0_awlen),
        .s_awsize        (s0_awsize),
        .s_awburst       (s0_awburst),
        .s_awvalid       (s0_awvalid),
        .s_awready       (s0_awready),
        .s_wdata         (s0_wdata),
        .s_wstrb         (s0_wstrb),
        .s_wlast         (s0_wlast),
        .s_wvalid        (s0_wvalid),
        .s_wready        (s0_wready),
        .s_bid           (s0_bid),
        .s_bresp         (s0_bresp),
        .s_bvalid        (s0_bvalid),
        .s_bready        (s0_bready),
        .s_arid          (s0_arid),
        .s_araddr        (s0_araddr),
        .s_arlen         (s0_arlen),
        .s_arsize        (s0_arsize),
        .s_arburst       (s0_arburst),
        .s_arvalid       (s0_arvalid),
        .s_arready       (s0_arready),
        .s_rid           (s0_rid),
        .s_rdata         (s0_rdata),
        .s_rresp         (s0_rresp),
        .s_rlast         (s0_rlast),
        .s_rvalid        (s0_rvalid),
        .s_rready        (s0_rready)
    );

    // synopsys translate_off
    task preload_sram_hex;
        input [1023:0] hex_path;
        begin
            u_axi_sram.load_hex(hex_path);
        end
    endtask
    // synopsys translate_on

    generate
    if (ENABLE_FLASH_IMAGE_MODEL) begin : g_flash_image_model
        axi_flash_image_model u_axi_flash_image_model (
            .clk             (clk),
            .rst_n           (rst_n),

            .s_awid          (s2_awid),
            .s_awaddr        (s2_awaddr),
            .s_awlen         (s2_awlen),
            .s_awsize        (s2_awsize),
            .s_awburst       (s2_awburst),
            .s_awlock        (s2_awlock),
            .s_awcache       (s2_awcache),
            .s_awprot        (s2_awprot),
            .s_awvalid       (s2_awvalid),
            .s_awready       (s2_awready),
            .s_wdata         (s2_wdata),
            .s_wstrb         (s2_wstrb),
            .s_wlast         (s2_wlast),
            .s_wvalid        (s2_wvalid),
            .s_wready        (s2_wready),
            .s_bid           (s2_bid),
            .s_bresp         (s2_bresp),
            .s_bvalid        (s2_bvalid),
            .s_bready        (s2_bready),

            .s_arid          (s2_arid),
            .s_araddr        (s2_araddr),
            .s_arlen         (s2_arlen),
            .s_arsize        (s2_arsize),
            .s_arburst       (s2_arburst),
            .s_arlock        (s2_arlock),
            .s_arcache       (s2_arcache),
            .s_arprot        (s2_arprot),
            .s_arvalid       (s2_arvalid),
            .s_arready       (s2_arready),
            .s_rid           (s2_rid),
            .s_rdata         (s2_rdata),
            .s_rresp         (s2_rresp),
            .s_rlast         (s2_rlast),
            .s_rvalid        (s2_rvalid),
            .s_rready        (s2_rready),

            .spi_sclk        (spi_sclk),
            .spi_cs_n        (spi_cs_n),
            .spi_mosi        (spi_mosi),
            .spi_miso        (spi_miso)
        );
    end else begin : g_spi_flash_controller
        axi_spi_flash u_axi_spi_flash (
            .clk             (clk),
            .rst_n           (rst_n),

            .s_awid          (s2_awid),
            .s_awaddr        (s2_awaddr),
            .s_awlen         (s2_awlen),
            .s_awsize        (s2_awsize),
            .s_awburst       (s2_awburst),
            .s_awlock        (s2_awlock),
            .s_awcache       (s2_awcache),
            .s_awprot        (s2_awprot),
            .s_awvalid       (s2_awvalid),
            .s_awready       (s2_awready),
            .s_wdata         (s2_wdata),
            .s_wstrb         (s2_wstrb),
            .s_wlast         (s2_wlast),
            .s_wvalid        (s2_wvalid),
            .s_wready        (s2_wready),
            .s_bid           (s2_bid),
            .s_bresp         (s2_bresp),
            .s_bvalid        (s2_bvalid),
            .s_bready        (s2_bready),

            .s_arid          (s2_arid),
            .s_araddr        (s2_araddr),
            .s_arlen         (s2_arlen),
            .s_arsize        (s2_arsize),
            .s_arburst       (s2_arburst),
            .s_arlock        (s2_arlock),
            .s_arcache       (s2_arcache),
            .s_arprot        (s2_arprot),
            .s_arvalid       (s2_arvalid),
            .s_arready       (s2_arready),
            .s_rid           (s2_rid),
            .s_rdata         (s2_rdata),
            .s_rresp         (s2_rresp),
            .s_rlast         (s2_rlast),
            .s_rvalid        (s2_rvalid),
            .s_rready        (s2_rready),

            .spi_sclk        (spi_sclk),
            .spi_cs_n        (spi_cs_n),
            .spi_mosi        (spi_mosi),
            .spi_miso        (spi_miso)
        );
    end
    endgenerate

endmodule
