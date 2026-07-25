// =============================================================================
// File Name: axi2apb_bridge.v
// Design:    AXI4 Lite to APB Bridge
// Author:    Antigravity
// Description:
//   Converts simple AXI4 accesses to APB.
//   Writes are accepted as a single APB transfer. Reads complete all requested
//   AXI beats by issuing one APB read per beat.
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

    localparam IDLE    = 3'd0;
    localparam W_SETUP = 3'd1;
    localparam W_ENABLE= 3'd2;
    localparam W_RESP  = 3'd3;
    localparam R_SETUP = 3'd4;
    localparam R_ENABLE= 3'd5;
    localparam R_RESP  = 3'd6;
    
    reg [2:0] state, next_state;
    
    reg aw_received;
    reg w_received;
    reg [31:0] awaddr_latch;
    reg [31:0] wdata_latch;
    reg [3:0]  wstrb_latch;
    reg [31:0] araddr_latch;
    reg [3:0]  awid_latch;
    reg [3:0]  arid_latch;
    reg [7:0]  arlen_latch;
    reg [2:0]  arsize_latch;
    reg [1:0]  arburst_latch;
    reg [7:0]  rbeat_latch;
    reg [31:0] rdata_latch;
    reg [1:0]  rresp_latch;
    reg        rlast_latch;
    reg [1:0]  bresp_latch;
    
    // VCS coverage off
    assign s_awready = (state == IDLE && !aw_received);
    assign s_wready  = (state == IDLE && !w_received);
    assign s_arready = (state == IDLE && !s_awvalid && !aw_received && !w_received);
    
    wire aw_done = aw_received || (s_awvalid && s_awready);
    wire w_done  = w_received || (s_wvalid && s_wready);
    // VCS coverage on
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            state <= IDLE;
            // VCS coverage on
        end
        else        state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (aw_done && w_done) next_state = W_SETUP;
                else if (s_arvalid && s_arready) next_state = R_SETUP;
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
                if (pready) next_state = R_RESP;
            end

            R_RESP: begin
                if (s_rready) begin
                    if (rlast_latch) next_state = IDLE;
                    else             next_state = R_SETUP;
                end
            end
            
            // VCS coverage off
            default: next_state = IDLE;
            // VCS coverage on
        endcase
    end
    
    // Latch AW and W channels independently
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_received <= 1'b0;
            w_received <= 1'b0;
            awaddr_latch <= 32'd0;
            awid_latch <= 4'd0;
            wdata_latch <= 32'd0;
            wstrb_latch <= 4'd0;
            arid_latch <= 4'd0;
            araddr_latch <= 32'd0;
            arlen_latch <= 8'd0;
            arsize_latch <= 3'd2;
            arburst_latch <= 2'b01;
            rbeat_latch <= 8'd0;
            rdata_latch <= 32'd0;
            rresp_latch <= 2'b00;
            rlast_latch <= 1'b0;
            bresp_latch <= 2'b00;
        end else begin
            if (state == IDLE) begin
                if (s_awvalid && s_awready) begin
                    aw_received <= 1'b1;
                    awaddr_latch <= s_awaddr;
                    awid_latch <= s_awid;
                end
                if (s_wvalid && s_wready) begin
                    w_received <= 1'b1;
                    wdata_latch <= s_wdata;
                    wstrb_latch <= s_wstrb;
                end
                if (s_arvalid && s_arready) begin
                    arid_latch <= s_arid;
                    araddr_latch <= s_araddr;
                    arlen_latch <= s_arlen;
                    arsize_latch <= s_arsize;
                    arburst_latch <= s_arburst;
                    rbeat_latch <= 8'd0;
                end
            end else if (state == W_RESP && s_bready) begin
                aw_received <= 1'b0;
                w_received <= 1'b0;
            end

            if (state == R_ENABLE && pready) begin
                rdata_latch <= prdata;
                rresp_latch <= pslverr ? 2'b10 : 2'b00;
                rlast_latch <= (rbeat_latch == arlen_latch);
            end

            if (state == W_ENABLE && pready) begin
                bresp_latch <= pslverr ? 2'b10 : 2'b00;
            end

            if (state == R_RESP && s_rready && !rlast_latch) begin
                rbeat_latch <= rbeat_latch + 8'd1;
            end
        end
    end
    
    assign s_bvalid  = (state == W_RESP);
    assign s_bresp   = bresp_latch;
    assign s_bid     = awid_latch;
    
    assign s_rvalid  = (state == R_RESP);
    assign s_rdata   = rdata_latch;
    assign s_rresp   = rresp_latch;
    assign s_rlast   = rlast_latch;
    assign s_rid     = arid_latch;

    wire [7:0]  read_setup_beat = (state == R_RESP && s_rready && !rlast_latch) ?
                                   (rbeat_latch + 8'd1) : rbeat_latch;
    wire [31:0] read_setup_addr = (arburst_latch == 2'b01) ?
                                  (araddr_latch + ({24'd0, read_setup_beat} << arsize_latch)) :
                                  araddr_latch;
    
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
                    paddr   <= (state == IDLE) ? (s_awvalid ? s_awaddr : awaddr_latch) : awaddr_latch;
                    pwdata  <= (state == IDLE) ? (s_wvalid ? s_wdata : wdata_latch) : wdata_latch;
                    pstrb   <= (state == IDLE) ? (s_wvalid ? s_wstrb : wstrb_latch) : wstrb_latch;
                end
                
                W_ENABLE: begin
                    penable <= 1'b1;
                end
                
                R_SETUP: begin
                    psel    <= 1'b1;
                    penable <= 1'b0;
                    pwrite  <= 1'b0;
                    paddr   <= (state == IDLE) ? s_araddr : read_setup_addr;
                end
                
                R_ENABLE: begin
                    penable <= 1'b1;
                end
                
                W_RESP: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                end

                R_RESP: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                end
                
                // VCS coverage off
                default: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                end
                // VCS coverage on
            endcase
        end
    end
endmodule
