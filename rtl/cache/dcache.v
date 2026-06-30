// =============================================================================
// File Name: dcache.v
// Design:    L1 Data Cache
// Author:    Antigravity
// Description:
//   8KB 2-way set-associative D-Cache.
//   Line size: 32 bytes (8 words).
//   Write-back, write-allocate.
//   LRU replacement.
//   AXI4 Master interface.
// =============================================================================

module dcache (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Data Memory Interface
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_be,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_addr_ok,
    output wire        cpu_data_ok,

    // AXI4 Master Interface
    // AW Channel
    output wire [3:0]  awid,
    output reg  [31:0] awaddr,
    output wire [7:0]  awlen,
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,
    output wire [1:0]  awlock,
    output wire [3:0]  awcache,
    output wire [2:0]  awprot,
    output reg         awvalid,
    input  wire        awready,
    // W Channel
    output reg  [31:0] wdata,
    output reg  [3:0]  wstrb,
    output reg         wlast,
    output reg         wvalid,
    input  wire        wready,
    // B Channel
    input  wire [3:0]  bid,
    input  wire [1:0]  bresp,
    input  wire        bvalid,
    output reg         bready,
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

    wire uncacheable;

    // Fixed AXI configuration for cache line (8 words)
    assign awid    = 4'd0;
    assign awlen   = uncacheable ? 8'd0 : 8'd7;
    assign awsize  = 3'b010; // 4 bytes
    assign awburst = 2'b01;  // INCR
    assign awlock  = 2'd0;
    assign awcache = uncacheable ? 4'b0000 : 4'b0010;
    assign awprot  = 3'b000;

    assign arid    = 4'd0;
    assign arlen   = uncacheable ? 8'd0 : 8'd7;
    assign arsize  = 3'b010; // 4 bytes
    assign arburst = 2'b01;  // INCR
    assign arlock  = 2'd0;
    assign arcache = uncacheable ? 4'b0000 : 4'b0010;
    assign arprot  = 3'b000;

    // Cache parameters
    // 8KB, 2 ways => 4KB per way.
    // 32B/line => 128 lines per way.
    // Offset: [4:0] (5 bits)
    // Index:  [11:5] (7 bits)
    // Tag:    [31:12] (20 bits)

    // State Machine
    localparam IDLE           = 4'd0;
    localparam COMPARE        = 4'd1;
    localparam WRITEBACK_REQ  = 4'd2;
    localparam WRITEBACK_DATA = 4'd3;
    localparam WRITEBACK_RESP = 4'd4;
    localparam REFILL_REQ     = 4'd5;
    localparam REFILL_DATA    = 4'd6;
    localparam WRITE_MERGE    = 4'd7;
    localparam UC_REQ         = 4'd8;
    localparam UC_WDATA       = 4'd9;
    localparam UC_WRESP       = 4'd10;
    localparam UC_RDATA       = 4'd11;

    reg [3:0] state, next_state;

    // CPU request buffer
    reg        req_buf_valid;
    reg        req_buf_we;
    reg [31:0] req_buf_addr;
    reg [31:0] req_buf_wdata;
    reg [3:0]  req_buf_be;

    wire [6:0]  lookup_index = req_buf_valid ? req_buf_addr[11:5] : cpu_addr[11:5];
    wire [19:0] lookup_tag   = req_buf_addr[31:12];
    wire [2:0]  lookup_word  = req_buf_addr[4:2];
    
    assign uncacheable = (req_buf_valid ? (req_buf_addr[31:28] == 4'h4 || req_buf_addr[31:28] == 4'hA) : (cpu_addr[31:28] == 4'h4 || cpu_addr[31:28] == 4'hA));

    // SRAM arrays
    reg [21:0]  tag_ram_0 [0:127]; // [21]: valid, [20]: dirty, [19:0]: tag
    reg [21:0]  tag_ram_1 [0:127];
    reg [255:0] data_ram_0 [0:127];
    reg [255:0] data_ram_1 [0:127];
    reg         lru_ram [0:127]; // 0: way 0 is LRU, 1: way 1 is LRU

    reg [21:0]  tag_rdata_0, tag_rdata_1;
    reg [255:0] data_rdata_0, data_rdata_1;
    reg         lru_rdata;

    // Hit detection
    wire hit_0 = tag_rdata_0[21] && (tag_rdata_0[19:0] == lookup_tag);
    wire hit_1 = tag_rdata_1[21] && (tag_rdata_1[19:0] == lookup_tag);
    wire cache_hit = hit_0 || hit_1;
    
    // Victim selection
    wire victim_way = lru_rdata;
    wire [21:0] victim_tag = victim_way ? tag_rdata_1 : tag_rdata_0;
    wire victim_dirty = victim_tag[21] && victim_tag[20];

    // Internal buffers for refill and writeback
    reg [255:0] line_buf;
    reg [2:0]   word_cnt;

    wire sram_read_en = (state == IDLE && cpu_req && !uncacheable) || (state == COMPARE && cache_hit && cpu_req && cpu_addr_ok && !uncacheable);
    wire [6:0] sram_addr = sram_read_en ? cpu_addr[11:5] : req_buf_addr[11:5];
    
    wire sram_write_en = (state == COMPARE && cache_hit && req_buf_we && !uncacheable) || (state == REFILL_DATA && rvalid && rlast) || (state == WRITE_MERGE);

    // CPU handshakes
    assign cpu_addr_ok = (state == IDLE) || (state == COMPARE && cache_hit && !uncacheable);
    assign cpu_data_ok = (state == COMPARE && cache_hit && !uncacheable) || (state == UC_WRESP && bvalid) || (state == UC_RDATA && rvalid);

    always @(posedge clk) begin
        if (sram_read_en) begin
            tag_rdata_0  <= tag_ram_0[sram_addr];
            tag_rdata_1  <= tag_ram_1[sram_addr];
            data_rdata_0 <= data_ram_0[sram_addr];
            data_rdata_1 <= data_ram_1[sram_addr];
            lru_rdata    <= lru_ram[sram_addr];
        end else if (state == REFILL_DATA || state == WRITEBACK_DATA) begin
            // Hold the read data so victim data doesn't change
            // Actually they don't change unless we write
        end
    end

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (uncacheable) next_state = UC_REQ;
                    else next_state = COMPARE;
                end
            end
            COMPARE: begin
                if (cache_hit) begin
                    next_state = IDLE;
                end else begin
                    if (victim_dirty) next_state = WRITEBACK_REQ;
                    else next_state = REFILL_REQ;
                end
            end
            WRITEBACK_REQ: begin
                if (awready && awvalid) next_state = WRITEBACK_DATA;
            end
            WRITEBACK_DATA: begin
                if (wready && wvalid && wlast) next_state = WRITEBACK_RESP;
            end
            WRITEBACK_RESP: begin
                if (bready && bvalid) next_state = REFILL_REQ;
            end
            REFILL_REQ: begin
                if (arready && arvalid) next_state = REFILL_DATA;
            end
            REFILL_DATA: begin
                if (rvalid && rlast) next_state = WRITE_MERGE;
            end
            WRITE_MERGE: begin
                next_state = IDLE;
            end
            UC_REQ: begin
                if (req_buf_we) next_state = UC_WDATA;
                else next_state = UC_RDATA;
            end
            UC_WDATA: begin
                if ((!awvalid || awready) && (!wvalid || wready)) next_state = UC_WRESP;
            end
            UC_WRESP: begin
                if (bready && bvalid) next_state = IDLE;
            end
            UC_RDATA: begin
                if (rready && rvalid) next_state = IDLE;
            end
        endcase
    end

    // Line merge for writes
    wire [255:0] target_line = cache_hit ? (hit_0 ? data_rdata_0 : data_rdata_1) : line_buf;
    
    // Mux out the correct 32-bit word from the target line
    wire [31:0] orig_word = (lookup_word == 3'd0) ? target_line[31:0] :
                            (lookup_word == 3'd1) ? target_line[63:32] :
                            (lookup_word == 3'd2) ? target_line[95:64] :
                            (lookup_word == 3'd3) ? target_line[127:96] :
                            (lookup_word == 3'd4) ? target_line[159:128] :
                            (lookup_word == 3'd5) ? target_line[191:160] :
                            (lookup_word == 3'd6) ? target_line[223:192] :
                                                    target_line[255:224];
                                                    
    // Merge new word based on byte enables
    wire [31:0] merged_word;
    assign merged_word[7:0]   = req_buf_be[0] ? req_buf_wdata[7:0]   : orig_word[7:0];
    assign merged_word[15:8]  = req_buf_be[1] ? req_buf_wdata[15:8]  : orig_word[15:8];
    assign merged_word[23:16] = req_buf_be[2] ? req_buf_wdata[23:16] : orig_word[23:16];
    assign merged_word[31:24] = req_buf_be[3] ? req_buf_wdata[31:24] : orig_word[31:24];

    wire [255:0] new_line;
    assign new_line[31:0]    = (lookup_word == 3'd0 && req_buf_we) ? merged_word : target_line[31:0];
    assign new_line[63:32]   = (lookup_word == 3'd1 && req_buf_we) ? merged_word : target_line[63:32];
    assign new_line[95:64]   = (lookup_word == 3'd2 && req_buf_we) ? merged_word : target_line[95:64];
    assign new_line[127:96]  = (lookup_word == 3'd3 && req_buf_we) ? merged_word : target_line[127:96];
    assign new_line[159:128] = (lookup_word == 3'd4 && req_buf_we) ? merged_word : target_line[159:128];
    assign new_line[191:160] = (lookup_word == 3'd5 && req_buf_we) ? merged_word : target_line[191:160];
    assign new_line[223:192] = (lookup_word == 3'd6 && req_buf_we) ? merged_word : target_line[223:192];
    assign new_line[255:224] = (lookup_word == 3'd7 && req_buf_we) ? merged_word : target_line[255:224];

    // CPU Read Data
    always @(*) begin
        cpu_rdata = orig_word; 
        if (state == UC_RDATA) cpu_rdata = rdata;
    end

    // Main Control and SRAM Writes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            state <= IDLE;
            // VCS coverage on
            req_buf_valid <= 1'b0;
            req_buf_we <= 1'b0;
            req_buf_addr <= 32'd0;
            req_buf_wdata <= 32'd0;
            req_buf_be <= 4'd0;
            
            awvalid <= 1'b0;
            awaddr <= 32'd0;
            wvalid <= 1'b0;
            wlast <= 1'b0;
            wdata <= 32'd0;
            wstrb <= 4'hF;
            bready <= 1'b0;
            
            arvalid <= 1'b0;
            araddr <= 32'd0;
            rready <= 1'b0;
            
            word_cnt <= 3'd0;
            line_buf <= 256'd0;
            
            for (int i = 0; i < 128; i = i + 1) begin
                tag_ram_0[i] <= 22'd0;
                tag_ram_1[i] <= 22'd0;
                lru_ram[i]   <= 1'b0;
            end
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        req_buf_valid <= 1'b1;
                        req_buf_we    <= cpu_we;
                        req_buf_addr  <= cpu_addr;
                        req_buf_wdata <= cpu_wdata;
                        req_buf_be    <= cpu_be;
                    end
                end
                
                UC_REQ: begin
                    if (req_buf_we) begin
                        awvalid <= 1'b1;
                        awaddr  <= req_buf_addr;
                        wvalid  <= 1'b1;
                        wstrb   <= req_buf_be;
                        wdata   <= req_buf_wdata;
                        wlast   <= 1'b1;
                    end else begin
                        arvalid <= 1'b1;
                        araddr  <= req_buf_addr;
                    end
                end
                
                UC_WDATA: begin
                    if (awready && awvalid) begin
                        awvalid <= 1'b0;
                    end
                    if (wready && wvalid) begin
                        wvalid <= 1'b0;
                        wlast  <= 1'b0;
                    end
                    if ((!awvalid || awready) && (!wvalid || wready)) begin
                        // Both accepted, wait for response
                        bready <= 1'b1;
                        $display("[%t] DCACHE: Asserting BREADY. awvalid=%b, awready=%b, wvalid=%b, wready=%b", $time, awvalid, awready, wvalid, wready);
                    end
                end
                
                UC_WRESP: begin
                    if (bready && bvalid) begin
                        bready <= 1'b0;
                        req_buf_valid <= 1'b0;
                    end
                end
                
                UC_RDATA: begin
                    if (rready && rvalid) begin
                        rready <= 1'b0;
                        req_buf_valid <= 1'b0;
                    end else if (arready && arvalid) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                    end
                end
                
                COMPARE: begin
                    if (cache_hit) begin
                        // Update LRU
                        lru_ram[lookup_index] <= hit_0 ? 1'b1 : 1'b0;
                        
                        // Handle Write Hit
                        if (req_buf_we) begin
                            if (hit_0) begin
                                data_ram_0[lookup_index] <= new_line;
                                tag_ram_0[lookup_index]  <= {1'b1, 1'b1, lookup_tag}; // Valid, Dirty, Tag
                            end else begin
                                data_ram_1[lookup_index] <= new_line;
                                tag_ram_1[lookup_index]  <= {1'b1, 1'b1, lookup_tag};
                            end
                        end
                        
                        // Request is satisfied, return to IDLE
                        req_buf_valid <= 1'b0;
                    end else begin
                        // Miss
                        if (victim_dirty) begin
                            awvalid <= 1'b1;
                            awaddr  <= {victim_tag[19:0], req_buf_addr[11:5], 5'd0};
                            word_cnt <= 3'd0;
                        end else begin
                            arvalid <= 1'b1;
                            araddr  <= {req_buf_addr[31:5], 5'd0};
                            word_cnt <= 3'd0;
                        end
                    end
                end
                
                WRITEBACK_REQ: begin
                    if (awready && awvalid) begin
                        awvalid <= 1'b0;
                        wvalid  <= 1'b1;
                        wstrb   <= 4'hF;
                        
                        // First data word
                        wdata <= victim_way ? data_rdata_1[31:0] : data_rdata_0[31:0];
                        wlast <= 1'b0;
                    end
                end
                
                WRITEBACK_DATA: begin
                    if (wready && wvalid) begin
                        if (wlast) begin
                            wvalid <= 1'b0;
                            wlast  <= 1'b0;
                            bready <= 1'b1;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                            if (word_cnt == 3'd6) wlast <= 1'b1; // next is last
                            
                            // Load next word
                            case (word_cnt + 1'b1)
                                3'd1: wdata <= victim_way ? data_rdata_1[63:32]   : data_rdata_0[63:32];
                                3'd2: wdata <= victim_way ? data_rdata_1[95:64]   : data_rdata_0[95:64];
                                3'd3: wdata <= victim_way ? data_rdata_1[127:96]  : data_rdata_0[127:96];
                                3'd4: wdata <= victim_way ? data_rdata_1[159:128] : data_rdata_0[159:128];
                                3'd5: wdata <= victim_way ? data_rdata_1[191:160] : data_rdata_0[191:160];
                                3'd6: wdata <= victim_way ? data_rdata_1[223:192] : data_rdata_0[223:192];
                                3'd7: wdata <= victim_way ? data_rdata_1[255:224] : data_rdata_0[255:224];
                            endcase
                        end
                    end
                end
                
                WRITEBACK_RESP: begin
                    if (bready && bvalid) begin
                        bready <= 1'b0;
                        arvalid <= 1'b1;
                        araddr  <= {req_buf_addr[31:5], 5'd0};
                        word_cnt <= 3'd0;
                    end
                end
                
                REFILL_REQ: begin
                    if (arready && arvalid) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                    end
                end
                
                REFILL_DATA: begin
                    if (rready && rvalid) begin
                        case (word_cnt)
                            3'd0: line_buf[31:0]    <= rdata;
                            3'd1: line_buf[63:32]   <= rdata;
                            3'd2: line_buf[95:64]   <= rdata;
                            3'd3: line_buf[127:96]  <= rdata;
                            3'd4: line_buf[159:128] <= rdata;
                            3'd5: line_buf[191:160] <= rdata;
                            3'd6: line_buf[223:192] <= rdata;
                            3'd7: line_buf[255:224] <= rdata;
                        endcase
                        word_cnt <= word_cnt + 1'b1;
                        
                        if (rlast) begin
                            rready <= 1'b0;
                        end
                    end
                end
                
                WRITE_MERGE: begin
                    // Write the filled (and optionally merged) line into the cache way
                    if (!victim_way) begin
                        data_ram_0[lookup_index] <= new_line;
                        tag_ram_0[lookup_index]  <= {1'b1, req_buf_we, lookup_tag}; // dirty if we wrote
                    end else begin
                        data_ram_1[lookup_index] <= new_line;
                        tag_ram_1[lookup_index]  <= {1'b1, req_buf_we, lookup_tag};
                    end
                    // Update LRU
                    lru_ram[lookup_index] <= !victim_way;
                    
                    req_buf_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
