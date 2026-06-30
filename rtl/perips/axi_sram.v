// =============================================================================
// File Name: axi_sram.v
// Design:    AXI4 SRAM Controller (Integrated SRAM)
// Author:    Antigravity
// Description:
//   An AXI4 slave that provides on-chip synchronous RAM.
//   Supports INCR bursts from caches (up to 32B/line).
// =============================================================================

module axi_sram #(
    parameter MEM_DEPTH_WORDS = 16384 // 64KB
) (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Slave Interface
    // AW Channel
    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire        s_awvalid,
    output reg         s_awready,
    // W Channel
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output reg         s_wready,
    // B Channel
    output reg  [3:0]  s_bid,
    output reg  [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,
    // AR Channel
    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire        s_arvalid,
    output reg         s_arready,
    // R Channel
    output reg  [3:0]  s_rid,
    output reg  [31:0] s_rdata,
    output reg  [1:0]  s_rresp,
    output reg         s_rlast,
    output reg         s_rvalid,
    input  wire        s_rready
);

    // Memory array
    reg [31:0] ram [0:MEM_DEPTH_WORDS-1];

    // Initialize with 0
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1) begin
            ram[i] = 32'd0;
        end
        // Optional: Preload with some hex file if needed
        // $readmemh("boot.hex", ram);
    end

    // =========================================================================
    // Read Logic
    // =========================================================================
    localparam R_IDLE = 2'd0;
    localparam R_BURST = 2'd1;
    
    reg [1:0]  r_state, r_next;
    reg [31:0] r_addr;
    reg [7:0]  r_len;
    reg [3:0]  r_id;

    wire [31:0] word_addr_r = r_addr[31:2]; // Word aligned
    wire valid_read_addr = (word_addr_r < MEM_DEPTH_WORDS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            r_state   <= R_IDLE;
            // VCS coverage on
            r_addr    <= 32'd0;
            r_len     <= 8'd0;
            r_id      <= 4'd0;
            s_arready <= 1'b0;
            s_rvalid  <= 1'b0;
            s_rlast   <= 1'b0;
            s_rdata   <= 32'd0;
            s_rid     <= 4'd0;
            s_rresp   <= 2'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_arready <= 1'b1;
                    if (s_arvalid && s_arready) begin
                        s_arready <= 1'b0;
                        r_addr    <= s_araddr;
                        r_len     <= s_arlen;
                        r_id      <= s_arid;
                        r_state   <= R_BURST;
                        
                        s_rvalid  <= 1'b1;
                        s_rlast   <= (s_arlen == 8'd0);
                        s_rid     <= s_arid;
                        s_rresp   <= 2'b00; // OKAY
                        // Provide first data
                        s_rdata   <= ram[s_araddr[15:2]];
                    end
                end
                R_BURST: begin
                    if (s_rvalid && s_rready) begin
                        if (r_len == 8'd0) begin
                            // Burst complete
                            s_rvalid  <= 1'b0;
                            s_rlast   <= 1'b0;
                            r_state   <= R_IDLE;
                            s_arready <= 1'b1;
                        end else begin
                            // Next beat
                            r_addr    <= r_addr + 32'd4; // Increment address by 4 bytes (INCR)
                            r_len     <= r_len - 1'b1;
                            
                            s_rlast   <= (r_len == 8'd1);
                            s_rdata   <= ram[(r_addr[15:0] + 16'd4) >> 2];
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Write Logic
    // =========================================================================
    localparam W_IDLE  = 2'd0;
    localparam W_DATA  = 2'd1;
    localparam W_RESP  = 2'd2;

    reg [1:0]  w_state;
    reg [31:0] w_addr;
    reg [7:0]  w_len;
    reg [3:0]  w_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            w_state   <= W_IDLE;
            // VCS coverage on
            w_addr    <= 32'd0;
            w_len     <= 8'd0;
            w_id      <= 4'd0;
            s_awready <= 1'b0;
            s_wready  <= 1'b0;
            s_bvalid  <= 1'b0;
            s_bresp   <= 2'd0;
            s_bid     <= 4'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_awready <= 1'b1;
                    s_wready  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        s_awready <= 1'b0;
                        w_addr    <= s_awaddr;
                        w_len     <= s_awlen;
                        w_id      <= s_awid;
                        w_state   <= W_DATA;
                        s_wready  <= 1'b1;
                    end
                end
                
                W_DATA: begin
                    if (s_wvalid && s_wready) begin
                        // Perform write
                        if (s_wstrb[0]) ram[w_addr[15:2]][7:0]   <= s_wdata[7:0];
                        if (s_wstrb[1]) ram[w_addr[15:2]][15:8]  <= s_wdata[15:8];
                        if (s_wstrb[2]) ram[w_addr[15:2]][23:16] <= s_wdata[23:16];
                        if (s_wstrb[3]) ram[w_addr[15:2]][31:24] <= s_wdata[31:24];

                        if (s_wlast) begin
                            s_wready <= 1'b0;
                            s_bvalid <= 1'b1;
                            s_bresp  <= 2'b00; // OKAY
                            s_bid    <= w_id;
                            w_state  <= W_RESP;
                        end else begin
                            w_addr <= w_addr + 32'd4;
                            w_len  <= w_len - 1'b1;
                        end
                    end
                end
                
                W_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid <= 1'b0;
                        w_state  <= W_IDLE;
                        s_awready <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
