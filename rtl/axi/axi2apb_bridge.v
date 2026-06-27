// =============================================================================
// File Name: axi2apb_bridge.v
// Design:    AXI4 Lite to APB Bridge
// Author:    Antigravity
// Description:
//   Converts simple single-beat AXI4 (or AXI-Lite) to APB.
//   Assumes burst length = 0 (1 beat).
// =============================================================================

module axi2apb_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // AXI Slave Interface (Single Beat)
    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire [1:0]  s_awlock,
    input  wire [3:0]  s_awcache,
    input  wire [2:0]  s_awprot,
    input  wire        s_awvalid,
    output wire        s_awready,
    
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    
    output wire [3:0]  s_bid,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    
    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire [1:0]  s_arlock,
    input  wire [3:0]  s_arcache,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,
    
    output wire [3:0]  s_rid,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    output wire        s_rvalid,
    input  wire        s_rready,
    
    // APB Master Interface
    output reg  [31:0] paddr,
    output reg         psel,
    output reg         penable,
    output reg         pwrite,
    output reg  [31:0] pwdata,
    output reg  [3:0]  pstrb,
    input  wire        pready,
    input  wire [31:0] prdata,
    input  wire        pslverr
);

    localparam IDLE   = 3'd0;
    localparam W_SETUP = 3'd1;
    localparam W_ENABLE= 3'd2;
    localparam W_RESP  = 3'd3;
    localparam R_SETUP = 3'd4;
    localparam R_ENABLE= 3'd5;
    
    reg [2:0] state, next_state;
    
    reg [3:0] awid_latch;
    reg [3:0] arid_latch;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (s_awvalid && s_wvalid) next_state = W_SETUP;
                else if (s_arvalid) next_state = R_SETUP;
            end
            
            W_SETUP: begin
                next_state = W_ENABLE;
            end
            
            W_ENABLE: begin
                if (pready) next_state = W_RESP;
            end
            
            W_RESP: begin
                if (s_bready) next_state = IDLE;
            end
            
            R_SETUP: begin
                next_state = R_ENABLE;
            end
            
            R_ENABLE: begin
                if (pready) next_state = IDLE;
            end
        endcase
    end
    
    // AXI outputs
    assign s_awready = (state == IDLE && s_awvalid && s_wvalid);
    assign s_wready  = (state == IDLE && s_awvalid && s_wvalid);
    
    assign s_arready = (state == IDLE && !s_awvalid && s_arvalid);
    
    assign s_bvalid  = (state == W_RESP);
    assign s_bresp   = 2'b00;
    assign s_bid     = awid_latch;
    
    assign s_rvalid  = (state == R_ENABLE && pready);
    assign s_rdata   = prdata;
    assign s_rresp   = 2'b00;
    assign s_rlast   = 1'b1;
    assign s_rid     = arid_latch;
    
    // Latch IDs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awid_latch <= 4'd0;
            arid_latch <= 4'd0;
        end else begin
            if (s_awready && s_awvalid) awid_latch <= s_awid;
            if (s_arready && s_arvalid) arid_latch <= s_arid;
        end
    end
    
    // APB Outputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
            paddr   <= 32'd0;
            pwdata  <= 32'd0;
            pstrb   <= 4'd0;
        end else begin
            case (next_state)
                IDLE: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                end
                
                W_SETUP: begin
                    psel    <= 1'b1;
                    penable <= 1'b0;
                    pwrite  <= 1'b1;
                    paddr   <= s_awaddr;
                    pwdata  <= s_wdata;
                    pstrb   <= s_wstrb;
                end
                
                W_ENABLE: begin
                    penable <= 1'b1;
                end
                
                R_SETUP: begin
                    psel    <= 1'b1;
                    penable <= 1'b0;
                    pwrite  <= 1'b0;
                    paddr   <= s_araddr;
                end
                
                R_ENABLE: begin
                    penable <= 1'b1;
                end
                
                W_RESP: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                end
            endcase
        end
    end

endmodule
