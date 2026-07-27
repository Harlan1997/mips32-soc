// =============================================================================
// File Name: l2_cache.v
// Design:    L2 unified cache — top wrapper (pass-through or caching)
// Author:    Antigravity — Phase C
// Description:
//   Wrapper around L2 impl variants. Selected at compile time:
//     * SOC_L2_CACHING defined → real caching (l2_cache_wt, write-through
//       no-write-allocate, direct-mapped, burst-aware slave FSM)
//     * default             → transparent pass-through (AXI wire)
//   Wrapper keeps soc_memory_subsystem wiring stable while L2 evolves.
// =============================================================================

`include "soc_config.vh"

module l2_cache #(
    parameter SIZE_BYTES = 32768,
    parameter LINE_BYTES = 32,
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [ID_WIDTH-1:0]   s_awid,
    input  wire [ADDR_WIDTH-1:0] s_awaddr,
    input  wire [7:0]            s_awlen,
    input  wire [2:0]            s_awsize,
    input  wire [1:0]            s_awburst,
    input  wire                  s_awvalid,
    output wire                  s_awready,
    input  wire [DATA_WIDTH-1:0] s_wdata,
    input  wire [3:0]            s_wstrb,
    input  wire                  s_wlast,
    input  wire                  s_wvalid,
    output wire                  s_wready,
    output wire [ID_WIDTH-1:0]   s_bid,
    output wire [1:0]            s_bresp,
    output wire                  s_bvalid,
    input  wire                  s_bready,
    input  wire [ID_WIDTH-1:0]   s_arid,
    input  wire [ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]            s_arlen,
    input  wire [2:0]            s_arsize,
    input  wire [1:0]            s_arburst,
    input  wire                  s_arvalid,
    output wire                  s_arready,
    output wire [ID_WIDTH-1:0]   s_rid,
    output wire [DATA_WIDTH-1:0] s_rdata,
    output wire [1:0]            s_rresp,
    output wire                  s_rlast,
    output wire                  s_rvalid,
    input  wire                  s_rready,

    output wire [ID_WIDTH-1:0]   m_awid,
    output wire [ADDR_WIDTH-1:0] m_awaddr,
    output wire [7:0]            m_awlen,
    output wire [2:0]            m_awsize,
    output wire [1:0]            m_awburst,
    output wire                  m_awvalid,
    input  wire                  m_awready,
    output wire [DATA_WIDTH-1:0] m_wdata,
    output wire [3:0]            m_wstrb,
    output wire                  m_wlast,
    output wire                  m_wvalid,
    input  wire                  m_wready,
    input  wire [ID_WIDTH-1:0]   m_bid,
    input  wire [1:0]            m_bresp,
    input  wire                  m_bvalid,
    output wire                  m_bready,
    output wire [ID_WIDTH-1:0]   m_arid,
    output wire [ADDR_WIDTH-1:0] m_araddr,
    output wire [7:0]            m_arlen,
    output wire [2:0]            m_arsize,
    output wire [1:0]            m_arburst,
    output wire                  m_arvalid,
    input  wire                  m_arready,
    input  wire [ID_WIDTH-1:0]   m_rid,
    input  wire [DATA_WIDTH-1:0] m_rdata,
    input  wire [1:0]            m_rresp,
    input  wire                  m_rlast,
    input  wire                  m_rvalid,
    output wire                  m_rready,

    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

`ifdef SOC_L2_CACHING
    l2_cache_wt #(
        .SIZE_BYTES(SIZE_BYTES), .LINE_BYTES(LINE_BYTES),
        .ID_WIDTH(ID_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_impl (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .snoop_addr(snoop_addr), .snoop_valid(snoop_valid),
        .snoop_ack(snoop_ack), .snoop_hit(snoop_hit)
    );
`else
    // ---- Pure pass-through ----
    assign m_awid    = s_awid;
    assign m_awaddr  = s_awaddr;
    assign m_awlen   = s_awlen;
    assign m_awsize  = s_awsize;
    assign m_awburst = s_awburst;
    assign m_awvalid = s_awvalid;
    assign s_awready = m_awready;

    assign m_wdata   = s_wdata;
    assign m_wstrb   = s_wstrb;
    assign m_wlast   = s_wlast;
    assign m_wvalid  = s_wvalid;
    assign s_wready  = m_wready;

    assign s_bid     = m_bid;
    assign s_bresp   = m_bresp;
    assign s_bvalid  = m_bvalid;
    assign m_bready  = s_bready;

    assign m_arid    = s_arid;
    assign m_araddr  = s_araddr;
    assign m_arlen   = s_arlen;
    assign m_arsize  = s_arsize;
    assign m_arburst = s_arburst;
    assign m_arvalid = s_arvalid;
    assign s_arready = m_arready;

    assign s_rid     = m_rid;
    assign s_rdata   = m_rdata;
    assign s_rresp   = m_rresp;
    assign s_rlast   = m_rlast;
    assign s_rvalid  = m_rvalid;
    assign m_rready  = s_rready;

    assign snoop_ack = snoop_valid;
    assign snoop_hit = 1'b0;
`endif

endmodule
