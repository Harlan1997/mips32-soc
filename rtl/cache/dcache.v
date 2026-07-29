// =============================================================================
// File Name: dcache.v
// Design:    L1 Data Cache
// Author:    Antigravity
// Description:
//   8KB 4-way set-associative D-Cache.
//   Line size: 32 bytes (8 words). 64 sets.
//   Write-back, write-allocate. Tree pseudo-LRU (PLRU) replacement.
//   AXI4 Master interface. Single-outstanding blocking miss handling.
//   VIPT non-aliasing: index [10:5] lies within the 4KB page offset.
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
    // 8KB, 4 ways => 2KB per way. 32B/line => 64 lines (sets) per way.
    // Offset: [4:0] (5 bits)   Index: [10:5] (6 bits)   Tag: [31:11] (21 bits)
    localparam WAYS     = 4;
    localparam SETS     = 64;
    localparam TAG_BITS = 21;

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

    wire [5:0]  lookup_index = req_buf_valid ? req_buf_addr[10:5] : cpu_addr[10:5];
    wire [20:0] lookup_tag   = req_buf_addr[31:11];
    wire [2:0]  lookup_word  = req_buf_addr[4:2];

    assign uncacheable = (req_buf_valid ? (req_buf_addr[31:28] == 4'h4 || req_buf_addr[31:28] == 4'hA)
                                        : (cpu_addr[31:28] == 4'h4 || cpu_addr[31:28] == 4'hA));

    // SRAM arrays (4-way). tag entry = {valid[22], dirty[21], tag[20:0]}
    reg [TAG_BITS+1:0] tag_ram  [0:WAYS-1][0:SETS-1];
    reg [255:0]        data_ram [0:WAYS-1][0:SETS-1];
    reg [2:0]          plru_ram [0:SETS-1];   // tree-PLRU: b0=top, b1=left, b2=right

    // Registered read-out of the indexed set
    reg [TAG_BITS+1:0] tag_rdata  [0:WAYS-1];
    reg [255:0]        data_rdata [0:WAYS-1];
    reg [2:0]          plru_rdata;

    // Hit detection across 4 ways
    integer wi;
    reg [WAYS-1:0] way_hit;
    reg [WAYS-1:0] way_valid;
    always @(*) begin
        for (wi=0; wi<WAYS; wi=wi+1) begin
            way_valid[wi] = tag_rdata[wi][TAG_BITS+1];
            way_hit[wi]   = tag_rdata[wi][TAG_BITS+1] &&
                            (tag_rdata[wi][TAG_BITS-1:0] == lookup_tag);
        end
    end
    wire cache_hit = |way_hit;
    reg [1:0] hit_way;
    always @(*) begin
        hit_way = 2'd0;
        for (wi=0; wi<WAYS; wi=wi+1) if (way_hit[wi]) hit_way = wi[1:0];
    end

    // Victim selection: prefer an invalid way, else tree-PLRU.
    // Tree bits: b0 top (0=>left pair {0,1}, 1=>right pair {2,3}),
    //            b1 left pair (0=>way0, 1=>way1), b2 right pair (0=>way2,1=>way3).
    function [1:0] plru_victim;
        input [2:0] p;
        begin
            if (p[0]==1'b0) plru_victim = (p[1]==1'b0) ? 2'd0 : 2'd1;
            else            plru_victim = (p[2]==1'b0) ? 2'd2 : 2'd3;
        end
    endfunction

    reg [1:0] victim_way;
    always @(*) begin
        if      (!way_valid[0]) victim_way = 2'd0;
        else if (!way_valid[1]) victim_way = 2'd1;
        else if (!way_valid[2]) victim_way = 2'd2;
        else if (!way_valid[3]) victim_way = 2'd3;
        else                    victim_way = plru_victim(plru_rdata);
    end

    wire [TAG_BITS+1:0] victim_tag_entry = tag_rdata[victim_way];
    wire victim_dirty = victim_tag_entry[TAG_BITS+1] && victim_tag_entry[TAG_BITS];

    // PLRU update: mark accessed way as most-recently-used (point bits away).
    function [2:0] plru_touch;
        input [2:0] p;
        input [1:0] w;
        reg   [2:0] n;
        begin
            n = p;
            case (w)
                2'd0: begin n[0]=1'b1; n[1]=1'b1; end
                2'd1: begin n[0]=1'b1; n[1]=1'b0; end
                2'd2: begin n[0]=1'b0; n[2]=1'b1; end
                2'd3: begin n[0]=1'b0; n[2]=1'b0; end
            endcase
            plru_touch = n;
        end
    endfunction

    // Internal buffers for refill and writeback
    reg [255:0] line_buf;
    reg [2:0]   word_cnt;

    wire sram_read_en = (state == IDLE && cpu_req && !uncacheable) ||
                        (state == COMPARE && cache_hit && cpu_req && cpu_addr_ok && !uncacheable);

    // CPU handshakes
    assign cpu_addr_ok = (state == IDLE) || (state == COMPARE && cache_hit && !uncacheable);
    assign cpu_data_ok = (state == COMPARE && cache_hit && !uncacheable) ||
                         (state == UC_WRESP && bvalid) || (state == UC_RDATA && rvalid);

    integer ri;
    always @(posedge clk) begin
        if (sram_read_en) begin
            for (ri=0; ri<WAYS; ri=ri+1) begin
                tag_rdata[ri]  <= tag_ram[ri][cpu_addr[10:5]];
                data_rdata[ri] <= data_ram[ri][cpu_addr[10:5]];
            end
            plru_rdata <= plru_ram[cpu_addr[10:5]];
        end
    end

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) next_state = uncacheable ? UC_REQ : COMPARE;
            end
            COMPARE: begin
                if (cache_hit) next_state = IDLE;
                else next_state = victim_dirty ? WRITEBACK_REQ : REFILL_REQ;
            end
            WRITEBACK_REQ:  if (awready && awvalid) next_state = WRITEBACK_DATA;
            WRITEBACK_DATA: if (wready && wvalid && wlast) next_state = WRITEBACK_RESP;
            WRITEBACK_RESP: if (bready && bvalid) next_state = REFILL_REQ;
            REFILL_REQ:     if (arready && arvalid) next_state = REFILL_DATA;
            REFILL_DATA:    if (rvalid && rlast) next_state = WRITE_MERGE;
            WRITE_MERGE:    next_state = IDLE;
            UC_REQ:         next_state = req_buf_we ? UC_WDATA : UC_RDATA;
            UC_WDATA:       if ((!awvalid || awready) && (!wvalid || wready)) next_state = UC_WRESP;
            UC_WRESP:       if (bready && bvalid) next_state = IDLE;
            UC_RDATA:       if (rready && rvalid) next_state = IDLE;
        endcase
    end

    // Line merge for writes: target line = hit way's line (hit) or refilled buf (miss)
    wire [255:0] target_line = cache_hit ? data_rdata[hit_way] : line_buf;
    wire [31:0] orig_word = target_line[lookup_word*32 +: 32];
    wire [31:0] merged_word;
    assign merged_word[7:0]   = req_buf_be[0] ? req_buf_wdata[7:0]   : orig_word[7:0];
    assign merged_word[15:8]  = req_buf_be[1] ? req_buf_wdata[15:8]  : orig_word[15:8];
    assign merged_word[23:16] = req_buf_be[2] ? req_buf_wdata[23:16] : orig_word[23:16];
    assign merged_word[31:24] = req_buf_be[3] ? req_buf_wdata[31:24] : orig_word[31:24];

    reg [255:0] new_line;
    integer nw;
    always @(*) begin
        new_line = target_line;
        if (req_buf_we) new_line[lookup_word*32 +: 32] = merged_word;
    end

    // CPU Read Data
    always @(*) begin
        cpu_rdata = orig_word;
        if (state == UC_RDATA) cpu_rdata = rdata;
    end

    // Main Control and SRAM Writes
    integer si, sw;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_buf_valid <= 1'b0; req_buf_we <= 1'b0;
            req_buf_addr <= 32'd0; req_buf_wdata <= 32'd0; req_buf_be <= 4'd0;
            awvalid <= 1'b0; awaddr <= 32'd0;
            wvalid <= 1'b0; wlast <= 1'b0; wdata <= 32'd0; wstrb <= 4'hF;
            bready <= 1'b0; arvalid <= 1'b0; araddr <= 32'd0; rready <= 1'b0;
            word_cnt <= 3'd0; line_buf <= 256'd0;
            for (si=0; si<SETS; si=si+1) begin
                plru_ram[si] <= 3'd0;
                for (sw=0; sw<WAYS; sw=sw+1) tag_ram[sw][si] <= {(TAG_BITS+2){1'b0}};
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        req_buf_valid <= 1'b1; req_buf_we <= cpu_we;
                        req_buf_addr  <= cpu_addr; req_buf_wdata <= cpu_wdata;
                        req_buf_be    <= cpu_be;
                    end
                end

                UC_REQ: begin
                    if (req_buf_we) begin
                        awvalid <= 1'b1; awaddr <= req_buf_addr;
                        wvalid  <= 1'b1; wstrb <= req_buf_be; wdata <= req_buf_wdata; wlast <= 1'b1;
                    end else begin
                        arvalid <= 1'b1; araddr <= req_buf_addr;
                    end
                end
                UC_WDATA: begin
                    if (awready && awvalid) awvalid <= 1'b0;
                    if (wready && wvalid) begin wvalid <= 1'b0; wlast <= 1'b0; end
                    if ((!awvalid || awready) && (!wvalid || wready)) bready <= 1'b1;
                end
                UC_WRESP: begin
                    if (bready && bvalid) begin bready <= 1'b0; req_buf_valid <= 1'b0; end
                end
                UC_RDATA: begin
                    if (rready && rvalid) begin rready <= 1'b0; req_buf_valid <= 1'b0; end
                    else if (arready && arvalid) begin arvalid <= 1'b0; rready <= 1'b1; end
                end

                COMPARE: begin
                    if (cache_hit) begin
                        // Update PLRU: accessed (hit) way is MRU
                        plru_ram[lookup_index] <= plru_touch(plru_rdata, hit_way);
                        if (req_buf_we) begin
                            data_ram[hit_way][lookup_index] <= new_line;
                            tag_ram[hit_way][lookup_index]  <= {1'b1, 1'b1, lookup_tag};
                        end
                        req_buf_valid <= 1'b0;
                    end else begin
                        // Miss: launch writeback (dirty victim) or refill
                        if (victim_dirty) begin
                            awvalid <= 1'b1;
                            awaddr  <= {victim_tag_entry[TAG_BITS-1:0], req_buf_addr[10:5], 5'd0};
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
                        wvalid  <= 1'b1; wstrb <= 4'hF;
                        wdata   <= data_rdata[victim_way][31:0];
                        wlast   <= 1'b0;
                    end
                end
                WRITEBACK_DATA: begin
                    if (wready && wvalid) begin
                        if (wlast) begin
                            wvalid <= 1'b0; wlast <= 1'b0; bready <= 1'b1;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                            if (word_cnt == 3'd6) wlast <= 1'b1;
                            wdata <= data_rdata[victim_way][(word_cnt+1'b1)*32 +: 32];
                        end
                    end
                end
                WRITEBACK_RESP: begin
                    if (bready && bvalid) begin
                        bready <= 1'b0;
                        arvalid <= 1'b1; araddr <= {req_buf_addr[31:5], 5'd0}; word_cnt <= 3'd0;
                    end
                end

                REFILL_REQ: begin
                    if (arready && arvalid) begin arvalid <= 1'b0; rready <= 1'b1; end
                end
                REFILL_DATA: begin
                    if (rready && rvalid) begin
                        line_buf[word_cnt*32 +: 32] <= rdata;
                        word_cnt <= word_cnt + 1'b1;
                        if (rlast) rready <= 1'b0;
                    end
                end
                WRITE_MERGE: begin
                    // Install refilled (optionally write-merged) line into victim way
                    data_ram[victim_way][lookup_index] <= new_line;
                    tag_ram[victim_way][lookup_index]  <= {1'b1, req_buf_we, lookup_tag};
                    // Accessed way becomes MRU
                    plru_ram[lookup_index] <= plru_touch(plru_rdata, victim_way);
                    req_buf_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
