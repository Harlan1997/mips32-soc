// =============================================================================
// File Name: axi_decoder_1x3.v
// Design:    AXI4 1x3 Decoder
// Author:    Antigravity
// Description:
//   Decodes addresses from 1 Master to 3 Slaves:
//     S0: 0x0000_0000 - 0x0000_FFFF (SRAM)
//     S1: 0x4000_0000 - 0x4000_FFFF (APB Bridge)
//     S2: 0x1000_0000 - 0x1FFF_FFFF (SPI Flash)
// =============================================================================

module axi_decoder_1x3 (
    input  wire        clk,
    input  wire        rst_n,

    // Master Interface
    input  wire [3:0]  m_awid,
    input  wire [31:0] m_awaddr,
    input  wire [7:0]  m_awlen,
    input  wire [2:0]  m_awsize,
    input  wire [1:0]  m_awburst,
    input  wire [1:0]  m_awlock,
    input  wire [3:0]  m_awcache,
    input  wire [2:0]  m_awprot,
    input  wire        m_awvalid,
    output wire        m_awready,
    input  wire [31:0] m_wdata,
    input  wire [3:0]  m_wstrb,
    input  wire        m_wlast,
    input  wire        m_wvalid,
    output wire        m_wready,
    output wire [3:0]  m_bid,
    output wire [1:0]  m_bresp,
    output wire        m_bvalid,
    input  wire        m_bready,

    input  wire [3:0]  m_arid,
    input  wire [31:0] m_araddr,
    input  wire [7:0]  m_arlen,
    input  wire [2:0]  m_arsize,
    input  wire [1:0]  m_arburst,
    input  wire [1:0]  m_arlock,
    input  wire [3:0]  m_arcache,
    input  wire [2:0]  m_arprot,
    input  wire        m_arvalid,
    output wire        m_arready,
    output wire [3:0]  m_rid,
    output wire [31:0] m_rdata,
    output wire [1:0]  m_rresp,
    output wire        m_rlast,
    output wire        m_rvalid,
    input  wire        m_rready,

    // Slave 0 Interface (SRAM)
    output wire [3:0]  s0_awid,
    output wire [31:0] s0_awaddr,
    output wire [7:0]  s0_awlen,
    output wire [2:0]  s0_awsize,
    output wire [1:0]  s0_awburst,
    output wire [1:0]  s0_awlock,
    output wire [3:0]  s0_awcache,
    output wire [2:0]  s0_awprot,
    output wire        s0_awvalid,
    input  wire        s0_awready,
    output wire [31:0] s0_wdata,
    output wire [3:0]  s0_wstrb,
    output wire        s0_wlast,
    output wire        s0_wvalid,
    input  wire        s0_wready,
    input  wire [3:0]  s0_bid,
    input  wire [1:0]  s0_bresp,
    input  wire        s0_bvalid,
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
    input  wire        s0_arready,
    input  wire [3:0]  s0_rid,
    input  wire [31:0] s0_rdata,
    input  wire [1:0]  s0_rresp,
    input  wire        s0_rlast,
    input  wire        s0_rvalid,
    output wire        s0_rready,

    // Slave 1 Interface (APB)
    output wire [3:0]  s1_awid,
    output wire [31:0] s1_awaddr,
    output wire [7:0]  s1_awlen,
    output wire [2:0]  s1_awsize,
    output wire [1:0]  s1_awburst,
    output wire [1:0]  s1_awlock,
    output wire [3:0]  s1_awcache,
    output wire [2:0]  s1_awprot,
    output wire        s1_awvalid,
    input  wire        s1_awready,
    output wire [31:0] s1_wdata,
    output wire [3:0]  s1_wstrb,
    output wire        s1_wlast,
    output wire        s1_wvalid,
    input  wire        s1_wready,
    input  wire [3:0]  s1_bid,
    input  wire [1:0]  s1_bresp,
    input  wire        s1_bvalid,
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
    input  wire        s1_arready,
    input  wire [3:0]  s1_rid,
    input  wire [31:0] s1_rdata,
    input  wire [1:0]  s1_rresp,
    input  wire        s1_rlast,
    input  wire        s1_rvalid,
    output wire        s1_rready,
    
    // Slave 2 Interface (SPI Flash)
    output wire [3:0]  s2_awid,
    output wire [31:0] s2_awaddr,
    output wire [7:0]  s2_awlen,
    output wire [2:0]  s2_awsize,
    output wire [1:0]  s2_awburst,
    output wire [1:0]  s2_awlock,
    output wire [3:0]  s2_awcache,
    output wire [2:0]  s2_awprot,
    output wire        s2_awvalid,
    input  wire        s2_awready,
    output wire [31:0] s2_wdata,
    output wire [3:0]  s2_wstrb,
    output wire        s2_wlast,
    output wire        s2_wvalid,
    input  wire        s2_wready,
    input  wire [3:0]  s2_bid,
    input  wire [1:0]  s2_bresp,
    input  wire        s2_bvalid,
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
    input  wire        s2_arready,
    input  wire [3:0]  s2_rid,
    input  wire [31:0] s2_rdata,
    input  wire [1:0]  s2_rresp,
    input  wire        s2_rlast,
    input  wire        s2_rvalid,
    output wire        s2_rready
);

    wire sel_s1_aw = (m_awaddr[31:28] == 4'h4);
    wire sel_s2_aw = (m_awaddr[31:28] == 4'h1);
    wire sel_s0_aw = !sel_s1_aw && !sel_s2_aw;

    wire sel_s1_ar = (m_araddr[31:28] == 4'h4);
    wire sel_s2_ar = (m_araddr[31:28] == 4'h1);
    wire sel_s0_ar = !sel_s1_ar && !sel_s2_ar;
    
    // Address Channels Demux
    assign s0_awid    = m_awid;
    assign s0_awaddr  = m_awaddr;
    assign s0_awlen   = m_awlen;
    assign s0_awsize  = m_awsize;
    assign s0_awburst = m_awburst;
    assign s0_awlock  = m_awlock;
    assign s0_awcache = m_awcache;
    assign s0_awprot  = m_awprot;
    assign s0_awvalid = m_awvalid & sel_s0_aw;
    
    assign s1_awid    = m_awid;
    assign s1_awaddr  = m_awaddr;
    assign s1_awlen   = m_awlen;
    assign s1_awsize  = m_awsize;
    assign s1_awburst = m_awburst;
    assign s1_awlock  = m_awlock;
    assign s1_awcache = m_awcache;
    assign s1_awprot  = m_awprot;
    assign s1_awvalid = m_awvalid & sel_s1_aw;

    assign s2_awid    = m_awid;
    assign s2_awaddr  = m_awaddr;
    assign s2_awlen   = m_awlen;
    assign s2_awsize  = m_awsize;
    assign s2_awburst = m_awburst;
    assign s2_awlock  = m_awlock;
    assign s2_awcache = m_awcache;
    assign s2_awprot  = m_awprot;
    assign s2_awvalid = m_awvalid & sel_s2_aw;

    assign m_awready  = sel_s1_aw ? s1_awready : sel_s2_aw ? s2_awready : s0_awready;

    // Write Data Demux (requires tracking active write channel)
    reg [1:0] act_w_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) act_w_sel <= 2'b00;
        else if (m_awvalid && m_awready) act_w_sel <= sel_s1_aw ? 2'b01 : (sel_s2_aw ? 2'b10 : 2'b00);
    end
    
    wire [1:0] cur_w_sel = m_awvalid ? (sel_s1_aw ? 2'b01 : (sel_s2_aw ? 2'b10 : 2'b00)) : act_w_sel;

    assign s0_wvalid = m_wvalid & (cur_w_sel == 2'b00);
    assign s0_wdata  = m_wdata;
    assign s0_wstrb  = m_wstrb;
    assign s0_wlast  = m_wlast;

    assign s1_wvalid = m_wvalid & (cur_w_sel == 2'b01);
    assign s1_wdata  = m_wdata;
    assign s1_wstrb  = m_wstrb;
    assign s1_wlast  = m_wlast;

    assign s2_wvalid = m_wvalid & (cur_w_sel == 2'b10);
    assign s2_wdata  = m_wdata;
    assign s2_wstrb  = m_wstrb;
    assign s2_wlast  = m_wlast;

    assign m_wready  = (cur_w_sel == 2'b01) ? s1_wready : (cur_w_sel == 2'b10) ? s2_wready : s0_wready;

    // Write Response Mux
    assign m_bid    = (act_w_sel == 2'b01) ? s1_bid : (act_w_sel == 2'b10) ? s2_bid : s0_bid;
    assign m_bresp  = (act_w_sel == 2'b01) ? s1_bresp : (act_w_sel == 2'b10) ? s2_bresp : s0_bresp;
    assign m_bvalid = (act_w_sel == 2'b01) ? s1_bvalid : (act_w_sel == 2'b10) ? s2_bvalid : s0_bvalid;
    
    assign s0_bready = m_bready & (act_w_sel == 2'b00);
    assign s1_bready = m_bready & (act_w_sel == 2'b01);
    assign s2_bready = m_bready & (act_w_sel == 2'b10);

    // Read Address Demux
    assign s0_arid    = m_arid;
    assign s0_araddr  = m_araddr;
    assign s0_arlen   = m_arlen;
    assign s0_arsize  = m_arsize;
    assign s0_arburst = m_arburst;
    assign s0_arlock  = m_arlock;
    assign s0_arcache = m_arcache;
    assign s0_arprot  = m_arprot;
    assign s0_arvalid = m_arvalid & sel_s0_ar;
    
    assign s1_arid    = m_arid;
    assign s1_araddr  = m_araddr;
    assign s1_arlen   = m_arlen;
    assign s1_arsize  = m_arsize;
    assign s1_arburst = m_arburst;
    assign s1_arlock  = m_arlock;
    assign s1_arcache = m_arcache;
    assign s1_arprot  = m_arprot;
    assign s1_arvalid = m_arvalid & sel_s1_ar;

    assign s2_arid    = m_arid;
    assign s2_araddr  = m_araddr;
    assign s2_arlen   = m_arlen;
    assign s2_arsize  = m_arsize;
    assign s2_arburst = m_arburst;
    assign s2_arlock  = m_arlock;
    assign s2_arcache = m_arcache;
    assign s2_arprot  = m_arprot;
    assign s2_arvalid = m_arvalid & sel_s2_ar;

    assign m_arready  = sel_s1_ar ? s1_arready : sel_s2_ar ? s2_arready : s0_arready;

    // Read Data Mux
    reg [1:0] act_r_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) act_r_sel <= 2'b00;
        else if (m_arvalid && m_arready) act_r_sel <= sel_s1_ar ? 2'b01 : (sel_s2_ar ? 2'b10 : 2'b00);
    end

    assign m_rid    = (act_r_sel == 2'b01) ? s1_rid : (act_r_sel == 2'b10) ? s2_rid : s0_rid;
    assign m_rdata  = (act_r_sel == 2'b01) ? s1_rdata : (act_r_sel == 2'b10) ? s2_rdata : s0_rdata;
    assign m_rresp  = (act_r_sel == 2'b01) ? s1_rresp : (act_r_sel == 2'b10) ? s2_rresp : s0_rresp;
    assign m_rlast  = (act_r_sel == 2'b01) ? s1_rlast : (act_r_sel == 2'b10) ? s2_rlast : s0_rlast;
    assign m_rvalid = (act_r_sel == 2'b01) ? s1_rvalid : (act_r_sel == 2'b10) ? s2_rvalid : s0_rvalid;

    assign s0_rready = m_rready & (act_r_sel == 2'b00);
    assign s1_rready = m_rready & (act_r_sel == 2'b01);
    assign s2_rready = m_rready & (act_r_sel == 2'b10);

endmodule
