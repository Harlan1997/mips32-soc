// =============================================================================
// File Name: axi_ddr_model.v
// Design:    AXI4 DDR Behavioral Model
// Author:    Antigravity
// Description:
//   An AXI4 slave that simulates DDR memory with high latency, 
//   random backpressure, and periodic refresh stalls.
// =============================================================================

module axi_ddr_model #(
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
    output wire        s_awready,
    // W Channel
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
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
    output wire        s_arready,
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
    reg [1023:0] firmware_hex;
    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1) begin
            ram[i] = 32'd0;
        end
        firmware_hex = "firmware.hex";
        if ($value$plusargs("FW_HEX=%s", firmware_hex)) begin
            $display("axi_ddr_model: loading firmware from %0s", firmware_hex);
        end else begin
            $display("axi_ddr_model: loading default firmware.hex");
        end
        load_hex(firmware_hex);
    end

    // synopsys translate_off
    task load_hex;
        input [1023:0] hex_path;
        begin
            $readmemh(hex_path, ram);
        end
    endtask
    // synopsys translate_on

    // Simple 16-bit LFSR for pseudo-random delays
    reg [15:0] lfsr;
    wire lfsr_feedback = ~(lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hACE1;
        else
            lfsr <= {lfsr[14:0], lfsr_feedback};
    end

    // Random backpressure & delay generation
    // 25% chance of asserting backpressure (READY = 0)
    wire rand_backpressure = (lfsr[1:0] == 2'd0);
    // Periodically simulate DDR Refresh (5% chance, takes 10-20 cycles)
    reg [7:0] refresh_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_counter <= 8'd0;
        end else begin
            if (refresh_counter > 0)
                refresh_counter <= refresh_counter - 1'b1;
            else if (lfsr[11:6] == 6'd0) // Low probability
                refresh_counter <= lfsr[7:3] + 8'd10; // Random refresh stall
        end
    end
    
    wire ddr_busy = (refresh_counter > 0);
    
    // Internal ready signals
    reg int_awready;
    reg int_wready;
    reg int_arready;
    reg int_rvalid;
    
    // Final outputs are masked by DDR busy and random backpressure
    assign s_awready = int_awready & ~ddr_busy & ~rand_backpressure;
    assign s_wready  = int_wready & ~ddr_busy & ~rand_backpressure;
    assign s_arready = int_arready & ~ddr_busy & ~rand_backpressure;

    // =========================================================================
    // Read Logic
    // =========================================================================
    localparam R_IDLE  = 3'd0;
    localparam R_WAIT  = 3'd1;
    localparam R_BURST = 3'd2;
    
    reg [2:0]  r_state;
    reg [31:0] r_addr;
    reg [7:0]  r_len;
    reg [3:0]  r_id;
    reg [7:0]  r_wait_cycles;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state     <= R_IDLE;
            r_addr      <= 32'd0;
            r_len       <= 8'd0;
            r_id        <= 4'd0;
            r_wait_cycles <= 8'd0;
            int_arready <= 1'b1;
            s_rvalid    <= 1'b0;
            s_rlast     <= 1'b0;
            s_rdata     <= 32'd0;
            s_rid       <= 4'd0;
            s_rresp     <= 2'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    int_arready <= 1'b1;
                    if (s_arvalid && s_arready) begin
                        int_arready <= 1'b0;
                        r_addr    <= s_araddr;
                        r_len     <= s_arlen;
                        r_id      <= s_arid;
                        // Simulating CAS Latency (e.g., 5 to 30 cycles)
                        r_wait_cycles <= {3'd0, lfsr[12:8]} + 8'd5;
                        r_state   <= R_WAIT;
                    end
                end
                R_WAIT: begin
                    if (ddr_busy) begin
                        // Do nothing, stalled by refresh
                    end else if (r_wait_cycles > 0) begin
                        r_wait_cycles <= r_wait_cycles - 1'b1;
                    end else begin
                        r_state   <= R_BURST;
                        s_rvalid  <= 1'b1;
                        s_rlast   <= (r_len == 8'd0);
                        s_rid     <= r_id;
                        s_rresp   <= 2'b00; // OKAY
                        s_rdata   <= ram[r_addr[15:2]];
                    end
                end
                R_BURST: begin
                    if (s_rvalid && s_rready) begin
                        if (r_len == 8'd0) begin
                            s_rvalid  <= 1'b0;
                            s_rlast   <= 1'b0;
                            r_state   <= R_IDLE;
                        end else begin
                            r_addr    <= r_addr + 32'd4;
                            r_len     <= r_len - 1'b1;
                            s_rlast   <= (r_len == 8'd1);
                            s_rdata   <= ram[(r_addr[15:0] + 16'd4) >> 2];
                            
                            // 10% chance to drop RVALID momentarily in middle of burst
                            if (lfsr[4:2] == 3'd0) begin
                                s_rvalid <= 1'b0;
                                r_wait_cycles <= lfsr[10:9] + 8'd1; // wait 1-4 cycles
                                r_state <= R_WAIT;
                            end
                        end
                    end else if (s_rvalid && !s_rready) begin
                        // stall
                    end else if (!s_rvalid) begin
                        // If we dropped valid to simulate bubbles
                        s_rvalid <= 1'b1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Write Logic
    // =========================================================================
    localparam W_IDLE  = 3'd0;
    localparam W_WAIT  = 3'd1;
    localparam W_DATA  = 3'd2;
    localparam W_RESP  = 3'd3;

    reg [2:0]  w_state;
    reg [31:0] w_addr;
    reg [7:0]  w_len;
    reg [3:0]  w_id;
    reg [7:0]  w_wait_cycles;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state     <= W_IDLE;
            w_addr      <= 32'd0;
            w_len       <= 8'd0;
            w_id        <= 4'd0;
            w_wait_cycles <= 8'd0;
            int_awready <= 1'b0; // Wait a cycle before ready
            int_wready  <= 1'b0;
            s_bvalid    <= 1'b0;
            s_bresp     <= 2'd0;
            s_bid       <= 4'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    int_awready <= 1'b1;
                    int_wready  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        int_awready <= 1'b0;
                        w_addr    <= s_awaddr;
                        w_len     <= s_awlen;
                        w_id      <= s_awid;
                        w_wait_cycles <= lfsr[8:5] + 8'd2; // 2 to 17 cycles before WREADY
                        w_state   <= W_WAIT;
                    end
                end
                
                W_WAIT: begin
                    if (!ddr_busy && w_wait_cycles > 0) begin
                        w_wait_cycles <= w_wait_cycles - 1'b1;
                    end else if (!ddr_busy) begin
                        w_state   <= W_DATA;
                        int_wready <= 1'b1;
                    end
                end
                
                W_DATA: begin
                    if (s_wvalid && s_wready) begin
                        if (s_wstrb[0]) ram[w_addr[15:2]][7:0]   <= s_wdata[7:0];
                        if (s_wstrb[1]) ram[w_addr[15:2]][15:8]  <= s_wdata[15:8];
                        if (s_wstrb[2]) ram[w_addr[15:2]][23:16] <= s_wdata[23:16];
                        if (s_wstrb[3]) ram[w_addr[15:2]][31:24] <= s_wdata[31:24];

                        if (s_wlast) begin
                            int_wready <= 1'b0;
                            s_bvalid   <= 1'b1;
                            s_bresp    <= 2'b00; // OKAY
                            s_bid      <= w_id;
                            w_state    <= W_RESP;
                        end else begin
                            w_addr <= w_addr + 32'd4;
                            w_len  <= w_len - 1'b1;
                            
                            // 12.5% chance to drop WREADY for a few cycles
                            if (lfsr[11:9] == 3'd7) begin
                                int_wready <= 1'b0;
                                w_wait_cycles <= lfsr[3:2] + 8'd1;
                                w_state <= W_WAIT;
                            end
                        end
                    end
                end
                
                W_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid <= 1'b0;
                        w_state  <= W_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
