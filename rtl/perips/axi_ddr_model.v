// =============================================================================
// File Name: axi_ddr_model.v
// Design:    AXI4 DDR Behavioral Model
// Author:    Antigravity
// Description:
//   An AXI4 slave that simulates DDR memory with high latency, 
//   random backpressure, and periodic refresh stalls.
// =============================================================================

module axi_ddr_model #(
    parameter MEM_DEPTH_WORDS = 16384, // 64KB
    parameter READ_SLOTS = 2,
    parameter INJECT_RESP_ERROR = 1'b0,
    parameter [31:0] INJECT_RESP_ERROR_ADDR = 32'h0000_8000,
    parameter INJECT_RESP_ERROR_TWO = 1'b0,
    parameter [31:0] INJECT_RESP_ERROR_ADDR2 = 32'h0000_9000,
    parameter INJECT_WRITE_RESP_ERROR = 1'b0,
    parameter [31:0] INJECT_WRITE_RESP_ERROR_ADDR = 32'h0000_2080,
    // The legacy model indexes the low SRAM address bits. Linux boot uses a
    // physical DDR window and needs a distinct address-relative index path.
    parameter ADDRESS_BASED_INDEX = 1'b0,
    parameter [31:0] BASE_ADDR = 32'h0800_0000,
    parameter FAST_MODE = 1'b0
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

    function [31:0] mem_word_index;
        input [31:0] addr;
        begin
            if (ADDRESS_BASED_INDEX)
                mem_word_index = ((addr - BASE_ADDR) >> 2) % MEM_DEPTH_WORDS;
            else
                mem_word_index = addr[15:2];
        end
    endfunction
    reg error_injected;
    reg error_injected2;
    reg write_error_injected;

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
            load_hex(firmware_hex);
        end else begin
            // A missing image is intentional for unit tests that exercise
            // reset, bus errors, or an independent Boot ROM. Do not probe a
            // default path here: VCS warns even for a failed $fopen.
            $display("axi_ddr_model: no firmware image supplied; retaining zero init");
        end
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
    wire rand_backpressure = FAST_MODE ? 1'b0 : (lfsr[1:0] == 2'd0);
    // Periodically simulate DDR Refresh (5% chance, takes 10-20 cycles)
    reg [7:0] refresh_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_counter <= 8'd0;
        end else begin
            if (refresh_counter > 0)
                refresh_counter <= refresh_counter - 1'b1;
            else if (!FAST_MODE && lfsr[11:6] == 6'd0) // Low probability
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
    // Read Logic: two independently delayed AXI read slots.  Responses are
    // arbitrated in slot order, while the AXI ID preserves MSHR ownership.
    // =========================================================================
    localparam R_IDLE = 2'd0, R_WAIT = 2'd1, R_BURST = 2'd2;
    reg [1:0] rd_state [0:READ_SLOTS-1];
    reg [31:0] rd_addr [0:READ_SLOTS-1];
    reg [7:0] rd_len [0:READ_SLOTS-1];
    reg [3:0] rd_id [0:READ_SLOTS-1];
    reg [7:0] rd_wait [0:READ_SLOTS-1];
    reg [1:0] rd_resp [0:READ_SLOTS-1];
    integer rd_free, rd_out, ri;

    always @(*) begin
        rd_free = -1;
        for (ri = 0; ri < READ_SLOTS; ri = ri + 1)
            if (rd_state[ri] == R_IDLE && rd_free < 0) rd_free = ri;
        rd_out = -1;
        for (ri = 0; ri < READ_SLOTS; ri = ri + 1)
            if (rd_state[ri] == R_BURST && rd_out < 0) rd_out = ri;
        int_arready = (rd_free >= 0);
        s_rvalid = (rd_out >= 0);
        s_rlast = (rd_out >= 0) && (rd_len[rd_out] == 0);
        s_rdata = (rd_out >= 0) ? ram[mem_word_index(rd_addr[rd_out])] : 32'd0;
        s_rid = (rd_out >= 0) ? rd_id[rd_out] : 4'd0;
        s_rresp = (rd_out >= 0) ? rd_resp[rd_out] : 2'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_injected <= 1'b0; error_injected2 <= 1'b0;
            write_error_injected <= 1'b0;
            for (ri = 0; ri < READ_SLOTS; ri = ri + 1) begin
                rd_state[ri] <= R_IDLE; rd_addr[ri] <= 0; rd_len[ri] <= 0;
                rd_id[ri] <= 0; rd_wait[ri] <= 0; rd_resp[ri] <= 0;
            end
        end else begin
            if (s_arvalid && s_arready && rd_free >= 0) begin
                rd_state[rd_free] <= R_WAIT;
                rd_addr[rd_free] <= s_araddr;
                rd_len[rd_free] <= s_arlen;
                rd_id[rd_free] <= s_arid;
                // Distinct slots intentionally get distinct latency so the
                // second accepted read can complete before the first.
                rd_wait[rd_free] <= {3'd0, lfsr[12:8]} + 8'd5 +
                                    (s_arid[0] ? 8'd0 : 8'd3);
                if (INJECT_RESP_ERROR && !error_injected &&
                    (s_araddr[31:5] == INJECT_RESP_ERROR_ADDR[31:5])) begin
                    rd_resp[rd_free] <= 2'b10; error_injected <= 1'b1;
                    $display("axi_ddr_model: injected SLVERR addr=%08h id=%0h len=%0d", s_araddr, s_arid, s_arlen);
                end else if (INJECT_RESP_ERROR && INJECT_RESP_ERROR_TWO &&
                             !error_injected2 &&
                             (s_araddr[31:5] == INJECT_RESP_ERROR_ADDR2[31:5])) begin
                    rd_resp[rd_free] <= 2'b10; error_injected2 <= 1'b1;
                    $display("axi_ddr_model: injected SLVERR addr=%08h id=%0h len=%0d slot=2", s_araddr, s_arid, s_arlen);
                end else rd_resp[rd_free] <= 2'b00;
            end
            for (ri = 0; ri < READ_SLOTS; ri = ri + 1) begin
                if (rd_state[ri] == R_WAIT && !ddr_busy) begin
                    if (rd_wait[ri] != 0) rd_wait[ri] <= rd_wait[ri] - 1'b1;
                    else rd_state[ri] <= R_BURST;
                end
            end
            if (s_rvalid && s_rready && rd_out >= 0) begin
                if (rd_len[rd_out] == 0) rd_state[rd_out] <= R_IDLE;
                else begin
                    rd_addr[rd_out] <= rd_addr[rd_out] + 4;
                    rd_len[rd_out] <= rd_len[rd_out] - 1'b1;
                end
            end
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
                w_wait_cycles <= FAST_MODE ? 8'd0 : lfsr[8:5] + 8'd2; // 2 to 17 cycles before WREADY
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
                        if (INJECT_WRITE_RESP_ERROR && !write_error_injected &&
                            (w_addr[31:5] == INJECT_WRITE_RESP_ERROR_ADDR[31:5])) begin
                            write_error_injected <= 1'b1;
                            $display("axi_ddr_model: injected write SLVERR addr=%08h id=%0h", w_addr, w_id);
                        end else begin
                            if (s_wstrb[0]) ram[mem_word_index(w_addr)][7:0]   <= s_wdata[7:0];
                            if (s_wstrb[1]) ram[mem_word_index(w_addr)][15:8]  <= s_wdata[15:8];
                            if (s_wstrb[2]) ram[mem_word_index(w_addr)][23:16] <= s_wdata[23:16];
                            if (s_wstrb[3]) ram[mem_word_index(w_addr)][31:24] <= s_wdata[31:24];
                        end

                        if (s_wlast) begin
                            int_wready <= 1'b0;
                            s_bvalid   <= 1'b1;
                            s_bresp    <= (INJECT_WRITE_RESP_ERROR &&
                                           !write_error_injected &&
                                           (w_addr[31:5] == INJECT_WRITE_RESP_ERROR_ADDR[31:5])) ?
                                           2'b10 : 2'b00;
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
