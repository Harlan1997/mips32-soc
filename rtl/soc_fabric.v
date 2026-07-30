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
    input  wire        s2_rvalid,
    output wire [3:0]  s3_awid,
    output wire [31:0] s3_awaddr,
    output wire [7:0]  s3_awlen,
    output wire [2:0]  s3_awsize,
    output wire [1:0]  s3_awburst,
    output wire [1:0]  s3_awlock,
    output wire [3:0]  s3_awcache,
    output wire [2:0]  s3_awprot,
    output wire        s3_awvalid,
    output wire [31:0] s3_wdata,
    output wire [3:0]  s3_wstrb,
    output wire        s3_wlast,
    output wire        s3_wvalid,
    output wire        s3_bready,
    output wire [3:0]  s3_arid,
    output wire [31:0] s3_araddr,
    output wire [7:0]  s3_arlen,
    output wire [2:0]  s3_arsize,
    output wire [1:0]  s3_arburst,
    output wire [1:0]  s3_arlock,
    output wire [3:0]  s3_arcache,
    output wire [2:0]  s3_arprot,
    output wire        s3_arvalid,
    output wire        s3_rready,
    input  wire        s3_awready,
    input  wire        s3_wready,
    input  wire [3:0]  s3_bid,
    input  wire [1:0]  s3_bresp,
    input  wire        s3_bvalid,
    input  wire        s3_arready,
    input  wire [3:0]  s3_rid,
    input  wire [31:0] s3_rdata,
    input  wire [1:0]  s3_rresp,
    input  wire        s3_rlast,
    input  wire        s3_rvalid
);

    // =========================================================================
    // Phase C.3: true M x N crossbar replaces the legacy arbiter cascade.
    // Masters packed: idx0=I$ (m0, read-only), 1=D$ (m1), 2=DMA (m2),
    // 3=jtag, 4=ext. Slaves: 0=SRAM/L2, 1=APB, 2=FLASH, 3=DDR (behavioral
    // placeholder, Phase C.4) (+ internal DECERR). ext master is masked off
    // via m_enable when ENABLE_EXT_AXI_MASTER=0.
    // =========================================================================
    `include "soc_config.vh"
    localparam integer NM = 5;
    localparam integer NS = 4;

    wire [NM-1:0] xm_enable = { ENABLE_EXT_AXI_MASTER ? 1'b1 : 1'b0,
                                1'b1, 1'b1, 1'b1, 1'b1 };

    // ---- Pack master request vectors (idx: {ext,jtag,dma,d$,i$}) ----
    // m0 = I$ is read-only: tie its AW/W to 0.
    wire [NM*4-1:0]  xm_awid    = { ext_awid,   jtag_awid,   m2_awid,   m1_awid,   4'd0 };
    wire [NM*32-1:0] xm_awaddr  = { ext_awaddr, jtag_awaddr, m2_awaddr, m1_awaddr, 32'd0 };
    wire [NM*8-1:0]  xm_awlen   = { ext_awlen,  jtag_awlen,  m2_awlen,  m1_awlen,  8'd0 };
    wire [NM*3-1:0]  xm_awsize  = { ext_awsize, jtag_awsize, m2_awsize, m1_awsize, 3'd0 };
    wire [NM*2-1:0]  xm_awburst = { ext_awburst,jtag_awburst,m2_awburst,m1_awburst,2'd0 };
    wire [NM*2-1:0]  xm_awlock  = { ext_awlock, jtag_awlock, m2_awlock, m1_awlock, 2'd0 };
    wire [NM*4-1:0]  xm_awcache = { ext_awcache,jtag_awcache,m2_awcache,m1_awcache,4'd0 };
    wire [NM*3-1:0]  xm_awprot  = { ext_awprot, jtag_awprot, m2_awprot, m1_awprot, 3'd0 };
    wire [NM*4-1:0]  xm_awqos   = { `SOC_XBAR_QOS_EXT, `SOC_XBAR_QOS_JTAG,
                                    `SOC_XBAR_QOS_DMA, `SOC_XBAR_QOS_DCACHE,
                                    `SOC_XBAR_QOS_ICACHE };
    wire [NM-1:0]    xm_awvalid = { ext_awvalid, jtag_awvalid, m2_awvalid, m1_awvalid, 1'b0 };
    wire [NM-1:0]    xm_awready;

    wire [NM*32-1:0] xm_wdata   = { ext_wdata, jtag_wdata, m2_wdata, m1_wdata, 32'd0 };
    wire [NM*4-1:0]  xm_wstrb   = { ext_wstrb, jtag_wstrb, m2_wstrb, m1_wstrb, 4'd0 };
    wire [NM-1:0]    xm_wlast   = { ext_wlast, jtag_wlast, m2_wlast, m1_wlast, 1'b0 };
    wire [NM-1:0]    xm_wvalid  = { ext_wvalid, jtag_wvalid, m2_wvalid, m1_wvalid, 1'b0 };
    wire [NM-1:0]    xm_wready;

    wire [NM*4-1:0]  xm_bid;
    wire [NM*2-1:0]  xm_bresp;
    wire [NM-1:0]    xm_bvalid;
    wire [NM-1:0]    xm_bready  = { ext_bready, jtag_bready, m2_bready, m1_bready, 1'b0 };

    wire [NM*4-1:0]  xm_arid    = { ext_arid,   jtag_arid,   m2_arid,   m1_arid,   m0_arid };
    wire [NM*32-1:0] xm_araddr  = { ext_araddr, jtag_araddr, m2_araddr, m1_araddr, m0_araddr };
    wire [NM*8-1:0]  xm_arlen   = { ext_arlen,  jtag_arlen,  m2_arlen,  m1_arlen,  m0_arlen };
    wire [NM*3-1:0]  xm_arsize  = { ext_arsize, jtag_arsize, m2_arsize, m1_arsize, m0_arsize };
    wire [NM*2-1:0]  xm_arburst = { ext_arburst,jtag_arburst,m2_arburst,m1_arburst,m0_arburst };
    wire [NM*2-1:0]  xm_arlock  = { ext_arlock, jtag_arlock, m2_arlock, m1_arlock, m0_arlock };
    wire [NM*4-1:0]  xm_arcache = { ext_arcache,jtag_arcache,m2_arcache,m1_arcache,m0_arcache };
    wire [NM*3-1:0]  xm_arprot  = { ext_arprot, jtag_arprot, m2_arprot, m1_arprot, m0_arprot };
    wire [NM*4-1:0]  xm_arqos   = { `SOC_XBAR_QOS_EXT, `SOC_XBAR_QOS_JTAG,
                                    `SOC_XBAR_QOS_DMA, `SOC_XBAR_QOS_DCACHE,
                                    `SOC_XBAR_QOS_ICACHE };
    wire [NM-1:0]    xm_arvalid = { ext_arvalid, jtag_arvalid, m2_arvalid, m1_arvalid, m0_arvalid };
    wire [NM-1:0]    xm_arready;

    wire [NM*4-1:0]  xm_rid;
    wire [NM*32-1:0] xm_rdata;
    wire [NM*2-1:0]  xm_rresp;
    wire [NM-1:0]    xm_rlast;
    wire [NM-1:0]    xm_rvalid;
    wire [NM-1:0]    xm_rready  = { ext_rready, jtag_rready, m2_rready, m1_rready, m0_rready };

    // ---- Unpack master response vectors back to flat ports ----
    // idx0 = I$ (read-only)
    assign m0_arready = xm_arready[0];
    assign m0_rid     = xm_rid  [0*4 +: 4];
    assign m0_rdata   = xm_rdata[0*32 +: 32];
    assign m0_rresp   = xm_rresp[0*2 +: 2];
    assign m0_rlast   = xm_rlast[0];
    assign m0_rvalid  = xm_rvalid[0];
    // idx1 = D$
    assign m1_awready = xm_awready[1];
    assign m1_wready  = xm_wready[1];
    assign m1_bid     = xm_bid  [1*4 +: 4];
    assign m1_bresp   = xm_bresp[1*2 +: 2];
    assign m1_bvalid  = xm_bvalid[1];
    assign m1_arready = xm_arready[1];
    assign m1_rid     = xm_rid  [1*4 +: 4];
    assign m1_rdata   = xm_rdata[1*32 +: 32];
    assign m1_rresp   = xm_rresp[1*2 +: 2];
    assign m1_rlast   = xm_rlast[1];
    assign m1_rvalid  = xm_rvalid[1];
    // idx2 = DMA
    assign m2_awready = xm_awready[2];
    assign m2_wready  = xm_wready[2];
    assign m2_bid     = xm_bid  [2*4 +: 4];
    assign m2_bresp   = xm_bresp[2*2 +: 2];
    assign m2_bvalid  = xm_bvalid[2];
    assign m2_arready = xm_arready[2];
    assign m2_rid     = xm_rid  [2*4 +: 4];
    assign m2_rdata   = xm_rdata[2*32 +: 32];
    assign m2_rresp   = xm_rresp[2*2 +: 2];
    assign m2_rlast   = xm_rlast[2];
    assign m2_rvalid  = xm_rvalid[2];
    // idx3 = jtag
    assign jtag_awready = xm_awready[3];
    assign jtag_wready  = xm_wready[3];
    assign jtag_bid     = xm_bid  [3*4 +: 4];
    assign jtag_bresp   = xm_bresp[3*2 +: 2];
    assign jtag_bvalid  = xm_bvalid[3];
    assign jtag_arready = xm_arready[3];
    assign jtag_rid     = xm_rid  [3*4 +: 4];
    assign jtag_rdata   = xm_rdata[3*32 +: 32];
    assign jtag_rresp   = xm_rresp[3*2 +: 2];
    assign jtag_rlast   = xm_rlast[3];
    assign jtag_rvalid  = xm_rvalid[3];
    // idx4 = ext
    assign ext_awready = xm_awready[4];
    assign ext_wready  = xm_wready[4];
    assign ext_bid     = xm_bid  [4*4 +: 4];
    assign ext_bresp   = xm_bresp[4*2 +: 2];
    assign ext_bvalid  = xm_bvalid[4];
    assign ext_arready = xm_arready[4];
    assign ext_rid     = xm_rid  [4*4 +: 4];
    assign ext_rdata   = xm_rdata[4*32 +: 32];
    assign ext_rresp   = xm_rresp[4*2 +: 2];
    assign ext_rlast   = xm_rlast[4];
    assign ext_rvalid  = xm_rvalid[4];

    // ---- Pack slave vectors (idx: {ddr,flash,apb,sram}) ----
    wire [NS*4-1:0]  xs_awid;    wire [NS*32-1:0] xs_awaddr;  wire [NS*8-1:0] xs_awlen;
    wire [NS*3-1:0]  xs_awsize;  wire [NS*2-1:0]  xs_awburst; wire [NS*2-1:0] xs_awlock;
    wire [NS*4-1:0]  xs_awcache; wire [NS*3-1:0]  xs_awprot;  wire [NS-1:0]   xs_awvalid;
    wire [NS-1:0]    xs_awready = { s3_awready, s2_awready, s1_awready, s0_awready };
    wire [NS*32-1:0] xs_wdata;   wire [NS*4-1:0]  xs_wstrb;   wire [NS-1:0]   xs_wlast;
    wire [NS-1:0]    xs_wvalid;  wire [NS-1:0]    xs_wready = { s3_wready, s2_wready, s1_wready, s0_wready };
    wire [NS*4-1:0]  xs_bid   = { s3_bid,   s2_bid,   s1_bid,   s0_bid };
    wire [NS*2-1:0]  xs_bresp = { s3_bresp, s2_bresp, s1_bresp, s0_bresp };
    wire [NS-1:0]    xs_bvalid= { s3_bvalid,s2_bvalid,s1_bvalid,s0_bvalid };
    wire [NS-1:0]    xs_bready;
    wire [NS*4-1:0]  xs_arid;    wire [NS*32-1:0] xs_araddr;  wire [NS*8-1:0] xs_arlen;
    wire [NS*3-1:0]  xs_arsize;  wire [NS*2-1:0]  xs_arburst; wire [NS*2-1:0] xs_arlock;
    wire [NS*4-1:0]  xs_arcache; wire [NS*3-1:0]  xs_arprot;  wire [NS-1:0]   xs_arvalid;
    wire [NS-1:0]    xs_arready = { s3_arready, s2_arready, s1_arready, s0_arready };
    wire [NS*4-1:0]  xs_rid   = { s3_rid,   s2_rid,   s1_rid,   s0_rid };
    wire [NS*32-1:0] xs_rdata = { s3_rdata, s2_rdata, s1_rdata, s0_rdata };
    wire [NS*2-1:0]  xs_rresp = { s3_rresp, s2_rresp, s1_rresp, s0_rresp };
    wire [NS-1:0]    xs_rlast = { s3_rlast, s2_rlast, s1_rlast, s0_rlast };
    wire [NS-1:0]    xs_rvalid= { s3_rvalid,s2_rvalid,s1_rvalid,s0_rvalid };
    wire [NS-1:0]    xs_rready;

    // Unpack slave request vectors to flat slave ports
    assign s0_awid   = xs_awid  [0*4 +:4];  assign s1_awid   = xs_awid  [1*4 +:4];  assign s2_awid   = xs_awid  [2*4 +:4];  assign s3_awid   = xs_awid  [3*4 +:4];
    assign s0_awaddr = xs_awaddr[0*32+:32]; assign s1_awaddr = xs_awaddr[1*32+:32]; assign s2_awaddr = xs_awaddr[2*32+:32]; assign s3_awaddr = xs_awaddr[3*32+:32];
    assign s0_awlen  = xs_awlen [0*8 +:8];  assign s1_awlen  = xs_awlen [1*8 +:8];  assign s2_awlen  = xs_awlen [2*8 +:8];  assign s3_awlen  = xs_awlen [3*8 +:8];
    assign s0_awsize = xs_awsize[0*3 +:3];  assign s1_awsize = xs_awsize[1*3 +:3];  assign s2_awsize = xs_awsize[2*3 +:3];  assign s3_awsize = xs_awsize[3*3 +:3];
    assign s0_awburst= xs_awburst[0*2+:2];  assign s1_awburst= xs_awburst[1*2+:2];  assign s2_awburst= xs_awburst[2*2+:2];  assign s3_awburst= xs_awburst[3*2+:2];
    assign s0_awlock = xs_awlock[0*2 +:2];  assign s1_awlock = xs_awlock[1*2 +:2];  assign s2_awlock = xs_awlock[2*2 +:2];  assign s3_awlock = xs_awlock[3*2 +:2];
    assign s0_awcache= xs_awcache[0*4+:4];  assign s1_awcache= xs_awcache[1*4+:4];  assign s2_awcache= xs_awcache[2*4+:4];  assign s3_awcache= xs_awcache[3*4+:4];
    assign s0_awprot = xs_awprot[0*3 +:3];  assign s1_awprot = xs_awprot[1*3 +:3];  assign s2_awprot = xs_awprot[2*3 +:3];  assign s3_awprot = xs_awprot[3*3 +:3];
    assign s0_awvalid= xs_awvalid[0];       assign s1_awvalid= xs_awvalid[1];       assign s2_awvalid= xs_awvalid[2];       assign s3_awvalid= xs_awvalid[3];
    assign s0_wdata  = xs_wdata [0*32+:32]; assign s1_wdata  = xs_wdata [1*32+:32]; assign s2_wdata  = xs_wdata [2*32+:32]; assign s3_wdata  = xs_wdata [3*32+:32];
    assign s0_wstrb  = xs_wstrb [0*4 +:4];  assign s1_wstrb  = xs_wstrb [1*4 +:4];  assign s2_wstrb  = xs_wstrb [2*4 +:4];  assign s3_wstrb  = xs_wstrb [3*4 +:4];
    assign s0_wlast  = xs_wlast [0];        assign s1_wlast  = xs_wlast [1];        assign s2_wlast  = xs_wlast [2];        assign s3_wlast  = xs_wlast [3];
    assign s0_wvalid = xs_wvalid[0];        assign s1_wvalid = xs_wvalid[1];        assign s2_wvalid = xs_wvalid[2];        assign s3_wvalid = xs_wvalid[3];
    assign s0_bready = xs_bready[0];        assign s1_bready = xs_bready[1];        assign s2_bready = xs_bready[2];        assign s3_bready = xs_bready[3];
    assign s0_arid   = xs_arid  [0*4 +:4];  assign s1_arid   = xs_arid  [1*4 +:4];  assign s2_arid   = xs_arid  [2*4 +:4];  assign s3_arid   = xs_arid  [3*4 +:4];
    assign s0_araddr = xs_araddr[0*32+:32]; assign s1_araddr = xs_araddr[1*32+:32]; assign s2_araddr = xs_araddr[2*32+:32]; assign s3_araddr = xs_araddr[3*32+:32];
    assign s0_arlen  = xs_arlen [0*8 +:8];  assign s1_arlen  = xs_arlen [1*8 +:8];  assign s2_arlen  = xs_arlen [2*8 +:8];  assign s3_arlen  = xs_arlen [3*8 +:8];
    assign s0_arsize = xs_arsize[0*3 +:3];  assign s1_arsize = xs_arsize[1*3 +:3];  assign s2_arsize = xs_arsize[2*3 +:3];  assign s3_arsize = xs_arsize[3*3 +:3];
    assign s0_arburst= xs_arburst[0*2+:2];  assign s1_arburst= xs_arburst[1*2+:2];  assign s2_arburst= xs_arburst[2*2+:2];  assign s3_arburst= xs_arburst[3*2+:2];
    assign s0_arlock = xs_arlock[0*2 +:2];  assign s1_arlock = xs_arlock[1*2 +:2];  assign s2_arlock = xs_arlock[2*2 +:2];  assign s3_arlock = xs_arlock[3*2 +:2];
    assign s0_arcache= xs_arcache[0*4+:4];  assign s1_arcache= xs_arcache[1*4+:4];  assign s2_arcache= xs_arcache[2*4+:4];  assign s3_arcache= xs_arcache[3*4+:4];
    assign s0_arprot = xs_arprot[0*3 +:3];  assign s1_arprot = xs_arprot[1*3 +:3];  assign s2_arprot = xs_arprot[2*3 +:3];  assign s3_arprot = xs_arprot[3*3 +:3];
    assign s0_arvalid= xs_arvalid[0];       assign s1_arvalid= xs_arvalid[1];       assign s2_arvalid= xs_arvalid[2];       assign s3_arvalid= xs_arvalid[3];
    assign s0_rready = xs_rready[0];        assign s1_rready = xs_rready[1];        assign s2_rready = xs_rready[2];        assign s3_rready = xs_rready[3];

    axi_crossbar #(
        .N_M(NM), .N_S(NS), .N_OT(`SOC_XBAR_N_OT),
        .IDW(4), .AW(32), .DW(32), .QW(4)
    ) u_xbar (
        .clk(clk), .rst_n(rst_n), .m_enable(xm_enable),
        .m_awid(xm_awid), .m_awaddr(xm_awaddr), .m_awlen(xm_awlen), .m_awsize(xm_awsize),
        .m_awburst(xm_awburst), .m_awlock(xm_awlock), .m_awcache(xm_awcache), .m_awprot(xm_awprot),
        .m_awqos(xm_awqos), .m_awvalid(xm_awvalid), .m_awready(xm_awready),
        .m_wdata(xm_wdata), .m_wstrb(xm_wstrb), .m_wlast(xm_wlast), .m_wvalid(xm_wvalid), .m_wready(xm_wready),
        .m_bid(xm_bid), .m_bresp(xm_bresp), .m_bvalid(xm_bvalid), .m_bready(xm_bready),
        .m_arid(xm_arid), .m_araddr(xm_araddr), .m_arlen(xm_arlen), .m_arsize(xm_arsize),
        .m_arburst(xm_arburst), .m_arlock(xm_arlock), .m_arcache(xm_arcache), .m_arprot(xm_arprot),
        .m_arqos(xm_arqos), .m_arvalid(xm_arvalid), .m_arready(xm_arready),
        .m_rid(xm_rid), .m_rdata(xm_rdata), .m_rresp(xm_rresp), .m_rlast(xm_rlast),
        .m_rvalid(xm_rvalid), .m_rready(xm_rready),
        .s_awid(xs_awid), .s_awaddr(xs_awaddr), .s_awlen(xs_awlen), .s_awsize(xs_awsize),
        .s_awburst(xs_awburst), .s_awlock(xs_awlock), .s_awcache(xs_awcache), .s_awprot(xs_awprot),
        .s_awvalid(xs_awvalid), .s_awready(xs_awready),
        .s_wdata(xs_wdata), .s_wstrb(xs_wstrb), .s_wlast(xs_wlast), .s_wvalid(xs_wvalid), .s_wready(xs_wready),
        .s_bid(xs_bid), .s_bresp(xs_bresp), .s_bvalid(xs_bvalid), .s_bready(xs_bready),
        .s_arid(xs_arid), .s_araddr(xs_araddr), .s_arlen(xs_arlen), .s_arsize(xs_arsize),
        .s_arburst(xs_arburst), .s_arlock(xs_arlock), .s_arcache(xs_arcache), .s_arprot(xs_arprot),
        .s_arvalid(xs_arvalid), .s_arready(xs_arready),
        .s_rid(xs_rid), .s_rdata(xs_rdata), .s_rresp(xs_rresp), .s_rlast(xs_rlast),
        .s_rvalid(xs_rvalid), .s_rready(xs_rready)
    );

endmodule
