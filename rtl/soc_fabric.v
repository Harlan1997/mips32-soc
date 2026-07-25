// =============================================================================
// File Name: soc_fabric.v
// Design:    SoC AXI fabric integration
// =============================================================================

module soc_fabric #(
    parameter ENABLE_EXT_AXI_MASTER = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  m0_arid,
    input  wire [31:0] m0_araddr,
    input  wire [7:0]  m0_arlen,
    input  wire [2:0]  m0_arsize,
    input  wire [1:0]  m0_arburst,
    input  wire [1:0]  m0_arlock,
    input  wire [3:0]  m0_arcache,
    input  wire [2:0]  m0_arprot,
    input  wire        m0_arvalid,
    input  wire        m0_rready,
    output wire        m0_arready,
    output wire [3:0]  m0_rid,
    output wire [31:0] m0_rdata,
    output wire [1:0]  m0_rresp,
    output wire        m0_rlast,
    output wire        m0_rvalid,
    input  wire [3:0]  m1_awid,
    input  wire [31:0] m1_awaddr,
    input  wire [7:0]  m1_awlen,
    input  wire [2:0]  m1_awsize,
    input  wire [1:0]  m1_awburst,
    input  wire [1:0]  m1_awlock,
    input  wire [3:0]  m1_awcache,
    input  wire [2:0]  m1_awprot,
    input  wire        m1_awvalid,
    input  wire [31:0] m1_wdata,
    input  wire [3:0]  m1_wstrb,
    input  wire        m1_wlast,
    input  wire        m1_wvalid,
    input  wire        m1_bready,
    input  wire [3:0]  m1_arid,
    input  wire [31:0] m1_araddr,
    input  wire [7:0]  m1_arlen,
    input  wire [2:0]  m1_arsize,
    input  wire [1:0]  m1_arburst,
    input  wire [1:0]  m1_arlock,
    input  wire [3:0]  m1_arcache,
    input  wire [2:0]  m1_arprot,
    input  wire        m1_arvalid,
    input  wire        m1_rready,
    output wire        m1_awready,
    output wire        m1_wready,
    output wire [3:0]  m1_bid,
    output wire [1:0]  m1_bresp,
    output wire        m1_bvalid,
    output wire        m1_arready,
    output wire [3:0]  m1_rid,
    output wire [31:0] m1_rdata,
    output wire [1:0]  m1_rresp,
    output wire        m1_rlast,
    output wire        m1_rvalid,
    input  wire [3:0]  m2_awid,
    input  wire [31:0] m2_awaddr,
    input  wire [7:0]  m2_awlen,
    input  wire [2:0]  m2_awsize,
    input  wire [1:0]  m2_awburst,
    input  wire [1:0]  m2_awlock,
    input  wire [3:0]  m2_awcache,
    input  wire [2:0]  m2_awprot,
    input  wire        m2_awvalid,
    input  wire [31:0] m2_wdata,
    input  wire [3:0]  m2_wstrb,
    input  wire        m2_wlast,
    input  wire        m2_wvalid,
    input  wire        m2_bready,
    input  wire [3:0]  m2_arid,
    input  wire [31:0] m2_araddr,
    input  wire [7:0]  m2_arlen,
    input  wire [2:0]  m2_arsize,
    input  wire [1:0]  m2_arburst,
    input  wire [1:0]  m2_arlock,
    input  wire [3:0]  m2_arcache,
    input  wire [2:0]  m2_arprot,
    input  wire        m2_arvalid,
    input  wire        m2_rready,
    output wire        m2_awready,
    output wire        m2_wready,
    output wire [3:0]  m2_bid,
    output wire [1:0]  m2_bresp,
    output wire        m2_bvalid,
    output wire        m2_arready,
    output wire [3:0]  m2_rid,
    output wire [31:0] m2_rdata,
    output wire [1:0]  m2_rresp,
    output wire        m2_rlast,
    output wire        m2_rvalid,
    input  wire [3:0]  jtag_awid,
    input  wire [31:0] jtag_awaddr,
    input  wire [7:0]  jtag_awlen,
    input  wire [2:0]  jtag_awsize,
    input  wire [1:0]  jtag_awburst,
    input  wire [1:0]  jtag_awlock,
    input  wire [3:0]  jtag_awcache,
    input  wire [2:0]  jtag_awprot,
    input  wire        jtag_awvalid,
    input  wire [31:0] jtag_wdata,
    input  wire [3:0]  jtag_wstrb,
    input  wire        jtag_wlast,
    input  wire        jtag_wvalid,
    input  wire        jtag_bready,
    input  wire [3:0]  jtag_arid,
    input  wire [31:0] jtag_araddr,
    input  wire [7:0]  jtag_arlen,
    input  wire [2:0]  jtag_arsize,
    input  wire [1:0]  jtag_arburst,
    input  wire [1:0]  jtag_arlock,
    input  wire [3:0]  jtag_arcache,
    input  wire [2:0]  jtag_arprot,
    input  wire        jtag_arvalid,
    input  wire        jtag_rready,
    output wire        jtag_awready,
    output wire        jtag_wready,
    output wire [3:0]  jtag_bid,
    output wire [1:0]  jtag_bresp,
    output wire        jtag_bvalid,
    output wire        jtag_arready,
    output wire [3:0]  jtag_rid,
    output wire [31:0] jtag_rdata,
    output wire [1:0]  jtag_rresp,
    output wire        jtag_rlast,
    output wire        jtag_rvalid,
    input  wire [3:0]  ext_awid,
    input  wire [31:0] ext_awaddr,
    input  wire [7:0]  ext_awlen,
    input  wire [2:0]  ext_awsize,
    input  wire [1:0]  ext_awburst,
    input  wire [1:0]  ext_awlock,
    input  wire [3:0]  ext_awcache,
    input  wire [2:0]  ext_awprot,
    input  wire        ext_awvalid,
    input  wire [31:0] ext_wdata,
    input  wire [3:0]  ext_wstrb,
    input  wire        ext_wlast,
    input  wire        ext_wvalid,
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
    input  wire        ext_rready,
    output wire        ext_awready,
    output wire        ext_wready,
    output wire [3:0]  ext_bid,
    output wire [1:0]  ext_bresp,
    output wire        ext_bvalid,
    output wire        ext_arready,
    output wire [3:0]  ext_rid,
    output wire [31:0] ext_rdata,
    output wire [1:0]  ext_rresp,
    output wire        ext_rlast,
    output wire        ext_rvalid,
    output wire [3:0]  s0_awid,
    output wire [31:0] s0_awaddr,
    output wire [7:0]  s0_awlen,
    output wire [2:0]  s0_awsize,
    output wire [1:0]  s0_awburst,
    output wire [1:0]  s0_awlock,
    output wire [3:0]  s0_awcache,
    output wire [2:0]  s0_awprot,
    output wire        s0_awvalid,
    output wire [31:0] s0_wdata,
    output wire [3:0]  s0_wstrb,
    output wire        s0_wlast,
    output wire        s0_wvalid,
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
    output wire        s0_rready,
    input  wire        s0_awready,
    input  wire        s0_wready,
    input  wire [3:0]  s0_bid,
    input  wire [1:0]  s0_bresp,
    input  wire        s0_bvalid,
    input  wire        s0_arready,
    input  wire [3:0]  s0_rid,
    input  wire [31:0] s0_rdata,
    input  wire [1:0]  s0_rresp,
    input  wire        s0_rlast,
    input  wire        s0_rvalid,
    output wire [3:0]  s1_awid,
    output wire [31:0] s1_awaddr,
    output wire [7:0]  s1_awlen,
    output wire [2:0]  s1_awsize,
    output wire [1:0]  s1_awburst,
    output wire [1:0]  s1_awlock,
    output wire [3:0]  s1_awcache,
    output wire [2:0]  s1_awprot,
    output wire        s1_awvalid,
    output wire [31:0] s1_wdata,
    output wire [3:0]  s1_wstrb,
    output wire        s1_wlast,
    output wire        s1_wvalid,
    output wire        s1_bready,
    output wire [3:0]  s1_arid,
    output wire [31:0] s1_araddr,
    output wire [7:0]  s1_arlen,
    output wire [2:0]  s1_arsize,
    output wire [1:0]  s1_arburst,
    output wire [1:0]  s1_arlock,
    output wire [3:0]  s1_arcache,
    output wire [2:0]  s1_arprot,
    output wire        s1_arvalid,
    output wire        s1_rready,
    input  wire        s1_awready,
    input  wire        s1_wready,
    input  wire [3:0]  s1_bid,
    input  wire [1:0]  s1_bresp,
    input  wire        s1_bvalid,
    input  wire        s1_arready,
    input  wire [3:0]  s1_rid,
    input  wire [31:0] s1_rdata,
    input  wire [1:0]  s1_rresp,
    input  wire        s1_rlast,
    input  wire        s1_rvalid,
    output wire [3:0]  s2_awid,
    output wire [31:0] s2_awaddr,
    output wire [7:0]  s2_awlen,
    output wire [2:0]  s2_awsize,
    output wire [1:0]  s2_awburst,
    output wire [1:0]  s2_awlock,
    output wire [3:0]  s2_awcache,
    output wire [2:0]  s2_awprot,
    output wire        s2_awvalid,
    output wire [31:0] s2_wdata,
    output wire [3:0]  s2_wstrb,
    output wire        s2_wlast,
    output wire        s2_wvalid,
    output wire        s2_bready,
    output wire [3:0]  s2_arid,
    output wire [31:0] s2_araddr,
    output wire [7:0]  s2_arlen,
    output wire [2:0]  s2_arsize,
    output wire [1:0]  s2_arburst,
    output wire [1:0]  s2_arlock,
    output wire [3:0]  s2_arcache,
    output wire [2:0]  s2_arprot,
    output wire        s2_arvalid,
    output wire        s2_rready,
    input  wire        s2_awready,
    input  wire        s2_wready,
    input  wire [3:0]  s2_bid,
    input  wire [1:0]  s2_bresp,
    input  wire        s2_bvalid,
    input  wire        s2_arready,
    input  wire [3:0]  s2_rid,
    input  wire [31:0] s2_rdata,
    input  wire [1:0]  s2_rresp,
    input  wire        s2_rlast,
    input  wire        s2_rvalid
);

    // Internal cascaded fabric links. These stay private to the fabric boundary.
    wire [3:0]  axim_awid;
    wire [31:0] axim_awaddr;
    wire [7:0]  axim_awlen;
    wire [2:0]  axim_awsize;
    wire [1:0]  axim_awburst;
    wire [1:0]  axim_awlock;
    wire [3:0]  axim_awcache;
    wire [2:0]  axim_awprot;
    wire        axim_awvalid;
    wire [31:0] axim_wdata;
    wire [3:0]  axim_wstrb;
    wire        axim_wlast;
    wire        axim_wvalid;
    wire        axim_bready;
    wire [3:0]  axim_arid;
    wire [31:0] axim_araddr;
    wire [7:0]  axim_arlen;
    wire [2:0]  axim_arsize;
    wire [1:0]  axim_arburst;
    wire [1:0]  axim_arlock;
    wire [3:0]  axim_arcache;
    wire [2:0]  axim_arprot;
    wire        axim_arvalid;
    wire        axim_rready;
    wire        axim_awready;
    wire        axim_wready;
    wire [3:0]  axim_bid;
    wire [1:0]  axim_bresp;
    wire        axim_bvalid;
    wire        axim_arready;
    wire [3:0]  axim_rid;
    wire [31:0] axim_rdata;
    wire [1:0]  axim_rresp;
    wire        axim_rlast;
    wire        axim_rvalid;

    wire [3:0]  axim2_awid;
    wire [31:0] axim2_awaddr;
    wire [7:0]  axim2_awlen;
    wire [2:0]  axim2_awsize;
    wire [1:0]  axim2_awburst;
    wire [1:0]  axim2_awlock;
    wire [3:0]  axim2_awcache;
    wire [2:0]  axim2_awprot;
    wire        axim2_awvalid;
    wire [31:0] axim2_wdata;
    wire [3:0]  axim2_wstrb;
    wire        axim2_wlast;
    wire        axim2_wvalid;
    wire        axim2_bready;
    wire [3:0]  axim2_arid;
    wire [31:0] axim2_araddr;
    wire [7:0]  axim2_arlen;
    wire [2:0]  axim2_arsize;
    wire [1:0]  axim2_arburst;
    wire [1:0]  axim2_arlock;
    wire [3:0]  axim2_arcache;
    wire [2:0]  axim2_arprot;
    wire        axim2_arvalid;
    wire        axim2_rready;
    wire        axim2_awready;
    wire        axim2_wready;
    wire [3:0]  axim2_bid;
    wire [1:0]  axim2_bresp;
    wire        axim2_bvalid;
    wire        axim2_arready;
    wire [3:0]  axim2_rid;
    wire [31:0] axim2_rdata;
    wire [1:0]  axim2_rresp;
    wire        axim2_rlast;
    wire        axim2_rvalid;

    wire [3:0]  axim3_awid;
    wire [31:0] axim3_awaddr;
    wire [7:0]  axim3_awlen;
    wire [2:0]  axim3_awsize;
    wire [1:0]  axim3_awburst;
    wire [1:0]  axim3_awlock;
    wire [3:0]  axim3_awcache;
    wire [2:0]  axim3_awprot;
    wire        axim3_awvalid;
    wire [31:0] axim3_wdata;
    wire [3:0]  axim3_wstrb;
    wire        axim3_wlast;
    wire        axim3_wvalid;
    wire        axim3_bready;
    wire [3:0]  axim3_arid;
    wire [31:0] axim3_araddr;
    wire [7:0]  axim3_arlen;
    wire [2:0]  axim3_arsize;
    wire [1:0]  axim3_arburst;
    wire [1:0]  axim3_arlock;
    wire [3:0]  axim3_arcache;
    wire [2:0]  axim3_arprot;
    wire        axim3_arvalid;
    wire        axim3_rready;
    wire        axim3_awready;
    wire        axim3_wready;
    wire [3:0]  axim3_bid;
    wire [1:0]  axim3_bresp;
    wire        axim3_bvalid;
    wire        axim3_arready;
    wire [3:0]  axim3_rid;
    wire [31:0] axim3_rdata;
    wire [1:0]  axim3_rresp;
    wire        axim3_rlast;
    wire        axim3_rvalid;

    wire [3:0]  axim4_awid;
    wire [31:0] axim4_awaddr;
    wire [7:0]  axim4_awlen;
    wire [2:0]  axim4_awsize;
    wire [1:0]  axim4_awburst;
    wire [1:0]  axim4_awlock;
    wire [3:0]  axim4_awcache;
    wire [2:0]  axim4_awprot;
    wire        axim4_awvalid;
    wire [31:0] axim4_wdata;
    wire [3:0]  axim4_wstrb;
    wire        axim4_wlast;
    wire        axim4_wvalid;
    wire        axim4_bready;
    wire [3:0]  axim4_arid;
    wire [31:0] axim4_araddr;
    wire [7:0]  axim4_arlen;
    wire [2:0]  axim4_arsize;
    wire [1:0]  axim4_arburst;
    wire [1:0]  axim4_arlock;
    wire [3:0]  axim4_arcache;
    wire [2:0]  axim4_arprot;
    wire        axim4_arvalid;
    wire        axim4_rready;
    wire        axim4_awready;
    wire        axim4_wready;
    wire [3:0]  axim4_bid;
    wire [1:0]  axim4_bresp;
    wire        axim4_bvalid;
    wire        axim4_arready;
    wire [3:0]  axim4_rid;
    wire [31:0] axim4_rdata;
    wire [1:0]  axim4_rresp;
    wire        axim4_rlast;
    wire        axim4_rvalid;

    axi_arbiter_2x1 u_axi_arbiter (
        .clk             (clk),
        .rst_n           (rst_n),

        .m0_arid         (m0_arid),
        .m0_araddr       (m0_araddr),
        .m0_arlen        (m0_arlen),
        .m0_arsize       (m0_arsize),
        .m0_arburst      (m0_arburst),
        .m0_arlock       (m0_arlock),
        .m0_arcache      (m0_arcache),
        .m0_arprot       (m0_arprot),
        .m0_arvalid      (m0_arvalid),
        .m0_arready      (m0_arready),
        .m0_rid          (m0_rid),
        .m0_rdata        (m0_rdata),
        .m0_rresp        (m0_rresp),
        .m0_rlast        (m0_rlast),
        .m0_rvalid       (m0_rvalid),
        .m0_rready       (m0_rready),

        .m1_awid         (m1_awid),
        .m1_awaddr       (m1_awaddr),
        .m1_awlen        (m1_awlen),
        .m1_awsize       (m1_awsize),
        .m1_awburst      (m1_awburst),
        .m1_awlock       (m1_awlock),
        .m1_awcache      (m1_awcache),
        .m1_awprot       (m1_awprot),
        .m1_awvalid      (m1_awvalid),
        .m1_awready      (m1_awready),
        .m1_wdata        (m1_wdata),
        .m1_wstrb        (m1_wstrb),
        .m1_wlast        (m1_wlast),
        .m1_wvalid       (m1_wvalid),
        .m1_wready       (m1_wready),
        .m1_bid          (m1_bid),
        .m1_bresp        (m1_bresp),
        .m1_bvalid       (m1_bvalid),
        .m1_bready       (m1_bready),
        .m1_arid         (m1_arid),
        .m1_araddr       (m1_araddr),
        .m1_arlen        (m1_arlen),
        .m1_arsize       (m1_arsize),
        .m1_arburst      (m1_arburst),
        .m1_arlock       (m1_arlock),
        .m1_arcache      (m1_arcache),
        .m1_arprot       (m1_arprot),
        .m1_arvalid      (m1_arvalid),
        .m1_arready      (m1_arready),
        .m1_rid          (m1_rid),
        .m1_rdata        (m1_rdata),
        .m1_rresp        (m1_rresp),
        .m1_rlast        (m1_rlast),
        .m1_rvalid       (m1_rvalid),
        .m1_rready       (m1_rready),

        .s0_awid         (axim_awid),
        .s0_awaddr       (axim_awaddr),
        .s0_awlen        (axim_awlen),
        .s0_awsize       (axim_awsize),
        .s0_awburst      (axim_awburst),
        .s0_awlock       (axim_awlock),
        .s0_awcache      (axim_awcache),
        .s0_awprot       (axim_awprot),
        .s0_awvalid      (axim_awvalid),
        .s0_awready      (axim_awready),
        .s0_wdata        (axim_wdata),
        .s0_wstrb        (axim_wstrb),
        .s0_wlast        (axim_wlast),
        .s0_wvalid       (axim_wvalid),
        .s0_wready       (axim_wready),
        .s0_bid          (axim_bid),
        .s0_bresp        (axim_bresp),
        .s0_bvalid       (axim_bvalid),
        .s0_bready       (axim_bready),
        .s0_arid         (axim_arid),
        .s0_araddr       (axim_araddr),
        .s0_arlen        (axim_arlen),
        .s0_arsize       (axim_arsize),
        .s0_arburst      (axim_arburst),
        .s0_arlock       (axim_arlock),
        .s0_arcache      (axim_arcache),
        .s0_arprot       (axim_arprot),
        .s0_arvalid      (axim_arvalid),
        .s0_arready      (axim_arready),
        .s0_rid          (axim_rid),
        .s0_rdata        (axim_rdata),
        .s0_rresp        (axim_rresp),
        .s0_rlast        (axim_rlast),
        .s0_rvalid       (axim_rvalid),
        .s0_rready       (axim_rready)
    );
    axi_arbiter_2x1_full u_axi_arbiter_2 (
        .clk             (clk),
        .rst_n           (rst_n),

        .m0_arid         (axim_arid),
        .m0_araddr       (axim_araddr),
        .m0_arlen        (axim_arlen),
        .m0_arsize       (axim_arsize),
        .m0_arburst      (axim_arburst),
        .m0_arlock       (axim_arlock),
        .m0_arcache      (axim_arcache),
        .m0_arprot       (axim_arprot),
        .m0_arvalid      (axim_arvalid),
        .m0_arready      (axim_arready),
        .m0_rid          (axim_rid),
        .m0_rdata        (axim_rdata),
        .m0_rresp        (axim_rresp),
        .m0_rlast        (axim_rlast),
        .m0_rvalid       (axim_rvalid),
        .m0_rready       (axim_rready),

        .m0_awid         (axim_awid),
        .m0_awaddr       (axim_awaddr),
        .m0_awlen        (axim_awlen),
        .m0_awsize       (axim_awsize),
        .m0_awburst      (axim_awburst),
        .m0_awlock       (axim_awlock),
        .m0_awcache      (axim_awcache),
        .m0_awprot       (axim_awprot),
        .m0_awvalid      (axim_awvalid),
        .m0_awready      (axim_awready),
        .m0_wdata        (axim_wdata),
        .m0_wstrb        (axim_wstrb),
        .m0_wlast        (axim_wlast),
        .m0_wvalid       (axim_wvalid),
        .m0_wready       (axim_wready),
        .m0_bid          (axim_bid),
        .m0_bresp        (axim_bresp),
        .m0_bvalid       (axim_bvalid),
        .m0_bready       (axim_bready),

        .m1_arid         (m2_arid),
        .m1_araddr       (m2_araddr),
        .m1_arlen        (m2_arlen),
        .m1_arsize       (m2_arsize),
        .m1_arburst      (m2_arburst),
        .m1_arlock       (m2_arlock),
        .m1_arcache      (m2_arcache),
        .m1_arprot       (m2_arprot),
        .m1_arvalid      (m2_arvalid),
        .m1_arready      (m2_arready),
        .m1_rid          (m2_rid),
        .m1_rdata        (m2_rdata),
        .m1_rresp        (m2_rresp),
        .m1_rlast        (m2_rlast),
        .m1_rvalid       (m2_rvalid),
        .m1_rready       (m2_rready),

        .m1_awid         (m2_awid),
        .m1_awaddr       (m2_awaddr),
        .m1_awlen        (m2_awlen),
        .m1_awsize       (m2_awsize),
        .m1_awburst      (m2_awburst),
        .m1_awlock       (m2_awlock),
        .m1_awcache      (m2_awcache),
        .m1_awprot       (m2_awprot),
        .m1_awvalid      (m2_awvalid),
        .m1_awready      (m2_awready),
        .m1_wdata        (m2_wdata),
        .m1_wstrb        (m2_wstrb),
        .m1_wlast        (m2_wlast),
        .m1_wvalid       (m2_wvalid),
        .m1_wready       (m2_wready),
        .m1_bid          (m2_bid),
        .m1_bresp        (m2_bresp),
        .m1_bvalid       (m2_bvalid),
        .m1_bready       (m2_bready),

        .s0_awid         (axim2_awid),
        .s0_awaddr       (axim2_awaddr),
        .s0_awlen        (axim2_awlen),
        .s0_awsize       (axim2_awsize),
        .s0_awburst      (axim2_awburst),
        .s0_awlock       (axim2_awlock),
        .s0_awcache      (axim2_awcache),
        .s0_awprot       (axim2_awprot),
        .s0_awvalid      (axim2_awvalid),
        .s0_awready      (axim2_awready),
        .s0_wdata        (axim2_wdata),
        .s0_wstrb        (axim2_wstrb),
        .s0_wlast        (axim2_wlast),
        .s0_wvalid       (axim2_wvalid),
        .s0_wready       (axim2_wready),
        .s0_bid          (axim2_bid),
        .s0_bresp        (axim2_bresp),
        .s0_bvalid       (axim2_bvalid),
        .s0_bready       (axim2_bready),
        .s0_arid         (axim2_arid),
        .s0_araddr       (axim2_araddr),
        .s0_arlen        (axim2_arlen),
        .s0_arsize       (axim2_arsize),
        .s0_arburst      (axim2_arburst),
        .s0_arlock       (axim2_arlock),
        .s0_arcache      (axim2_arcache),
        .s0_arprot       (axim2_arprot),
        .s0_arvalid      (axim2_arvalid),
        .s0_arready      (axim2_arready),
        .s0_rid          (axim2_rid),
        .s0_rdata        (axim2_rdata),
        .s0_rresp        (axim2_rresp),
        .s0_rlast        (axim2_rlast),
        .s0_rvalid       (axim2_rvalid),
        .s0_rready       (axim2_rready)
    );

    axi_arbiter_2x1_full u_axi_arbiter_3 (
        .clk             (clk),
        .rst_n           (rst_n),

        .m0_arid         (axim2_arid),
        .m0_araddr       (axim2_araddr),
        .m0_arlen        (axim2_arlen),
        .m0_arsize       (axim2_arsize),
        .m0_arburst      (axim2_arburst),
        .m0_arlock       (axim2_arlock),
        .m0_arcache      (axim2_arcache),
        .m0_arprot       (axim2_arprot),
        .m0_arvalid      (axim2_arvalid),
        .m0_arready      (axim2_arready),
        .m0_rid          (axim2_rid),
        .m0_rdata        (axim2_rdata),
        .m0_rresp        (axim2_rresp),
        .m0_rlast        (axim2_rlast),
        .m0_rvalid       (axim2_rvalid),
        .m0_rready       (axim2_rready),

        .m0_awid         (axim2_awid),
        .m0_awaddr       (axim2_awaddr),
        .m0_awlen        (axim2_awlen),
        .m0_awsize       (axim2_awsize),
        .m0_awburst      (axim2_awburst),
        .m0_awlock       (axim2_awlock),
        .m0_awcache      (axim2_awcache),
        .m0_awprot       (axim2_awprot),
        .m0_awvalid      (axim2_awvalid),
        .m0_awready      (axim2_awready),
        .m0_wdata        (axim2_wdata),
        .m0_wstrb        (axim2_wstrb),
        .m0_wlast        (axim2_wlast),
        .m0_wvalid       (axim2_wvalid),
        .m0_wready       (axim2_wready),
        .m0_bid          (axim2_bid),
        .m0_bresp        (axim2_bresp),
        .m0_bvalid       (axim2_bvalid),
        .m0_bready       (axim2_bready),

        .m1_arid         (jtag_arid),
        .m1_araddr       (jtag_araddr),
        .m1_arlen        (jtag_arlen),
        .m1_arsize       (jtag_arsize),
        .m1_arburst      (jtag_arburst),
        .m1_arlock       (jtag_arlock),
        .m1_arcache      (jtag_arcache),
        .m1_arprot       (jtag_arprot),
        .m1_arvalid      (jtag_arvalid),
        .m1_arready      (jtag_arready),
        .m1_rid          (jtag_rid),
        .m1_rdata        (jtag_rdata),
        .m1_rresp        (jtag_rresp),
        .m1_rlast        (jtag_rlast),
        .m1_rvalid       (jtag_rvalid),
        .m1_rready       (jtag_rready),

        .m1_awid         (jtag_awid),
        .m1_awaddr       (jtag_awaddr),
        .m1_awlen        (jtag_awlen),
        .m1_awsize       (jtag_awsize),
        .m1_awburst      (jtag_awburst),
        .m1_awlock       (jtag_awlock),
        .m1_awcache      (jtag_awcache),
        .m1_awprot       (jtag_awprot),
        .m1_awvalid      (jtag_awvalid),
        .m1_awready      (jtag_awready),
        .m1_wdata        (jtag_wdata),
        .m1_wstrb        (jtag_wstrb),
        .m1_wlast        (jtag_wlast),
        .m1_wvalid       (jtag_wvalid),
        .m1_wready       (jtag_wready),
        .m1_bid          (jtag_bid),
        .m1_bresp        (jtag_bresp),
        .m1_bvalid       (jtag_bvalid),
        .m1_bready       (jtag_bready),

        .s0_awid         (axim3_awid),
        .s0_awaddr       (axim3_awaddr),
        .s0_awlen        (axim3_awlen),
        .s0_awsize       (axim3_awsize),
        .s0_awburst      (axim3_awburst),
        .s0_awlock       (axim3_awlock),
        .s0_awcache      (axim3_awcache),
        .s0_awprot       (axim3_awprot),
        .s0_awvalid      (axim3_awvalid),
        .s0_awready      (axim3_awready),
        .s0_wdata        (axim3_wdata),
        .s0_wstrb        (axim3_wstrb),
        .s0_wlast        (axim3_wlast),
        .s0_wvalid       (axim3_wvalid),
        .s0_wready       (axim3_wready),
        .s0_bid          (axim3_bid),
        .s0_bresp        (axim3_bresp),
        .s0_bvalid       (axim3_bvalid),
        .s0_bready       (axim3_bready),
        .s0_arid         (axim3_arid),
        .s0_araddr       (axim3_araddr),
        .s0_arlen        (axim3_arlen),
        .s0_arsize       (axim3_arsize),
        .s0_arburst      (axim3_arburst),
        .s0_arlock       (axim3_arlock),
        .s0_arcache      (axim3_arcache),
        .s0_arprot       (axim3_arprot),
        .s0_arvalid      (axim3_arvalid),
        .s0_arready      (axim3_arready),
        .s0_rid          (axim3_rid),
        .s0_rdata        (axim3_rdata),
        .s0_rresp        (axim3_rresp),
        .s0_rlast        (axim3_rlast),
        .s0_rvalid       (axim3_rvalid),
        .s0_rready       (axim3_rready)
    );

    generate
    if (ENABLE_EXT_AXI_MASTER) begin : g_ext_axi_master
    axi_arbiter_2x1_full u_axi_arbiter_4 (
        .clk             (clk),
        .rst_n           (rst_n),

        .m0_arid         (axim3_arid),
        .m0_araddr       (axim3_araddr),
        .m0_arlen        (axim3_arlen),
        .m0_arsize       (axim3_arsize),
        .m0_arburst      (axim3_arburst),
        .m0_arlock       (axim3_arlock),
        .m0_arcache      (axim3_arcache),
        .m0_arprot       (axim3_arprot),
        .m0_arvalid      (axim3_arvalid),
        .m0_arready      (axim3_arready),
        .m0_rid          (axim3_rid),
        .m0_rdata        (axim3_rdata),
        .m0_rresp        (axim3_rresp),
        .m0_rlast        (axim3_rlast),
        .m0_rvalid       (axim3_rvalid),
        .m0_rready       (axim3_rready),

        .m0_awid         (axim3_awid),
        .m0_awaddr       (axim3_awaddr),
        .m0_awlen        (axim3_awlen),
        .m0_awsize       (axim3_awsize),
        .m0_awburst      (axim3_awburst),
        .m0_awlock       (axim3_awlock),
        .m0_awcache      (axim3_awcache),
        .m0_awprot       (axim3_awprot),
        .m0_awvalid      (axim3_awvalid),
        .m0_awready      (axim3_awready),
        .m0_wdata        (axim3_wdata),
        .m0_wstrb        (axim3_wstrb),
        .m0_wlast        (axim3_wlast),
        .m0_wvalid       (axim3_wvalid),
        .m0_wready       (axim3_wready),
        .m0_bid          (axim3_bid),
        .m0_bresp        (axim3_bresp),
        .m0_bvalid       (axim3_bvalid),
        .m0_bready       (axim3_bready),

        .m1_arid         (ext_arid),
        .m1_araddr       (ext_araddr),
        .m1_arlen        (ext_arlen),
        .m1_arsize       (ext_arsize),
        .m1_arburst      (ext_arburst),
        .m1_arlock       (ext_arlock),
        .m1_arcache      (ext_arcache),
        .m1_arprot       (ext_arprot),
        .m1_arvalid      (ext_arvalid),
        .m1_arready      (ext_arready),
        .m1_rid          (ext_rid),
        .m1_rdata        (ext_rdata),
        .m1_rresp        (ext_rresp),
        .m1_rlast        (ext_rlast),
        .m1_rvalid       (ext_rvalid),
        .m1_rready       (ext_rready),

        .m1_awid         (ext_awid),
        .m1_awaddr       (ext_awaddr),
        .m1_awlen        (ext_awlen),
        .m1_awsize       (ext_awsize),
        .m1_awburst      (ext_awburst),
        .m1_awlock       (ext_awlock),
        .m1_awcache      (ext_awcache),
        .m1_awprot       (ext_awprot),
        .m1_awvalid      (ext_awvalid),
        .m1_awready      (ext_awready),
        .m1_wdata        (ext_wdata),
        .m1_wstrb        (ext_wstrb),
        .m1_wlast        (ext_wlast),
        .m1_wvalid       (ext_wvalid),
        .m1_wready       (ext_wready),
        .m1_bid          (ext_bid),
        .m1_bresp        (ext_bresp),
        .m1_bvalid       (ext_bvalid),
        .m1_bready       (ext_bready),

        .s0_awid         (axim4_awid),
        .s0_awaddr       (axim4_awaddr),
        .s0_awlen        (axim4_awlen),
        .s0_awsize       (axim4_awsize),
        .s0_awburst      (axim4_awburst),
        .s0_awlock       (axim4_awlock),
        .s0_awcache      (axim4_awcache),
        .s0_awprot       (axim4_awprot),
        .s0_awvalid      (axim4_awvalid),
        .s0_awready      (axim4_awready),
        .s0_wdata        (axim4_wdata),
        .s0_wstrb        (axim4_wstrb),
        .s0_wlast        (axim4_wlast),
        .s0_wvalid       (axim4_wvalid),
        .s0_wready       (axim4_wready),
        .s0_bid          (axim4_bid),
        .s0_bresp        (axim4_bresp),
        .s0_bvalid       (axim4_bvalid),
        .s0_bready       (axim4_bready),
        .s0_arid         (axim4_arid),
        .s0_araddr       (axim4_araddr),
        .s0_arlen        (axim4_arlen),
        .s0_arsize       (axim4_arsize),
        .s0_arburst      (axim4_arburst),
        .s0_arlock       (axim4_arlock),
        .s0_arcache      (axim4_arcache),
        .s0_arprot       (axim4_arprot),
        .s0_arvalid      (axim4_arvalid),
        .s0_arready      (axim4_arready),
        .s0_rid          (axim4_rid),
        .s0_rdata        (axim4_rdata),
        .s0_rresp        (axim4_rresp),
        .s0_rlast        (axim4_rlast),
        .s0_rvalid       (axim4_rvalid),
        .s0_rready       (axim4_rready)
    );
    end else begin : g_no_ext_axi_master
        assign axim4_awid     = axim3_awid;
        assign axim4_awaddr   = axim3_awaddr;
        assign axim4_awlen    = axim3_awlen;
        assign axim4_awsize   = axim3_awsize;
        assign axim4_awburst  = axim3_awburst;
        assign axim4_awlock   = axim3_awlock;
        assign axim4_awcache  = axim3_awcache;
        assign axim4_awprot   = axim3_awprot;
        assign axim4_awvalid  = axim3_awvalid;
        assign axim3_awready  = axim4_awready;
        assign axim4_wdata    = axim3_wdata;
        assign axim4_wstrb    = axim3_wstrb;
        assign axim4_wlast    = axim3_wlast;
        assign axim4_wvalid   = axim3_wvalid;
        assign axim3_wready   = axim4_wready;
        assign axim3_bid      = axim4_bid;
        assign axim3_bresp    = axim4_bresp;
        assign axim3_bvalid   = axim4_bvalid;
        assign axim4_bready   = axim3_bready;

        assign axim4_arid     = axim3_arid;
        assign axim4_araddr   = axim3_araddr;
        assign axim4_arlen    = axim3_arlen;
        assign axim4_arsize   = axim3_arsize;
        assign axim4_arburst  = axim3_arburst;
        assign axim4_arlock   = axim3_arlock;
        assign axim4_arcache  = axim3_arcache;
        assign axim4_arprot   = axim3_arprot;
        assign axim4_arvalid  = axim3_arvalid;
        assign axim3_arready  = axim4_arready;
        assign axim3_rid      = axim4_rid;
        assign axim3_rdata    = axim4_rdata;
        assign axim3_rresp    = axim4_rresp;
        assign axim3_rlast    = axim4_rlast;
        assign axim3_rvalid   = axim4_rvalid;
        assign axim4_rready   = axim3_rready;

        assign ext_awready    = 1'b0;
        assign ext_wready     = 1'b0;
        assign ext_bid        = 4'd0;
        assign ext_bresp      = 2'b00;
        assign ext_bvalid     = 1'b0;
        assign ext_arready    = 1'b0;
        assign ext_rid        = 4'd0;
        assign ext_rdata      = 32'd0;
        assign ext_rresp      = 2'b00;
        assign ext_rlast      = 1'b0;
        assign ext_rvalid     = 1'b0;
    end
    endgenerate

    // 1x3 Decoder
    // Slave 0: SRAM boot window and uncached alias
    // Slave 1: APB peripherals
    // Slave 2: SPI flash
    // Unmapped addresses complete internally with DECERR.

    axi_decoder_1x3 u_axi_decoder (
        .clk             (clk),
        .rst_n           (rst_n),

        .m_awid          (axim4_awid),
        .m_awaddr        (axim4_awaddr),
        .m_awlen         (axim4_awlen),
        .m_awsize        (axim4_awsize),
        .m_awburst       (axim4_awburst),
        .m_awlock        (axim4_awlock),
        .m_awcache       (axim4_awcache),
        .m_awprot        (axim4_awprot),
        .m_awvalid       (axim4_awvalid),
        .m_awready       (axim4_awready),
        .m_wdata         (axim4_wdata),
        .m_wstrb         (axim4_wstrb),
        .m_wlast         (axim4_wlast),
        .m_wvalid        (axim4_wvalid),
        .m_wready        (axim4_wready),
        .m_bid           (axim4_bid),
        .m_bresp         (axim4_bresp),
        .m_bvalid        (axim4_bvalid),
        .m_bready        (axim4_bready),
        .m_arid          (axim4_arid),
        .m_araddr        (axim4_araddr),
        .m_arlen         (axim4_arlen),
        .m_arsize        (axim4_arsize),
        .m_arburst       (axim4_arburst),
        .m_arlock        (axim4_arlock),
        .m_arcache       (axim4_arcache),
        .m_arprot        (axim4_arprot),
        .m_arvalid       (axim4_arvalid),
        .m_arready       (axim4_arready),
        .m_rid           (axim4_rid),
        .m_rdata         (axim4_rdata),
        .m_rresp         (axim4_rresp),
        .m_rlast         (axim4_rlast),
        .m_rvalid        (axim4_rvalid),
        .m_rready        (axim4_rready),

        .s0_awid         (s0_awid),
        .s0_awaddr       (s0_awaddr),
        .s0_awlen        (s0_awlen),
        .s0_awsize       (s0_awsize),
        .s0_awburst      (s0_awburst),
        .s0_awlock       (s0_awlock),
        .s0_awcache      (s0_awcache),
        .s0_awprot       (s0_awprot),
        .s0_awvalid      (s0_awvalid),
        .s0_awready      (s0_awready),
        .s0_wdata        (s0_wdata),
        .s0_wstrb        (s0_wstrb),
        .s0_wlast        (s0_wlast),
        .s0_wvalid       (s0_wvalid),
        .s0_wready       (s0_wready),
        .s0_bid          (s0_bid),
        .s0_bresp        (s0_bresp),
        .s0_bvalid       (s0_bvalid),
        .s0_bready       (s0_bready),
        .s0_arid         (s0_arid),
        .s0_araddr       (s0_araddr),
        .s0_arlen        (s0_arlen),
        .s0_arsize       (s0_arsize),
        .s0_arburst      (s0_arburst),
        .s0_arlock       (s0_arlock),
        .s0_arcache      (s0_arcache),
        .s0_arprot       (s0_arprot),
        .s0_arvalid      (s0_arvalid),
        .s0_arready      (s0_arready),
        .s0_rid          (s0_rid),
        .s0_rdata        (s0_rdata),
        .s0_rresp        (s0_rresp),
        .s0_rlast        (s0_rlast),
        .s0_rvalid       (s0_rvalid),
        .s0_rready       (s0_rready),

        .s1_awid         (s1_awid),
        .s1_awaddr       (s1_awaddr),
        .s1_awlen        (s1_awlen),
        .s1_awsize       (s1_awsize),
        .s1_awburst      (s1_awburst),
        .s1_awlock       (s1_awlock),
        .s1_awcache      (s1_awcache),
        .s1_awprot       (s1_awprot),
        .s1_awvalid      (s1_awvalid),
        .s1_awready      (s1_awready),
        .s1_wdata        (s1_wdata),
        .s1_wstrb        (s1_wstrb),
        .s1_wlast        (s1_wlast),
        .s1_wvalid       (s1_wvalid),
        .s1_wready       (s1_wready),
        .s1_bid          (s1_bid),
        .s1_bresp        (s1_bresp),
        .s1_bvalid       (s1_bvalid),
        .s1_bready       (s1_bready),
        .s1_arid         (s1_arid),
        .s1_araddr       (s1_araddr),
        .s1_arlen        (s1_arlen),
        .s1_arsize       (s1_arsize),
        .s1_arburst      (s1_arburst),
        .s1_arlock       (s1_arlock),
        .s1_arcache      (s1_arcache),
        .s1_arprot       (s1_arprot),
        .s1_arvalid      (s1_arvalid),
        .s1_arready      (s1_arready),
        .s1_rid          (s1_rid),
        .s1_rdata        (s1_rdata),
        .s1_rresp        (s1_rresp),
        .s1_rlast        (s1_rlast),
        .s1_rvalid       (s1_rvalid),
        .s1_rready       (s1_rready),

        .s2_awid         (s2_awid),
        .s2_awaddr       (s2_awaddr),
        .s2_awlen        (s2_awlen),
        .s2_awsize       (s2_awsize),
        .s2_awburst      (s2_awburst),
        .s2_awlock       (s2_awlock),
        .s2_awcache      (s2_awcache),
        .s2_awprot       (s2_awprot),
        .s2_awvalid      (s2_awvalid),
        .s2_awready      (s2_awready),
        .s2_wdata        (s2_wdata),
        .s2_wstrb        (s2_wstrb),
        .s2_wlast        (s2_wlast),
        .s2_wvalid       (s2_wvalid),
        .s2_wready       (s2_wready),
        .s2_bid          (s2_bid),
        .s2_bresp        (s2_bresp),
        .s2_bvalid       (s2_bvalid),
        .s2_bready       (s2_bready),
        .s2_arid         (s2_arid),
        .s2_araddr       (s2_araddr),
        .s2_arlen        (s2_arlen),
        .s2_arsize       (s2_arsize),
        .s2_arburst      (s2_arburst),
        .s2_arlock       (s2_arlock),
        .s2_arcache      (s2_arcache),
        .s2_arprot       (s2_arprot),
        .s2_arvalid      (s2_arvalid),
        .s2_arready      (s2_arready),
        .s2_rid          (s2_rid),
        .s2_rdata        (s2_rdata),
        .s2_rresp        (s2_rresp),
        .s2_rlast        (s2_rlast),
        .s2_rvalid       (s2_rvalid),
        .s2_rready       (s2_rready)
    );

endmodule
