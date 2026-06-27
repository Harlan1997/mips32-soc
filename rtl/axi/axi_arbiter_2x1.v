// =============================================================================
// File Name: axi_arbiter_2x1.v
// Design:    AXI4 2x1 Arbiter/Interconnect
// Author:    Antigravity
// Description:
//   Connects M0 (I-Cache, Read Only) and M1 (D-Cache, R/W) to S0 (SRAM).
//   Simple arbitration: M1 has priority over M0.
//   AW/W/B channels: Directly passed from M1 to S0.
//   AR/R channels: Arbitrated between M0 and M1.
// =============================================================================

module axi_arbiter_2x1 (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0 (I-Cache) - AR / R only
    input  wire [3:0]  m0_arid,
    input  wire [31:0] m0_araddr,
    input  wire [7:0]  m0_arlen,
    input  wire [2:0]  m0_arsize,
    input  wire [1:0]  m0_arburst,
    input  wire [1:0]  m0_arlock,
    input  wire [3:0]  m0_arcache,
    input  wire [2:0]  m0_arprot,
    input  wire        m0_arvalid,
    output wire        m0_arready,
    
    output wire [3:0]  m0_rid,
    output wire [31:0] m0_rdata,
    output wire [1:0]  m0_rresp,
    output wire        m0_rlast,
    output wire        m0_rvalid,
    input  wire        m0_rready,
    
    // Master 1 (D-Cache) - Full AXI
    input  wire [3:0]  m1_awid,
    input  wire [31:0] m1_awaddr,
    input  wire [7:0]  m1_awlen,
    input  wire [2:0]  m1_awsize,
    input  wire [1:0]  m1_awburst,
    input  wire [1:0]  m1_awlock,
    input  wire [3:0]  m1_awcache,
    input  wire [2:0]  m1_awprot,
    input  wire        m1_awvalid,
    output wire        m1_awready,
    
    input  wire [31:0] m1_wdata,
    input  wire [3:0]  m1_wstrb,
    input  wire        m1_wlast,
    input  wire        m1_wvalid,
    output wire        m1_wready,
    
    output wire [3:0]  m1_bid,
    output wire [1:0]  m1_bresp,
    output wire        m1_bvalid,
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
    output wire        m1_arready,
    
    output wire [3:0]  m1_rid,
    output wire [31:0] m1_rdata,
    output wire [1:0]  m1_rresp,
    output wire        m1_rlast,
    output wire        m1_rvalid,
    input  wire        m1_rready,
    
    // Slave 0 (SRAM) - Full AXI
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
    output wire        s0_rready
);

    // =========================================================================
    // Write Channels (AW, W, B) - Direct Pass-Through for M1
    // =========================================================================
    assign s0_awid    = m1_awid;
    assign s0_awaddr  = m1_awaddr;
    assign s0_awlen   = m1_awlen;
    assign s0_awsize  = m1_awsize;
    assign s0_awburst = m1_awburst;
    assign s0_awlock  = m1_awlock;
    assign s0_awcache = m1_awcache;
    assign s0_awprot  = m1_awprot;
    assign s0_awvalid = m1_awvalid;
    assign m1_awready = s0_awready;
    
    assign s0_wdata   = m1_wdata;
    assign s0_wstrb   = m1_wstrb;
    assign s0_wlast   = m1_wlast;
    assign s0_wvalid  = m1_wvalid;
    assign m1_wready  = s0_wready;
    
    assign m1_bid     = s0_bid;
    assign m1_bresp   = s0_bresp;
    assign m1_bvalid  = s0_bvalid;
    assign s0_bready  = m1_bready;

    // =========================================================================
    // Read Channels (AR, R) - Arbitration
    // =========================================================================
    localparam AR_IDLE = 1'b0;
    localparam AR_BUSY = 1'b1;
    
    reg        ar_state;
    reg        active_master; // 0 for M0, 1 for M1
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_state <= AR_IDLE;
            active_master <= 1'b0;
        end else begin
            case (ar_state)
                AR_IDLE: begin
                    if (m1_arvalid) begin
                        active_master <= 1'b1;
                        if (s0_arready) ar_state <= AR_BUSY;
                    end else if (m0_arvalid) begin
                        active_master <= 1'b0;
                        if (s0_arready) ar_state <= AR_BUSY;
                    end
                end
                AR_BUSY: begin
                    // Wait for the read transaction to finish (RLAST)
                    if (s0_rvalid && s0_rready && s0_rlast) begin
                        ar_state <= AR_IDLE;
                    end
                end
            endcase
        end
    end
    
    // AR Mux
    wire sel_m1 = (ar_state == AR_IDLE) ? m1_arvalid : active_master;
    
    assign s0_arid    = sel_m1 ? m1_arid    : m0_arid;
    assign s0_araddr  = sel_m1 ? m1_araddr  : m0_araddr;
    assign s0_arlen   = sel_m1 ? m1_arlen   : m0_arlen;
    assign s0_arsize  = sel_m1 ? m1_arsize  : m0_arsize;
    assign s0_arburst = sel_m1 ? m1_arburst : m0_arburst;
    assign s0_arlock  = sel_m1 ? m1_arlock  : m0_arlock;
    assign s0_arcache = sel_m1 ? m1_arcache : m0_arcache;
    assign s0_arprot  = sel_m1 ? m1_arprot  : m0_arprot;
    assign s0_arvalid = (ar_state == AR_IDLE) ? (m1_arvalid | m0_arvalid) : 1'b0; 
    
    // In AR_IDLE, ready is routed to the selected master (if they asserted valid)
    // If not in IDLE, no new AR is accepted.
    assign m1_arready = (ar_state == AR_IDLE && sel_m1) ? s0_arready : 1'b0;
    assign m0_arready = (ar_state == AR_IDLE && !sel_m1) ? s0_arready : 1'b0;
    
    // R Demux
    assign m1_rid     = s0_rid;
    assign m1_rdata   = s0_rdata;
    assign m1_rresp   = s0_rresp;
    assign m1_rlast   = s0_rlast;
    assign m1_rvalid  = (active_master == 1'b1) ? s0_rvalid : 1'b0;
    
    assign m0_rid     = s0_rid;
    assign m0_rdata   = s0_rdata;
    assign m0_rresp   = s0_rresp;
    assign m0_rlast   = s0_rlast;
    assign m0_rvalid  = (active_master == 1'b0) ? s0_rvalid : 1'b0;
    
    assign s0_rready  = (active_master == 1'b1) ? m1_rready : m0_rready;

endmodule
