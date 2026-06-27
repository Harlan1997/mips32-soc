// =============================================================================
// File Name: axi_decoder_1x2.v
// Design:    AXI4 1x2 Address Decoder
// Author:    Antigravity
// Description:
//   Routes 1 AXI Master to 2 AXI Slaves based on address.
//   S0: SRAM (0x0000_0000 - 0x0FFF_FFFF) -> Select bit 28 is 0, bit 31 is 0
//   S1: APB  (0x4000_0000 - 0x4FFF_FFFF) -> Select bit 30 is 1
// =============================================================================

module axi_decoder_1x2 (
    input  wire        clk,
    input  wire        rst_n,

    // Master Input
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
    
    // Slave 0 (SRAM - 0x0000_0000)
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
    
    // Slave 1 (APB - 0x4000_0000)
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
    output wire        s1_rready
);

    // Address Decoding (simplified)
    // S0: 0x0000_0000 -> 0x0FFF_FFFF
    // S1: 0x4000_0000 -> 0x4FFF_FFFF
    wire aw_sel_s1 = (m_awaddr[31:28] == 4'h4);
    wire ar_sel_s1 = (m_araddr[31:28] == 4'h4);

    // State machines to route W and R responses
    reg w_route;
    reg r_route;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_route <= 1'b0;
            r_route <= 1'b0;
        end else begin
            if (m_awvalid && m_awready) w_route <= aw_sel_s1;
            if (m_arvalid && m_arready) r_route <= ar_sel_s1;
        end
    end

    // AW Channel
    assign s0_awid    = m_awid;
    assign s0_awaddr  = m_awaddr;
    assign s0_awlen   = m_awlen;
    assign s0_awsize  = m_awsize;
    assign s0_awburst = m_awburst;
    assign s0_awlock  = m_awlock;
    assign s0_awcache = m_awcache;
    assign s0_awprot  = m_awprot;
    assign s0_awvalid = m_awvalid & ~aw_sel_s1;

    assign s1_awid    = m_awid;
    assign s1_awaddr  = m_awaddr;
    assign s1_awlen   = m_awlen;
    assign s1_awsize  = m_awsize;
    assign s1_awburst = m_awburst;
    assign s1_awlock  = m_awlock;
    assign s1_awcache = m_awcache;
    assign s1_awprot  = m_awprot;
    assign s1_awvalid = m_awvalid & aw_sel_s1;

    assign m_awready  = aw_sel_s1 ? s1_awready : s0_awready;

    wire current_w_sel = m_awvalid ? aw_sel_s1 : w_route;

    // W Channel
    assign s0_wdata   = m_wdata;
    assign s0_wstrb   = m_wstrb;
    assign s0_wlast   = m_wlast;
    assign s0_wvalid  = m_wvalid & ~current_w_sel;

    assign s1_wdata   = m_wdata;
    assign s1_wstrb   = m_wstrb;
    assign s1_wlast   = m_wlast;
    assign s1_wvalid  = m_wvalid & current_w_sel;

    assign m_wready   = current_w_sel ? s1_wready : s0_wready;

    // B Channel
    assign m_bid      = w_route ? s1_bid : s0_bid;
    assign m_bresp    = w_route ? s1_bresp : s0_bresp;
    assign m_bvalid   = w_route ? s1_bvalid : s0_bvalid;
    
    assign s0_bready  = m_bready & ~w_route;
    assign s1_bready  = m_bready & w_route;

    // AR Channel
    assign s0_arid    = m_arid;
    assign s0_araddr  = m_araddr;
    assign s0_arlen   = m_arlen;
    assign s0_arsize  = m_arsize;
    assign s0_arburst = m_arburst;
    assign s0_arlock  = m_arlock;
    assign s0_arcache = m_arcache;
    assign s0_arprot  = m_arprot;
    assign s0_arvalid = m_arvalid & ~ar_sel_s1;

    assign s1_arid    = m_arid;
    assign s1_araddr  = m_araddr;
    assign s1_arlen   = m_arlen;
    assign s1_arsize  = m_arsize;
    assign s1_arburst = m_arburst;
    assign s1_arlock  = m_arlock;
    assign s1_arcache = m_arcache;
    assign s1_arprot  = m_arprot;
    assign s1_arvalid = m_arvalid & ar_sel_s1;

    assign m_arready  = ar_sel_s1 ? s1_arready : s0_arready;

    // R Channel
    assign m_rid      = r_route ? s1_rid : s0_rid;
    assign m_rdata    = r_route ? s1_rdata : s0_rdata;
    assign m_rresp    = r_route ? s1_rresp : s0_rresp;
    assign m_rlast    = r_route ? s1_rlast : s0_rlast;
    assign m_rvalid   = r_route ? s1_rvalid : s0_rvalid;
    
    assign s0_rready  = m_rready & ~r_route;
    assign s1_rready  = m_rready & r_route;

endmodule
