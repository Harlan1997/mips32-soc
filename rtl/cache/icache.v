// =============================================================================
// File Name: icache.v
// Design:    L1 Instruction Cache
// Author:    Antigravity
// Description:
//   8KB 4-way set-associative I-Cache.
//   Line size: 32 bytes (8 words). 64 sets.
//   Physical addressing. Tree pseudo-LRU (PLRU) replacement. Read-only.
//   AXI4 Master interface (AR and R channels). Single-outstanding blocking.
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
    output wire        cpu_bus_error,
    // All I-cache AXI failures are refill failures and use MIPS CacheErr.
    output wire        cpu_cache_error,

    // MIPS CACHE index tag maintenance. I-cache is read-only, so these
    // operations only inspect or replace the valid/tag tuple and never issue
    // AXI traffic. The request is held by the CPU MEM stage until done.
    input  wire        cache_op_valid,
    input  wire [4:0]  cache_op,
    input  wire [31:0] cache_op_addr,
    output wire        cache_op_ready,
    output wire        cache_op_done,
    output wire        cache_op_error,
    input  wire [31:0] cache_tag_wdata,
    output wire [31:0] cache_tag_rdata,

    // AXI4 Master Interface (AR and R channels)
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
    assign arcache = 4'b0010;
    assign arprot  = 3'b100;   // Instruction access

    // Cache parameters
    // 8KB, 4 ways => 2KB/way. 32B/line => 64 sets/way.
    // Offset [4:0]  Index [10:5] (6b)  Tag [31:11] (21b)
    localparam WAYS     = 4;
    localparam SETS     = 64;
    localparam TAG_BITS = 21;

    // State Machine
    localparam IDLE    = 3'd0;
    localparam LOOKUP  = 3'd1;
    localparam MISS    = 3'd2;
    localparam REFILL  = 3'd3;
    localparam ERROR   = 3'd4;
    localparam CACHE_LOOKUP = 3'd5;
    localparam CACHE_DONE   = 3'd6;

    reg [2:0] state, next_state;

    // Request buffer
    reg        req_buf_valid;
    reg [31:0] req_buf_addr;

    wire [5:0]  lookup_index = req_buf_valid ? req_buf_addr[10:5] : cpu_addr[10:5];
    wire [20:0] lookup_tag   = req_buf_addr[31:11];
    wire [2:0]  lookup_word  = req_buf_addr[4:2];

    // SRAM arrays (4-way). tag entry = {valid[21], tag[20:0]}
    reg [TAG_BITS:0] tag_ram  [0:WAYS-1][0:SETS-1];
    reg [255:0]      data_ram [0:WAYS-1][0:SETS-1];
    reg [2:0]        plru_ram [0:SETS-1];

    // Registered read-out of the indexed set
    reg [TAG_BITS:0] tag_rdata  [0:WAYS-1];
    reg [255:0]      data_rdata [0:WAYS-1];
    reg [2:0]        plru_rdata;

    // Refill buffer
    reg [255:0] refill_buf;
    reg [2:0]   refill_word_cnt;
    reg         refill_error;

    // Keep legacy direct icache unit benches source-compatible while the
    // maintenance ports are added: an omitted input is Z, never a request.
    wire        maint_req = (cache_op_valid === 1'b1);

    reg [31:0]  maint_addr;
    reg [4:0]   maint_op;
    reg [1:0]   maint_way;
    reg [31:0]  maint_tag_wdata;
    reg         maint_error;

    wire [5:0]  maint_index = maint_addr[10:5];
    wire [TAG_BITS:0] maint_tag_entry = tag_rdata[maint_way];
    wire              maint_load_tag = (maint_op == 5'b00100);
    wire              maint_store_tag = (maint_op == 5'b01000);

    // Synchronous read for SRAM (fan out across 4 ways)
    wire sram_read_en  = (state == IDLE && (cpu_req || maint_req)) ||
                         (state == LOOKUP && cpu_req && cpu_addr_ok);
    wire sram_write_en = (state == REFILL && rvalid && rlast &&
                          !(refill_error || (rresp != 2'b00)));
    wire [5:0] sram_addr = sram_write_en ? req_buf_addr[10:5] :
                           ((state == IDLE && maint_req) ? cache_op_addr[10:5] :
                            (sram_read_en ? cpu_addr[10:5] : req_buf_addr[10:5]));

    integer ri;
    always @(posedge clk) begin
        if (sram_read_en || sram_write_en) begin
            for (ri=0; ri<WAYS; ri=ri+1) begin
                tag_rdata[ri]  <= tag_ram[ri][sram_addr];
                data_rdata[ri] <= data_ram[ri][sram_addr];
            end
            plru_rdata <= plru_ram[sram_addr];
        end
    end

    // Hit detection across 4 ways
    integer wi;
    reg [WAYS-1:0] way_hit;
    reg [WAYS-1:0] way_valid;
    always @(*) begin
        for (wi=0; wi<WAYS; wi=wi+1) begin
            way_valid[wi] = tag_rdata[wi][TAG_BITS];
            way_hit[wi]   = tag_rdata[wi][TAG_BITS] && (tag_rdata[wi][TAG_BITS-1:0] == lookup_tag);
        end
    end
    wire cache_hit = |way_hit;
    reg [1:0] hit_way;
    always @(*) begin
        hit_way = 2'd0;
        for (wi=0; wi<WAYS; wi=wi+1) if (way_hit[wi]) hit_way = wi[1:0];
    end

    // Victim selection: prefer invalid way, else tree-PLRU
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

    // CPU interface logic
    assign cpu_addr_ok = (state == IDLE && !maint_req) ||
                         (state == LOOKUP && cache_hit);
    assign cpu_data_ok = (state == LOOKUP && cache_hit) || (state == ERROR);
    assign cpu_bus_error = (state == ERROR);
    assign cpu_cache_error = (state == ERROR);
    assign cache_op_ready = (state == IDLE) && !cpu_req;
    assign cache_op_done = (state == CACHE_DONE);
    assign cache_op_error = (state == CACHE_DONE) && maint_error;
    // I-cache TagLo contract: [22]=valid, [21]=0 (read-only clean line),
    // [20:0]=physical tag. Upper bits are reserved and read as zero.
    assign cache_tag_rdata = {9'd0, maint_tag_entry[TAG_BITS], 1'b0,
                              maint_tag_entry[TAG_BITS-1:0]};

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:   begin
                if (cpu_req) next_state = LOOKUP;
                else if (maint_req) next_state = CACHE_LOOKUP;
            end
            LOOKUP: begin
                if (cache_hit) begin
                    if (!cpu_req) next_state = IDLE;
                end else next_state = MISS;
            end
            MISS:   if (arready && arvalid) next_state = REFILL;
            REFILL: if (rvalid && rlast)
                        next_state = (refill_error || (rresp != 2'b00)) ? ERROR : IDLE;
            ERROR:  next_state = IDLE;
            CACHE_LOOKUP: next_state = CACHE_DONE;
            CACHE_DONE:   next_state = IDLE;
        endcase
    end

    // State Reg & Data Path
    integer si, sw;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_buf_valid <= 1'b0; req_buf_addr <= 32'd0;
            arvalid <= 1'b0; araddr <= 32'd0; rready <= 1'b0;
            refill_word_cnt <= 3'd0; refill_buf <= 256'd0; refill_error <= 1'b0;
            maint_addr <= 32'd0; maint_op <= 5'd0; maint_way <= 2'd0;
            maint_tag_wdata <= 32'd0; maint_error <= 1'b0;
            for (si=0; si<SETS; si=si+1) begin
                plru_ram[si] <= 3'd0;
                for (sw=0; sw<WAYS; sw=sw+1) tag_ram[sw][si] <= {(TAG_BITS+1){1'b0}};
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (maint_req && !cpu_req) begin
                        maint_addr <= cache_op_addr;
                        maint_op <= cache_op;
                        maint_way <= cache_op_addr[12:11];
                        maint_tag_wdata <= cache_tag_wdata;
                        maint_error <= 1'b0;
                    end else if (cpu_req) begin
                        req_buf_valid <= 1'b1;
                        req_buf_addr  <= cpu_addr;
                    end
                end
                LOOKUP: begin
                    if (cache_hit) begin
                        // accessed way becomes MRU
                        plru_ram[lookup_index] <= plru_touch(plru_rdata, hit_way);
                        if (cpu_req) req_buf_addr <= cpu_addr;
                        else         req_buf_valid <= 1'b0;
                    end else begin
                        arvalid <= 1'b1;
                        araddr  <= {req_buf_addr[31:5], 5'd0};
                    end
                end
                MISS: begin
                    if (arready && arvalid) begin
                        arvalid <= 1'b0; rready <= 1'b1; refill_word_cnt <= 3'd0;
                        refill_error <= 1'b0;
                    end
                end
                REFILL: begin
                    if (rvalid && rready) begin
                        refill_buf[refill_word_cnt*32 +: 32] <= rdata;
                        refill_word_cnt <= refill_word_cnt + 1'b1;
                        if (rresp != 2'b00)
                            refill_error <= 1'b1;
                        if (rlast) rready <= 1'b0;
                    end
                end
                ERROR: begin
                    req_buf_valid <= 1'b0;
                end
                CACHE_LOOKUP: begin
                    if (maint_store_tag) begin
                        // Ignore the D-cache dirty bit in TagLo[21].
                        tag_ram[maint_way][maint_index] <=
                            {maint_tag_wdata[22], maint_tag_wdata[20:0]};
                    end else if (!maint_load_tag) begin
                        maint_error <= 1'b1;
                    end
                end
                CACHE_DONE: begin
                    // cache_op_done/cache_op_error are state-qualified outputs.
                end
            endcase
        end
    end

    // Extract correct word for CPU data (from the hit way)
    always @(*) begin
        cpu_rdata = 32'd0;
        if (state == LOOKUP && cache_hit)
            cpu_rdata = data_rdata[hit_way][lookup_word*32 +: 32];
    end

    // Assemble full refilled line (last beat merges combinationally)
    wire [255:0] full_refill_line;
    genvar g;
    generate
        for (g=0; g<8; g=g+1) begin : gen_line
            assign full_refill_line[g*32 +: 32] =
                (refill_word_cnt == g[2:0]) ? rdata : refill_buf[g*32 +: 32];
        end
    endgenerate

    // Install refilled line into the victim way + mark it MRU
    always @(posedge clk) begin
        if (sram_write_en) begin
            data_ram[victim_way][sram_addr] <= full_refill_line;
            tag_ram[victim_way][sram_addr]  <= {1'b1, req_buf_addr[31:11]};
            plru_ram[sram_addr]             <= plru_touch(plru_rdata, victim_way);
        end
    end

endmodule
