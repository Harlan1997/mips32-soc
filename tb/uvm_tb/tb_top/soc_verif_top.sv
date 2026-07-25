// =============================================================================
// File Name: soc_verif_top.sv
// Design:    Verification-only SoC wrapper
// =============================================================================

`include "soc_observation_if.sv"

module soc_verif_top (
    input  wire        clk,
    input  wire        rst_n,

    inout  wire [31:0] gpio_pins,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo,

    input  wire [3:0]  ext_awid,
    input  wire [31:0] ext_awaddr,
    input  wire [7:0]  ext_awlen,
    input  wire [2:0]  ext_awsize,
    input  wire [1:0]  ext_awburst,
    input  wire [1:0]  ext_awlock,
    input  wire [3:0]  ext_awcache,
    input  wire [2:0]  ext_awprot,
    input  wire        ext_awvalid,
    output wire        ext_awready,
    input  wire [31:0] ext_wdata,
    input  wire [3:0]  ext_wstrb,
    input  wire        ext_wlast,
    input  wire        ext_wvalid,
    output wire        ext_wready,
    output wire [3:0]  ext_bid,
    output wire [1:0]  ext_bresp,
    output wire        ext_bvalid,
    input  wire        ext_bready,
    input  wire [3:0]  ext_arid,
    input  wire [31:0] ext_araddr,
    input  wire [7:0]  ext_arlen,
    input  wire [2:0]  ext_arsize,
    input  wire [1:0]  ext_arburst,
    input  wire [1:0]  ext_arlock,
    input  wire [3:0]  ext_arcache,
    input  wire [2:0]  ext_arprot,
    input  wire        ext_arvalid,
    output wire        ext_arready,
    output wire [3:0]  ext_rid,
    output wire [31:0] ext_rdata,
    output wire [1:0]  ext_rresp,
    output wire        ext_rlast,
    output wire        ext_rvalid,
    input  wire        ext_rready,

    output wire [3:0]  s0_awid,
    output wire [31:0] s0_awaddr,
    output wire [7:0]  s0_awlen,
    output wire [2:0]  s0_awsize,
    output wire [1:0]  s0_awburst,
    output wire [1:0]  s0_awlock,
    output wire [3:0]  s0_awcache,
    output wire [2:0]  s0_awprot,
    output wire        s0_awvalid,
    output wire        s0_awready,
    output wire [31:0] s0_wdata,
    output wire [3:0]  s0_wstrb,
    output wire        s0_wlast,
    output wire        s0_wvalid,
    output wire        s0_wready,
    output wire [3:0]  s0_bid,
    output wire [1:0]  s0_bresp,
    output wire        s0_bvalid,
    output wire        s0_bready,
    output wire [3:0]  s0_arid,
    output wire [31:0] s0_araddr,
    output wire [7:0]  s0_arlen,
    output wire [2:0]  s0_arsize,
    output wire [1:0]  s0_arburst,
    output wire [1:0]  s0_arlock,
    output wire [3:0]  s0_arcache,
    output wire [2:0]  s0_arprot,
    output wire        s0_arvalid,
    output wire        s0_arready,
    output wire [3:0]  s0_rid,
    output wire [31:0] s0_rdata,
    output wire [1:0]  s0_rresp,
    output wire        s0_rlast,
    output wire        s0_rvalid,
    output wire        s0_rready,

    soc_observation_if.producer obs_if
);

    mips_soc_impl #(
        .ENABLE_EXT_AXI_MASTER (1'b1),
        .ENABLE_APB_FAULT_INJECTOR (1'b1),
        .ENABLE_FLASH_IMAGE_MODEL (1'b1)
    ) u_dut (
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
        .tdo          (tdo),

        .ext_awid     (ext_awid),
        .ext_awaddr   (ext_awaddr),
        .ext_awlen    (ext_awlen),
        .ext_awsize   (ext_awsize),
        .ext_awburst  (ext_awburst),
        .ext_awlock   (ext_awlock),
        .ext_awcache  (ext_awcache),
        .ext_awprot   (ext_awprot),
        .ext_awvalid  (ext_awvalid),
        .ext_awready  (ext_awready),
        .ext_wdata    (ext_wdata),
        .ext_wstrb    (ext_wstrb),
        .ext_wlast    (ext_wlast),
        .ext_wvalid   (ext_wvalid),
        .ext_wready   (ext_wready),
        .ext_bid      (ext_bid),
        .ext_bresp    (ext_bresp),
        .ext_bvalid   (ext_bvalid),
        .ext_bready   (ext_bready),
        .ext_arid     (ext_arid),
        .ext_araddr   (ext_araddr),
        .ext_arlen    (ext_arlen),
        .ext_arsize   (ext_arsize),
        .ext_arburst  (ext_arburst),
        .ext_arlock   (ext_arlock),
        .ext_arcache  (ext_arcache),
        .ext_arprot   (ext_arprot),
        .ext_arvalid  (ext_arvalid),
        .ext_arready  (ext_arready),
        .ext_rid      (ext_rid),
        .ext_rdata    (ext_rdata),
        .ext_rresp    (ext_rresp),
        .ext_rlast    (ext_rlast),
        .ext_rvalid   (ext_rvalid),
        .ext_rready   (ext_rready)
    );

    assign s0_awid     = u_dut.s0_awid;
    assign s0_awaddr   = u_dut.s0_awaddr;
    assign s0_awlen    = u_dut.s0_awlen;
    assign s0_awsize   = u_dut.s0_awsize;
    assign s0_awburst  = u_dut.s0_awburst;
    assign s0_awlock   = u_dut.s0_awlock;
    assign s0_awcache  = u_dut.s0_awcache;
    assign s0_awprot   = u_dut.s0_awprot;
    assign s0_awvalid  = u_dut.s0_awvalid;
    assign s0_awready  = u_dut.s0_awready;
    assign s0_wdata    = u_dut.s0_wdata;
    assign s0_wstrb    = u_dut.s0_wstrb;
    assign s0_wlast    = u_dut.s0_wlast;
    assign s0_wvalid   = u_dut.s0_wvalid;
    assign s0_wready   = u_dut.s0_wready;
    assign s0_bid      = u_dut.s0_bid;
    assign s0_bresp    = u_dut.s0_bresp;
    assign s0_bvalid   = u_dut.s0_bvalid;
    assign s0_bready   = u_dut.s0_bready;
    assign s0_arid     = u_dut.s0_arid;
    assign s0_araddr   = u_dut.s0_araddr;
    assign s0_arlen    = u_dut.s0_arlen;
    assign s0_arsize   = u_dut.s0_arsize;
    assign s0_arburst  = u_dut.s0_arburst;
    assign s0_arlock   = u_dut.s0_arlock;
    assign s0_arcache  = u_dut.s0_arcache;
    assign s0_arprot   = u_dut.s0_arprot;
    assign s0_arvalid  = u_dut.s0_arvalid;
    assign s0_arready  = u_dut.s0_arready;
    assign s0_rid      = u_dut.s0_rid;
    assign s0_rdata    = u_dut.s0_rdata;
    assign s0_rresp    = u_dut.s0_rresp;
    assign s0_rlast    = u_dut.s0_rlast;
    assign s0_rvalid   = u_dut.s0_rvalid;
    assign s0_rready   = u_dut.s0_rready;

endmodule
