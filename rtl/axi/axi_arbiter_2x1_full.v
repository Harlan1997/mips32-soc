// =============================================================================
// File Name: axi_arbiter_2x1_full.v
// Design:    AXI4 2x1 Arbiter/Interconnect (Full Read/Write)
// Author:    Antigravity
// Description:
//   Connects M0 (e.g. CPU) and M1 (e.g. DMA) to S0.
//   Simple arbitration: M1 has priority over M0.
//   Arbitrates both Read channels and Write channels.
// =============================================================================

module axi_arbiter_2x1_full (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0
    input  wire [3:0]  m0_awid,
    input  wire [31:0] m0_awaddr,
    input  wire [7:0]  m0_awlen,
    input  wire [2:0]  m0_awsize,
    input  wire [1:0]  m0_awburst,
    input  wire [1:0]  m0_awlock,
    input  wire [3:0]  m0_awcache,
    input  wire [2:0]  m0_awprot,
    input  wire        m0_awvalid,
    output wire        m0_awready,
    
    input  wire [31:0] m0_wdata,
    input  wire [3:0]  m0_wstrb,
    input  wire        m0_wlast,
    input  wire        m0_wvalid,
    output wire        m0_wready,
    
    output wire [3:0]  m0_bid,
    output wire [1:0]  m0_bresp,
    output wire        m0_bvalid,
    input  wire        m0_bready,

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
    
    // Master 1
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
    
    // Slave 0
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
    // Read Channels (AR, R) - Arbitration
    // =========================================================================
    localparam AR_IDLE = 1'b0;
    localparam AR_BUSY = 1'b1;
    
    reg        ar_state;
    reg        active_ar_master;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_state <= AR_IDLE;
            active_ar_master <= 1'b0;
        end else begin
            case (ar_state)
                AR_IDLE: begin
                    if (m1_arvalid) begin
                        active_ar_master <= 1'b1;
                        if (s0_arready) ar_state <= AR_BUSY;
                    end else if (m0_arvalid) begin
                        active_ar_master <= 1'b0;
                        if (s0_arready) ar_state <= AR_BUSY;
                    end
                end
                AR_BUSY: begin
                    if (s0_rvalid && s0_rready && s0_rlast) begin
                        ar_state <= AR_IDLE;
                    end
                end
            endcase
        end
    end
    
    wire sel_ar_m1 = (ar_state == AR_IDLE) ? m1_arvalid : active_ar_master;
    
    assign s0_arid    = sel_ar_m1 ? m1_arid    : m0_arid;
    assign s0_araddr  = sel_ar_m1 ? m1_araddr  : m0_araddr;
    assign s0_arlen   = sel_ar_m1 ? m1_arlen   : m0_arlen;
    assign s0_arsize  = sel_ar_m1 ? m1_arsize  : m0_arsize;
    assign s0_arburst = sel_ar_m1 ? m1_arburst : m0_arburst;
    assign s0_arlock  = sel_ar_m1 ? m1_arlock  : m0_arlock;
    assign s0_arcache = sel_ar_m1 ? m1_arcache : m0_arcache;
    assign s0_arprot  = sel_ar_m1 ? m1_arprot  : m0_arprot;
    assign s0_arvalid = (ar_state == AR_IDLE) ? (m1_arvalid | m0_arvalid) : 1'b0; 
    
    assign m1_arready = (ar_state == AR_IDLE && sel_ar_m1) ? s0_arready : 1'b0;
    assign m0_arready = (ar_state == AR_IDLE && !sel_ar_m1) ? s0_arready : 1'b0;
    
    assign m1_rid     = s0_rid;
    assign m1_rdata   = s0_rdata;
    assign m1_rresp   = s0_rresp;
    assign m1_rlast   = s0_rlast;
    assign m1_rvalid  = (active_ar_master == 1'b1) ? s0_rvalid : 1'b0;
    
    assign m0_rid     = s0_rid;
    assign m0_rdata   = s0_rdata;
    assign m0_rresp   = s0_rresp;
    assign m0_rlast   = s0_rlast;
    assign m0_rvalid  = (active_ar_master == 1'b0) ? s0_rvalid : 1'b0;
    
    assign s0_rready  = (active_ar_master == 1'b1) ? m1_rready : m0_rready;

    // =========================================================================
    // Write Channels (AW, W, B) - Arbitration
    // =========================================================================
    localparam AW_IDLE = 1'b0;
    localparam AW_BUSY = 1'b1;
    
    reg        aw_state;
    reg        active_aw_master;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_state <= AW_IDLE;
            active_aw_master <= 1'b0;
        end else begin
            case (aw_state)
                AW_IDLE: begin
                    if (m1_awvalid) begin
                        active_aw_master <= 1'b1;
                        if (s0_awready) aw_state <= AW_BUSY;
                    end else if (m0_awvalid) begin
                        active_aw_master <= 1'b0;
                        if (s0_awready) aw_state <= AW_BUSY;
                    end
                end
                AW_BUSY: begin
                    // Wait for BVALID (response) to finish the whole transaction
                    if (s0_bvalid && s0_bready) begin
                        aw_state <= AW_IDLE;
                    end
                end
            endcase
        end
    end
    
    wire sel_aw_m1 = (aw_state == AW_IDLE) ? m1_awvalid : active_aw_master;
    
    assign s0_awid    = sel_aw_m1 ? m1_awid    : m0_awid;
    assign s0_awaddr  = sel_aw_m1 ? m1_awaddr  : m0_awaddr;
    assign s0_awlen   = sel_aw_m1 ? m1_awlen   : m0_awlen;
    assign s0_awsize  = sel_aw_m1 ? m1_awsize  : m0_awsize;
    assign s0_awburst = sel_aw_m1 ? m1_awburst : m0_awburst;
    assign s0_awlock  = sel_aw_m1 ? m1_awlock  : m0_awlock;
    assign s0_awcache = sel_aw_m1 ? m1_awcache : m0_awcache;
    assign s0_awprot  = sel_aw_m1 ? m1_awprot  : m0_awprot;
    assign s0_awvalid = (aw_state == AW_IDLE) ? (m1_awvalid | m0_awvalid) : 1'b0;
    
    assign m1_awready = (aw_state == AW_IDLE && sel_aw_m1) ? s0_awready : 1'b0;
    assign m0_awready = (aw_state == AW_IDLE && !sel_aw_m1) ? s0_awready : 1'b0;
    
    // Route W channel based on active_aw_master
    assign s0_wdata   = active_aw_master ? m1_wdata  : m0_wdata;
    assign s0_wstrb   = active_aw_master ? m1_wstrb  : m0_wstrb;
    assign s0_wlast   = active_aw_master ? m1_wlast  : m0_wlast;
    assign s0_wvalid  = active_aw_master ? m1_wvalid : m0_wvalid;
    
    assign m1_wready  = active_aw_master ? s0_wready : 1'b0;
    assign m0_wready  = !active_aw_master ? s0_wready : 1'b0;
    
    // Route B channel based on active_aw_master
    assign m1_bid     = s0_bid;
    assign m1_bresp   = s0_bresp;
    assign m1_bvalid  = active_aw_master ? s0_bvalid : 1'b0;
    
    assign m0_bid     = s0_bid;
    assign m0_bresp   = s0_bresp;
    assign m0_bvalid  = !active_aw_master ? s0_bvalid : 1'b0;
    
    assign s0_bready  = active_aw_master ? m1_bready : m0_bready;

endmodule
