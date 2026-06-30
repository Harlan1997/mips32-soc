// =============================================================================
// File Name: icache.v
// Design:    L1 Instruction Cache
// Author:    Antigravity
// Description:
//   8KB Direct-mapped I-Cache.
//   Line size: 32 bytes (8 words).
//   Physical addressing.
//   AXI4 Master interface (Read-only).
// =============================================================================

module icache (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Instruction Fetch Interface
    input  wire        cpu_req,
    input  wire [31:0] cpu_addr,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_addr_ok,
    output wire        cpu_data_ok,

    // AXI4 Master Interface (AR and R channels)
    // AR Channel
    output wire [3:0]  arid,
    output reg  [31:0] araddr,
    output wire [7:0]  arlen,
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,
    output wire [1:0]  arlock,
    output wire [3:0]  arcache,
    output wire [2:0]  arprot,
    output reg         arvalid,
    input  wire        arready,
    // R Channel
    input  wire [3:0]  rid,
    input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output reg         rready
);

    // Fixed AXI AR signals for cache line refill
    assign arid    = 4'd0;
    assign arlen   = 8'd7;     // 8 transfers of 4 bytes
    assign arsize  = 3'b010;   // 4 bytes per transfer
    assign arburst = 2'b01;    // INCR
    assign arlock  = 2'd0;
    assign arcache = 4'b0010;  // Normal, non-cacheable (or cacheable if L2 exists)
    assign arprot  = 3'b100;   // Instruction access

    // Cache parameters
    // 8KB, 32B/line => 256 lines.
    // Offset: 5 bits [4:0] (Word offset: [4:2])
    // Index:  8 bits [12:5]
    // Tag:   19 bits [31:13]

    // State Machine
    localparam IDLE    = 3'd0;
    localparam LOOKUP  = 3'd1;
    localparam MISS    = 3'd2;
    localparam REFILL  = 3'd3;

    reg [2:0] state, next_state;

    // Request buffer
    reg        req_buf_valid;
    reg [31:0] req_buf_addr;
    
    wire [7:0]  lookup_index = req_buf_valid ? req_buf_addr[12:5] : cpu_addr[12:5];
    wire [18:0] lookup_tag   = req_buf_addr[31:13];
    wire [2:0]  lookup_word  = req_buf_addr[4:2];

    // SRAM arrays (Inference)
    reg [19:0]  tag_ram  [0:255]; // [19]: valid, [18:0]: tag
    reg [255:0] data_ram [0:255]; // 32 bytes per line

    // SRAM outputs
    reg [19:0]  tag_rdata;
    reg [255:0] data_rdata;

    // Refill buffer
    reg [255:0] refill_buf;
    reg [2:0]   refill_word_cnt;

    // Synchronous Read for SRAM
    wire sram_read_en = (state == IDLE && cpu_req) || (state == LOOKUP && cpu_req && cpu_addr_ok);
    wire sram_write_en = (state == REFILL && rvalid && rlast);
    
    wire [7:0] sram_addr = sram_write_en ? req_buf_addr[12:5] : (sram_read_en ? cpu_addr[12:5] : req_buf_addr[12:5]);

    always @(posedge clk) begin
        if (sram_read_en || sram_write_en) begin
            tag_rdata  <= tag_ram[sram_addr];
            data_rdata <= data_ram[sram_addr];
        end
    end

    // Hit detection
    wire cache_hit = tag_rdata[19] && (tag_rdata[18:0] == lookup_tag);

    // CPU interface logic
    assign cpu_addr_ok = (state == IDLE) || (state == LOOKUP && cache_hit);
    assign cpu_data_ok = (state == LOOKUP && cache_hit);

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) next_state = LOOKUP;
            end
            LOOKUP: begin
                if (cache_hit) begin
                    // VCS coverage off
                    if (!cpu_req) next_state = IDLE;
                    // VCS coverage on
                end else begin
                    next_state = MISS;
                end
            end
            MISS: begin
                if (arready && arvalid) next_state = REFILL;
            end
            REFILL: begin
                if (rvalid && rlast) next_state = IDLE;
            end
        endcase
    end

    // State Reg & Data Path
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            state <= IDLE;
            // VCS coverage on
            req_buf_valid <= 1'b0;
            req_buf_addr <= 32'd0;
            arvalid <= 1'b0;
            araddr <= 32'd0;
            rready <= 1'b0;
            refill_word_cnt <= 3'd0;
            refill_buf <= 256'd0;
            
            // Invalidate all tags
            for (int i = 0; i < 256; i = i + 1) begin
                tag_ram[i] <= 20'd0;
            end
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        req_buf_valid <= 1'b1;
                        req_buf_addr  <= cpu_addr;
                    end
                end
                
                LOOKUP: begin
                    if (cache_hit) begin
                        if (cpu_req) begin
                            req_buf_addr <= cpu_addr;
                        end else begin
                            req_buf_valid <= 1'b0;
                        end
                    end else begin
                        // Cache miss, prepare AXI read request
                        arvalid <= 1'b1;
                        // Align address to 32-byte boundary
                        araddr  <= {req_buf_addr[31:5], 5'd0}; 
                    end
                end
                
                MISS: begin
                    if (arready && arvalid) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                        refill_word_cnt <= 3'd0;
                    end
                end
                
                REFILL: begin
                    if (rvalid && rready) begin
                        // Shift/insert data into refill buffer
                        case (refill_word_cnt)
                            3'd0: refill_buf[31:0]    <= rdata;
                            3'd1: refill_buf[63:32]   <= rdata;
                            3'd2: refill_buf[95:64]   <= rdata;
                            3'd3: refill_buf[127:96]  <= rdata;
                            3'd4: refill_buf[159:128] <= rdata;
                            3'd5: refill_buf[191:160] <= rdata;
                            3'd6: refill_buf[223:192] <= rdata;
                            3'd7: refill_buf[255:224] <= rdata;
                        endcase
                        
                        refill_word_cnt <= refill_word_cnt + 1'b1;
                        
                        if (rlast) begin
                            rready <= 1'b0;
                        end
                    end
                end
            endcase
            
            // Special fix: on sram_write_en (which is rvalid && rlast),
            // refill_buf is being updated in the same cycle. So the data_ram update
            // in the SRAM block needs the final concatenated value.
            // Let's modify that logic in the SRAM write block instead.
        end
    end

    // Extract correct word for CPU data
    always @(*) begin
        cpu_rdata = 32'd0;
        if (state == LOOKUP && cache_hit) begin
            case (lookup_word)
                3'd0: cpu_rdata = data_rdata[31:0];
                3'd1: cpu_rdata = data_rdata[63:32];
                3'd2: cpu_rdata = data_rdata[95:64];
                3'd3: cpu_rdata = data_rdata[127:96];
                3'd4: cpu_rdata = data_rdata[159:128];
                3'd5: cpu_rdata = data_rdata[191:160];
                3'd6: cpu_rdata = data_rdata[223:192];
                3'd7: cpu_rdata = data_rdata[255:224];
            endcase
        end
    end

    // Overwrite the data_ram write logic from above to use the correct full line
    wire [255:0] full_refill_line;
    assign full_refill_line[31:0]    = (refill_word_cnt == 3'd0) ? rdata : refill_buf[31:0];
    assign full_refill_line[63:32]   = (refill_word_cnt == 3'd1) ? rdata : refill_buf[63:32];
    assign full_refill_line[95:64]   = (refill_word_cnt == 3'd2) ? rdata : refill_buf[95:64];
    assign full_refill_line[127:96]  = (refill_word_cnt == 3'd3) ? rdata : refill_buf[127:96];
    assign full_refill_line[159:128] = (refill_word_cnt == 3'd4) ? rdata : refill_buf[159:128];
    assign full_refill_line[191:160] = (refill_word_cnt == 3'd5) ? rdata : refill_buf[191:160];
    assign full_refill_line[223:192] = (refill_word_cnt == 3'd6) ? rdata : refill_buf[223:192];
    assign full_refill_line[255:224] = (refill_word_cnt == 3'd7) ? rdata : refill_buf[255:224];

    always @(posedge clk) begin
        if (sram_write_en) begin
            data_ram[sram_addr] <= full_refill_line;
            tag_ram[sram_addr]  <= {1'b1, req_buf_addr[31:13]};
        end
    end

    always @(posedge clk) begin
        if (arvalid || arready || rvalid || rready) begin
            $display("[%t] ICACHE READ: state=%d, arvalid=%b, arready=%b, araddr=%h, rvalid=%b, rready=%b, cpu_data_ok=%b",
                     $time, state, arvalid, arready, araddr, rvalid, rready, cpu_data_ok);
        end
    end
endmodule
