// =============================================================================
// File Name: l2_cache.v
// Design:    L2 unified cache — pass-through pre-caching skeleton
// Author:    Antigravity — Phase C
// Description:
//   Currently a transparent pass-through: upstream slave port wires
//   directly to downstream master port. Purpose is to have L2 present
//   in the DUT (memory subsystem) so future incremental caching logic
//   (tag/data arrays, MSHR, LRU) can be added behind this stable
//   interface without changing integration each time.
//
//   The caching implementation with tag/data/dirty/refill FSM lives in
//   rtl/cache/l2_cache_caching.v as l2_cache_caching (not currently
//   instantiated). It needs upstream burst handling (rlast/wlast tracking
//   across arlen+1 beats) before it can safely replace this pass-through
//   in DUT.
//
//   Port list matches docs/block_specs/l2_spec.md §7 so future upgrade
//   is drop-in.
// =============================================================================

module l2_cache #(
    parameter SIZE_BYTES = 32768,
    parameter LINE_BYTES = 32,
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,

    // Upstream slave
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

    // Downstream master
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

    // Snoop port (tied off)
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

    // ---- Pure pass-through wiring ----
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

endmodule
