// =============================================================================
// File Name: axi_arbiter_2x1_full.v
// Design:    AXI4 2x1 Arbiter/Interconnect (Full Read/Write)
// Author:    Antigravity
// Description:
//   Connects M0 (e.g. CPU) and M1 (e.g. DMA) to S0.
//   Single-outstanding round-robin arbitration for read and write channels.
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
    localparam AR_IDLE = 2'd0;
    localparam AR_WAIT = 2'd1;
    localparam AR_BUSY = 2'd2;
    
    reg [1:0]  ar_state;
    reg        active_r_master; // 0 for M0, 1 for M1
    reg        rr_next_r_master;
    reg [3:0]  arid_latch;
    reg [31:0] araddr_latch;
    reg [7:0]  arlen_latch;
    reg [2:0]  arsize_latch;
    reg [1:0]  arburst_latch;
    reg [1:0]  arlock_latch;
    reg [3:0]  arcache_latch;
    reg [2:0]  arprot_latch;

    wire choose_m1_ar = m1_arvalid && (!m0_arvalid || rr_next_r_master);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_state <= AR_IDLE;
            active_r_master <= 1'b0;
            rr_next_r_master <= 1'b1;
            arid_latch <= 4'h0;
            araddr_latch <= 32'h0;
            arlen_latch <= 8'h0;
            arsize_latch <= 3'h0;
            arburst_latch <= 2'h0;
            arlock_latch <= 2'h0;
            arcache_latch <= 4'h0;
            arprot_latch <= 3'h0;
        end else begin
            case (ar_state)
                AR_IDLE: begin
                    if (m0_arvalid || m1_arvalid) begin
                        active_r_master <= choose_m1_ar;
                        arid_latch    <= choose_m1_ar ? m1_arid    : m0_arid;
                        araddr_latch  <= choose_m1_ar ? m1_araddr  : m0_araddr;
                        arlen_latch   <= choose_m1_ar ? m1_arlen   : m0_arlen;
                        arsize_latch  <= choose_m1_ar ? m1_arsize  : m0_arsize;
                        arburst_latch <= choose_m1_ar ? m1_arburst : m0_arburst;
                        arlock_latch  <= choose_m1_ar ? m1_arlock  : m0_arlock;
                        arcache_latch <= choose_m1_ar ? m1_arcache : m0_arcache;
                        arprot_latch  <= choose_m1_ar ? m1_arprot  : m0_arprot;
                        if (s0_arready) begin
                            ar_state <= AR_BUSY;
                            rr_next_r_master <= !choose_m1_ar;
                        end else begin
                            ar_state <= AR_WAIT;
                        end
                    end
                end
                AR_WAIT: begin
                    if (s0_arready) begin
                        ar_state <= AR_BUSY;
                        rr_next_r_master <= !active_r_master;
                    end
                end
                AR_BUSY: begin
                    if (s0_rvalid && s0_rready && s0_rlast) begin
                        ar_state <= AR_IDLE;
                    end
                end
                default: ar_state <= AR_IDLE;
            endcase
        end
    end
    
    // AR Mux
    wire sel_r_m1 = (ar_state == AR_IDLE) ? choose_m1_ar : active_r_master;
    wire ar_waiting = (ar_state == AR_WAIT);
    
    assign s0_arid    = ar_waiting ? arid_latch    : (sel_r_m1 ? m1_arid    : m0_arid);
    assign s0_araddr  = ar_waiting ? araddr_latch  : (sel_r_m1 ? m1_araddr  : m0_araddr);
    assign s0_arlen   = ar_waiting ? arlen_latch   : (sel_r_m1 ? m1_arlen   : m0_arlen);
    assign s0_arsize  = ar_waiting ? arsize_latch  : (sel_r_m1 ? m1_arsize  : m0_arsize);
    assign s0_arburst = ar_waiting ? arburst_latch : (sel_r_m1 ? m1_arburst : m0_arburst);
    assign s0_arlock  = ar_waiting ? arlock_latch  : (sel_r_m1 ? m1_arlock  : m0_arlock);
    assign s0_arcache = ar_waiting ? arcache_latch : (sel_r_m1 ? m1_arcache : m0_arcache);
    assign s0_arprot  = ar_waiting ? arprot_latch  : (sel_r_m1 ? m1_arprot  : m0_arprot);
    assign s0_arvalid = (ar_state == AR_IDLE) ? (m1_arvalid | m0_arvalid) : (ar_state == AR_WAIT ? 1'b1 : 1'b0); 
    
    assign m1_arready = (ar_state == AR_IDLE && choose_m1_ar) ? s0_arready : ((ar_state == AR_WAIT && active_r_master) ? s0_arready : 1'b0);
    assign m0_arready = (ar_state == AR_IDLE && !choose_m1_ar && m0_arvalid) ? s0_arready : ((ar_state == AR_WAIT && !active_r_master) ? s0_arready : 1'b0);
    
    assign m1_rid     = s0_rid;
    assign m1_rdata   = s0_rdata;
    assign m1_rresp   = s0_rresp;
    assign m1_rlast   = s0_rlast;
    assign m1_rvalid  = (ar_state == AR_BUSY && active_r_master == 1'b1) ? s0_rvalid : 1'b0;
    
    assign m0_rid     = s0_rid;
    assign m0_rdata   = s0_rdata;
    assign m0_rresp   = s0_rresp;
    assign m0_rlast   = s0_rlast;
    assign m0_rvalid  = (ar_state == AR_BUSY && active_r_master == 1'b0) ? s0_rvalid : 1'b0;
    
    assign s0_rready  = (ar_state == AR_BUSY) ? (active_r_master ? m1_rready : m0_rready) : 1'b0;

    // =========================================================================
    // Write Channels (AW, W, B) - Arbitration
    // =========================================================================
    localparam AW_IDLE = 2'd0;
    localparam AW_WAIT = 2'd1;
    localparam AW_BUSY = 2'd2;
    
    reg [1:0]  aw_state;
    reg        active_w_master; // 0 for M0, 1 for M1
    reg        rr_next_w_master;
    reg [3:0]  awid_latch;
    reg [31:0] awaddr_latch;
    reg [7:0]  awlen_latch;
    reg [2:0]  awsize_latch;
    reg [1:0]  awburst_latch;
    reg [1:0]  awlock_latch;
    reg [3:0]  awcache_latch;
    reg [2:0]  awprot_latch;

    wire choose_m1_aw = m1_awvalid && (!m0_awvalid || rr_next_w_master);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_state <= AW_IDLE;
            active_w_master <= 1'b0;
            rr_next_w_master <= 1'b1;
            awid_latch <= 4'h0;
            awaddr_latch <= 32'h0;
            awlen_latch <= 8'h0;
            awsize_latch <= 3'h0;
            awburst_latch <= 2'h0;
            awlock_latch <= 2'h0;
            awcache_latch <= 4'h0;
            awprot_latch <= 3'h0;
        end else begin
            case (aw_state)
                AW_IDLE: begin
                    if (m0_awvalid || m1_awvalid) begin
                        active_w_master <= choose_m1_aw;
                        awid_latch    <= choose_m1_aw ? m1_awid    : m0_awid;
                        awaddr_latch  <= choose_m1_aw ? m1_awaddr  : m0_awaddr;
                        awlen_latch   <= choose_m1_aw ? m1_awlen   : m0_awlen;
                        awsize_latch  <= choose_m1_aw ? m1_awsize  : m0_awsize;
                        awburst_latch <= choose_m1_aw ? m1_awburst : m0_awburst;
                        awlock_latch  <= choose_m1_aw ? m1_awlock  : m0_awlock;
                        awcache_latch <= choose_m1_aw ? m1_awcache : m0_awcache;
                        awprot_latch  <= choose_m1_aw ? m1_awprot  : m0_awprot;
                        if (s0_awready) begin
                            aw_state <= AW_BUSY;
                            rr_next_w_master <= !choose_m1_aw;
                        end else begin
                            aw_state <= AW_WAIT;
                        end
                    end
                end
                AW_WAIT: begin
                    if (s0_awready) begin
                        aw_state <= AW_BUSY;
                        rr_next_w_master <= !active_w_master;
                    end
                end
                AW_BUSY: begin
                    if (s0_bvalid && s0_bready) begin
                        aw_state <= AW_IDLE;
                    end
                end
                default: aw_state <= AW_IDLE;
            endcase
        end
    end
    
    // AW Mux
    wire sel_aw_m1 = (aw_state == AW_IDLE) ? choose_m1_aw : active_w_master;
    wire aw_waiting = (aw_state == AW_WAIT);
    
    assign s0_awid    = aw_waiting ? awid_latch    : (sel_aw_m1 ? m1_awid    : m0_awid);
    assign s0_awaddr  = aw_waiting ? awaddr_latch  : (sel_aw_m1 ? m1_awaddr  : m0_awaddr);
    assign s0_awlen   = aw_waiting ? awlen_latch   : (sel_aw_m1 ? m1_awlen   : m0_awlen);
    assign s0_awsize  = aw_waiting ? awsize_latch  : (sel_aw_m1 ? m1_awsize  : m0_awsize);
    assign s0_awburst = aw_waiting ? awburst_latch : (sel_aw_m1 ? m1_awburst : m0_awburst);
    assign s0_awlock  = aw_waiting ? awlock_latch  : (sel_aw_m1 ? m1_awlock  : m0_awlock);
    assign s0_awcache = aw_waiting ? awcache_latch : (sel_aw_m1 ? m1_awcache : m0_awcache);
    assign s0_awprot  = aw_waiting ? awprot_latch  : (sel_aw_m1 ? m1_awprot  : m0_awprot);
    assign s0_awvalid = (aw_state == AW_IDLE) ? (m1_awvalid | m0_awvalid) : (aw_state == AW_WAIT ? 1'b1 : 1'b0);
    
    assign m1_awready = (aw_state == AW_IDLE && choose_m1_aw) ? s0_awready : ((aw_state == AW_WAIT && active_w_master) ? s0_awready : 1'b0);
    assign m0_awready = (aw_state == AW_IDLE && !choose_m1_aw && m0_awvalid) ? s0_awready : ((aw_state == AW_WAIT && !active_w_master) ? s0_awready : 1'b0);
    
    // Route W channel based on active_w_master
    assign s0_wdata   = active_w_master ? m1_wdata  : m0_wdata;
    assign s0_wstrb   = active_w_master ? m1_wstrb  : m0_wstrb;
    assign s0_wlast   = active_w_master ? m1_wlast  : m0_wlast;
    assign s0_wvalid  = (aw_state == AW_BUSY) ? (active_w_master ? m1_wvalid : m0_wvalid) : 1'b0;
    
    assign m1_wready  = (aw_state == AW_BUSY && active_w_master) ? s0_wready : 1'b0;
    assign m0_wready  = (aw_state == AW_BUSY && !active_w_master) ? s0_wready : 1'b0;
    
    // Route B channel based on active_w_master
    assign m1_bid     = s0_bid;
    assign m1_bresp   = s0_bresp;
    assign m1_bvalid  = (aw_state == AW_BUSY && active_w_master) ? s0_bvalid : 1'b0;
    
    assign m0_bid     = s0_bid;
    assign m0_bresp   = s0_bresp;
    assign m0_bvalid  = (aw_state == AW_BUSY && !active_w_master) ? s0_bvalid : 1'b0;
    
    assign s0_bready  = (aw_state == AW_BUSY) ? (active_w_master ? m1_bready : m0_bready) : 1'b0;

endmodule
