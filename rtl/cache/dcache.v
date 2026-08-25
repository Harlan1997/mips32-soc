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

module dcache #(
    // Product mips_core disables the prototype physical-address alias check;
    // standalone block tests retain it by default.
    parameter ENABLE_LEGACY_ADDR_HEURISTIC = 1'b1,
    parameter ENABLE_COHERENCY = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Data Memory Interface
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_be,
    input  wire        cpu_uncacheable,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_addr_ok,
    output wire        cpu_data_ok,
    output wire        cpu_bus_error,
    // Cached refill/writeback failures are distinguished from uncached AXI
    // response errors. The CPU maps this sideband to MIPS CacheErr (30).
    output wire        cpu_cache_error,

    // Simulation-only parity fault injection. Production instances may leave
    // these ports unconnected; only an explicit 1 enables injection.
    input  wire        sim_parity_inject_valid,
    input  wire        sim_parity_inject_tag,
    input  wire        sim_parity_inject_data,
    input  wire [1:0]  sim_parity_inject_way,
    input  wire [5:0]  sim_parity_inject_index,

    // MIPS CACHE maintenance interface. The request is held by the MEM
    // stage until cache_op_done is observed; no CPU data request is issued
    // for a maintenance operation.
    input  wire        cache_op_valid,
    input  wire [4:0]  cache_op,
    input  wire [31:0] cache_op_addr,
    output wire        cache_op_ready,
    output wire        cache_op_done,
    output wire        cache_op_error,
    input  wire [31:0] cache_tag_wdata,
    output wire [31:0] cache_tag_rdata,

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
    output reg         rready,

    // Minimal dual-core write-invalidate contract. In coherency mode stores
    // bypass this cache; a completed store invalidates a matching line in the
    // peer cache through the fabric-level broadcast.
    output wire        coh_store_valid,
    output wire [31:0] coh_store_addr,
    input  wire        coh_snoop_valid,
    input  wire [31:0] coh_snoop_addr
);

    wire uncacheable;

    // Fixed AXI configuration for cache line (8 words)
    assign awid    = 4'd0;
    assign awlen   = cache_op_valid ? 8'd7 : (uncacheable ? 8'd0 : 8'd7);
    assign awsize  = 3'b010; // 4 bytes
    assign awburst = 2'b01;  // INCR
    assign awlock  = 2'd0;
    assign awcache = cache_op_valid ? 4'b0010 : (uncacheable ? 4'b0000 : 4'b0010);
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
    localparam ERROR_RESP     = 5'd12;
    localparam CACHE_LOOKUP   = 5'd13;
    localparam CACHE_WB_REQ   = 5'd14;
    localparam CACHE_WB_DATA  = 5'd15;
    localparam CACHE_WB_RESP  = 5'd16;
    localparam CACHE_DONE     = 5'd17;

    reg [4:0] state, next_state;

    reg [31:0] maint_addr;
    reg [4:0]  maint_op;
    reg [1:0]  maint_way;
    reg        coh_refill_snoop_pending;
    reg        coh_snoop_block;
    reg [31:0] maint_tag_wdata;
    reg [255:0] maint_line;
    reg         maint_error;
    reg         maint_clear_valid;
    reg         maint_clear_dirty;

    // CPU request buffer
    reg        req_buf_valid;
    reg        req_buf_we;
    reg [31:0] req_buf_addr;
    reg [31:0] req_buf_wdata;
    reg [3:0]  req_buf_be;
    reg        req_buf_uncacheable;

    wire [31:0] lookup_addr  = (state == CACHE_LOOKUP || state == CACHE_WB_REQ ||
                                state == CACHE_WB_DATA || state == CACHE_WB_RESP ||
                                state == CACHE_DONE) ? maint_addr :
                               (req_buf_valid ? req_buf_addr : cpu_addr);
    wire [5:0]  lookup_index = lookup_addr[10:5];
    wire [20:0] lookup_tag   = lookup_addr[31:11];
    wire [2:0]  lookup_word  = lookup_addr[4:2];

    // Product-mode kseg1 accesses are translated before reaching this cache,
    // so the physical address alone cannot identify them as uncached. Preserve
    // the MMU attribute with the buffered request while retaining legacy APB
    // and SRAM-alias decoding for the prototype configuration.
    // In the prototype, untranslated physical 0x4xxx/0xAxxx accesses are
    // legacy uncached aliases. Product MMU mode must honor the translated
    // EntryLo C attribute instead: a cacheable kseg2 mapping may legitimately
    // target physical APB/alias-looking addresses.
    wire legacy_addr_uncacheable = ENABLE_LEGACY_ADDR_HEURISTIC;
    wire legacy_cpu_uncacheable = legacy_addr_uncacheable &&
                                  (cpu_addr[31:28] == 4'h4 || cpu_addr[31:28] == 4'hA);
    wire legacy_req_uncacheable = legacy_addr_uncacheable &&
                                  (req_buf_addr[31:28] == 4'h4 || req_buf_addr[31:28] == 4'hA);
    assign uncacheable = req_buf_valid ? (req_buf_uncacheable || legacy_req_uncacheable ||
                                          (ENABLE_COHERENCY && req_buf_we))
                                       : (cpu_uncacheable || legacy_cpu_uncacheable ||
                                          (ENABLE_COHERENCY && cpu_we));

    // Coherency tags are physical. Prototype SRAM accesses may arrive through
    // the A000xxxx alias, so normalize that alias before broadcasting or
    // comparing a peer store against a cached physical line.
    function [31:0] normalize_coh_addr;
        input [31:0] addr;
        begin
            normalize_coh_addr = ((addr[31:28] == 4'hA) &&
                                  (addr[27:16] == 12'd0)) ?
                                 {16'd0, addr[15:0]} : addr;
        end
    endfunction

    function [255:0] merge_coh_word;
        input [255:0] line;
        input [31:0]  wdata;
        input [3:0]   be;
        input [2:0]   word;
        reg [31:0] old_word;
        reg [31:0] new_word;
        begin
            old_word = line[word*32 +: 32];
            new_word[7:0]   = be[0] ? wdata[7:0]   : old_word[7:0];
            new_word[15:8]  = be[1] ? wdata[15:8]  : old_word[15:8];
            new_word[23:16] = be[2] ? wdata[23:16] : old_word[23:16];
            new_word[31:24] = be[3] ? wdata[31:24] : old_word[31:24];
            merge_coh_word = line;
            merge_coh_word[word*32 +: 32] = new_word;
        end
    endfunction
    wire [31:0] coh_snoop_addr_norm = normalize_coh_addr(coh_snoop_addr);

    // SRAM arrays (4-way). tag entry = {valid[22], dirty[21], tag[20:0]}
    reg [TAG_BITS+1:0] tag_ram  [0:WAYS-1][0:SETS-1];
    reg [255:0]        data_ram [0:WAYS-1][0:SETS-1];
    reg                tag_parity_ram [0:WAYS-1][0:SETS-1];
    reg                data_parity_ram [0:WAYS-1][0:SETS-1];
    reg [2:0]          plru_ram [0:SETS-1];   // tree-PLRU: b0=top, b1=left, b2=right

    wire coh_snoop_index_hit = tag_ram[0][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                                ((tag_ram[0][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11]) ||
                                 tag_ram[1][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                                 (tag_ram[1][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11]) ||
                                 tag_ram[2][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                                 (tag_ram[2][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11]) ||
                                 tag_ram[3][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                                 (tag_ram[3][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11]));
    assign coh_store_valid = ENABLE_COHERENCY && req_buf_valid && req_buf_we &&
                             (state == UC_WRESP) && bvalid && (bresp == 2'b00);
    assign coh_store_addr = normalize_coh_addr(req_buf_addr);
    wire coh_refill_collision = coh_refill_snoop_pending ||
                                (ENABLE_COHERENCY && coh_snoop_valid &&
                                 req_buf_valid &&
                                 (state == REFILL_REQ || state == REFILL_DATA || state == WRITE_MERGE) &&
                                (req_buf_addr[31:5] == coh_snoop_addr_norm[31:5]));

    // Registered read-out of the indexed set
    reg [TAG_BITS+1:0] tag_rdata  [0:WAYS-1];
    reg [255:0]        data_rdata [0:WAYS-1];
    reg                tag_parity_rdata [0:WAYS-1];
    reg                data_parity_rdata [0:WAYS-1];
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
    wire sim_parity_target = (sim_parity_inject_valid === 1'b1) &&
                             (lookup_index == sim_parity_inject_index);
    reg [WAYS-1:0] tag_parity_bad;
    reg [WAYS-1:0] data_parity_bad;
    integer pi;
    always @(*) begin
        for (pi=0; pi<WAYS; pi=pi+1) begin
            tag_parity_bad[pi] = way_valid[pi] &&
                ((^tag_rdata[pi]) != tag_parity_rdata[pi]);
            data_parity_bad[pi] = way_hit[pi] &&
                ((^data_rdata[pi]) != data_parity_rdata[pi]);
        end
    end
    wire dcache_parity_error = (|tag_parity_bad) || (|data_parity_bad);
    wire cache_hit = |way_hit;
    wire coh_snoop_hits_lookup = ENABLE_COHERENCY && coh_snoop_valid &&
                                  (lookup_addr[31:5] == coh_snoop_addr_norm[31:5]);
    wire cache_hit_for_request = cache_hit && !coh_snoop_hits_lookup && !coh_snoop_block;
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
    reg         refill_error;
    reg         cache_error_pending;

    wire sram_read_en = !coh_snoop_valid &&
                        ((state == IDLE && ((cpu_req && !uncacheable) || cache_op_valid)) ||
                         (state == COMPARE && cache_hit_for_request && cpu_req && cpu_addr_ok && !uncacheable));

    // CPU handshakes
    assign cpu_addr_ok = (state == IDLE) || (state == COMPARE && cache_hit_for_request && !uncacheable);
    assign cpu_data_ok = (state == COMPARE && cache_hit_for_request && !uncacheable &&
                          !dcache_parity_error) ||
                         (state == UC_WRESP && bvalid) || (state == UC_RDATA && rvalid) ||
                         (state == ERROR_RESP);
    assign cpu_bus_error = ((state == UC_WRESP) && bvalid && (bresp != 2'b00)) ||
                            ((state == UC_RDATA) && rvalid && (rresp != 2'b00)) ||
                            (state == ERROR_RESP);
    assign cpu_cache_error = (state == ERROR_RESP) && cache_error_pending;
    assign cache_op_ready  = (state == IDLE) && !cpu_req;
    assign cache_op_done   = (state == CACHE_DONE);
    assign cache_op_error  = (state == CACHE_DONE) && maint_error;
    wire maint_index_wbi = (maint_op == 5'b00001);
    wire maint_index_load_tag = (maint_op == 5'b00101);
    wire maint_index_store_tag = (maint_op == 5'b01001);
    wire maint_index_tag = maint_index_load_tag || maint_index_store_tag;
    wire maint_hit_inv   = (maint_op == 5'b10101);
    wire maint_hit_wb_inv= (maint_op == 5'b11001);
    wire maint_hit_wb    = (maint_op == 5'b11101);
    wire [1:0] maint_target_way = (maint_index_wbi || maint_index_tag) ? maint_way : hit_way;
    wire [TAG_BITS+1:0] maint_target_tag_entry = tag_rdata[maint_target_way];
    wire maint_target_valid = maint_target_tag_entry[TAG_BITS+1];
    wire maint_target_dirty = maint_target_tag_entry[TAG_BITS];
    wire maint_needs_wb = (maint_index_wbi || maint_hit_wb_inv || maint_hit_wb) &&
                          maint_target_valid && maint_target_dirty;
    // TagLo contract: [22]=valid, [21]=dirty, [20:0]=physical tag.
    // The upper bits are reserved and read as zero.
    assign cache_tag_rdata = {9'd0, maint_target_tag_entry};

    integer ri;
    always @(posedge clk) begin
        if (sram_read_en) begin
            for (ri=0; ri<WAYS; ri=ri+1) begin
                tag_rdata[ri]  <= tag_ram[ri][((state == IDLE) && cache_op_valid) ?
                                                cache_op_addr[10:5] : lookup_addr[10:5]];
                data_rdata[ri] <= data_ram[ri][((state == IDLE) && cache_op_valid) ?
                                                cache_op_addr[10:5] : lookup_addr[10:5]];
                tag_parity_rdata[ri] <= tag_parity_ram[ri][((state == IDLE) && cache_op_valid) ?
                                                cache_op_addr[10:5] : lookup_addr[10:5]] ^
                    (sim_parity_target && (sim_parity_inject_way == ri) &&
                     (sim_parity_inject_tag === 1'b1));
                data_parity_rdata[ri] <= data_parity_ram[ri][((state == IDLE) && cache_op_valid) ?
                                                 cache_op_addr[10:5] : lookup_addr[10:5]] ^
                    (sim_parity_target && (sim_parity_inject_way == ri) &&
                     (sim_parity_inject_data === 1'b1));
            end
            plru_rdata <= plru_ram[((state == IDLE) && cache_op_valid) ?
                                   cache_op_addr[10:5] : lookup_addr[10:5]];
        end
    end

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                // A request is captured before the state register advances.
                // Keep a buffered request live if the upstream master drops
                // its pulse after address acceptance; this is required by
                // adapters that decouple address and completion handshakes.
                if (cpu_req || req_buf_valid)
                    next_state = uncacheable ? UC_REQ : COMPARE;
                else if (cache_op_valid) next_state = CACHE_LOOKUP;
            end
            COMPARE: begin
                if (dcache_parity_error) next_state = ERROR_RESP;
                else if (cache_hit_for_request) next_state = IDLE;
                else next_state = victim_dirty ? WRITEBACK_REQ : REFILL_REQ;
            end
            WRITEBACK_REQ:  if (awready && awvalid) next_state = WRITEBACK_DATA;
            WRITEBACK_DATA: if (wready && wvalid && wlast) next_state = WRITEBACK_RESP;
            WRITEBACK_RESP: if (bready && bvalid)
                                next_state = (bresp != 2'b00) ? ERROR_RESP : REFILL_REQ;
            REFILL_REQ:     if (arready && arvalid) next_state = REFILL_DATA;
            REFILL_DATA:    if (rvalid && rlast)
                                next_state = (refill_error || (rresp != 2'b00)) ? ERROR_RESP : WRITE_MERGE;
            WRITE_MERGE:    next_state = IDLE;
            UC_REQ:         next_state = req_buf_we ? UC_WDATA : UC_RDATA;
            UC_WDATA:       if ((!awvalid || awready) && (!wvalid || wready)) next_state = UC_WRESP;
            UC_WRESP:       if (bready && bvalid) next_state = IDLE;
            UC_RDATA:       if (rready && rvalid) next_state = IDLE;
            ERROR_RESP:     next_state = IDLE;
            CACHE_LOOKUP:   next_state = maint_needs_wb ? CACHE_WB_REQ : CACHE_DONE;
            CACHE_WB_REQ:   if (awready && awvalid) next_state = CACHE_WB_DATA;
            CACHE_WB_DATA:  if (wready && wvalid && wlast) next_state = CACHE_WB_RESP;
            CACHE_WB_RESP:  if (bready && bvalid) next_state = CACHE_DONE;
            CACHE_DONE:     next_state = IDLE;
        endcase
    end

    // Line merge for writes: target line = hit way's line (hit) or refilled buf (miss)
    wire [255:0] target_line = cache_hit_for_request ? data_rdata[hit_way] : line_buf;
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
            req_buf_valid <= 1'b0; req_buf_we <= 1'b0; req_buf_uncacheable <= 1'b0;
            req_buf_addr <= 32'd0; req_buf_wdata <= 32'd0; req_buf_be <= 4'd0;
            awvalid <= 1'b0; awaddr <= 32'd0;
            wvalid <= 1'b0; wlast <= 1'b0; wdata <= 32'd0; wstrb <= 4'hF;
            bready <= 1'b0; arvalid <= 1'b0; araddr <= 32'd0; rready <= 1'b0;
            word_cnt <= 3'd0; line_buf <= 256'd0;
            refill_error <= 1'b0; cache_error_pending <= 1'b0;
            maint_addr <= 32'd0; maint_op <= 5'd0; maint_way <= 2'd0;
            maint_tag_wdata <= 32'd0;
            maint_line <= 256'd0;
            maint_error <= 1'b0;
            maint_clear_valid <= 1'b0; maint_clear_dirty <= 1'b0;
            coh_refill_snoop_pending <= 1'b0;
            coh_snoop_block <= 1'b0;
            for (si=0; si<SETS; si=si+1) begin
                plru_ram[si] <= 3'd0;
                for (sw=0; sw<WAYS; sw=sw+1) begin
                    tag_ram[sw][si] <= {(TAG_BITS+2){1'b0}};
                    data_ram[sw][si] <= 256'd0;
                    tag_parity_ram[sw][si] <= 1'b0;
                    data_parity_ram[sw][si] <= 1'b0;
                end
            end
        end else begin
            state <= next_state;
            coh_snoop_block <= ENABLE_COHERENCY && coh_snoop_valid;
            if (ENABLE_COHERENCY && coh_snoop_valid) begin
                // tag_rdata is a registered lookup snapshot and can still
                // describe a line invalidated on this same clock edge. Drop
                // its valid bits for the duration of the snoop; the next
                // lookup will repopulate the snapshot from tag_ram.
                tag_rdata[0][TAG_BITS+1] <= 1'b0;
                tag_rdata[1][TAG_BITS+1] <= 1'b0;
                tag_rdata[2][TAG_BITS+1] <= 1'b0;
                tag_rdata[3][TAG_BITS+1] <= 1'b0;
                if (tag_ram[0][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                    tag_ram[0][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                    begin
                        tag_ram[0][coh_snoop_addr_norm[10:5]][TAG_BITS+1] <= 1'b0;
                        if (tag_rdata[0][TAG_BITS+1] &&
                            tag_rdata[0][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                            tag_rdata[0][TAG_BITS+1] <= 1'b0;
                    end
                if (tag_ram[1][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                    tag_ram[1][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                    begin
                        tag_ram[1][coh_snoop_addr_norm[10:5]][TAG_BITS+1] <= 1'b0;
                        if (tag_rdata[1][TAG_BITS+1] &&
                            tag_rdata[1][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                            tag_rdata[1][TAG_BITS+1] <= 1'b0;
                    end
                if (tag_ram[2][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                    tag_ram[2][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                    begin
                        tag_ram[2][coh_snoop_addr_norm[10:5]][TAG_BITS+1] <= 1'b0;
                        if (tag_rdata[2][TAG_BITS+1] &&
                            tag_rdata[2][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                            tag_rdata[2][TAG_BITS+1] <= 1'b0;
                    end
                if (tag_ram[3][coh_snoop_addr_norm[10:5]][TAG_BITS+1] &&
                    tag_ram[3][coh_snoop_addr_norm[10:5]][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                    begin
                        tag_ram[3][coh_snoop_addr_norm[10:5]][TAG_BITS+1] <= 1'b0;
                        if (tag_rdata[3][TAG_BITS+1] &&
                            tag_rdata[3][TAG_BITS-1:0] == coh_snoop_addr_norm[31:11])
                            tag_rdata[3][TAG_BITS+1] <= 1'b0;
                    end
                if (req_buf_valid &&
                    (state == REFILL_REQ || state == REFILL_DATA || state == WRITE_MERGE) &&
                    (req_buf_addr[31:5] == coh_snoop_addr_norm[31:5]))
                    coh_refill_snoop_pending <= 1'b1;
            end
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        req_buf_valid <= 1'b1; req_buf_we <= cpu_we;
                        req_buf_addr  <= cpu_addr; req_buf_wdata <= cpu_wdata;
                        req_buf_be    <= cpu_be;
                        req_buf_uncacheable <= cpu_uncacheable || legacy_cpu_uncacheable;
                    end else if (cache_op_valid) begin
                        maint_addr <= cache_op_addr;
                        maint_op   <= cache_op;
                        maint_tag_wdata <= cache_tag_wdata;
                        // The index operation selects its way from VA[12:11].
                        // This is the explicit contract used by the directed
                        // tests; hit operations ignore this field.
                        maint_way  <= cache_op_addr[12:11];
                        maint_error <= 1'b0;
                        maint_clear_valid <= (cache_op == 5'b00001) ||
                                             (cache_op == 5'b10101) ||
                                             (cache_op == 5'b11001);
                        maint_clear_dirty <= (cache_op == 5'b11101);
                    end
                end

                CACHE_LOOKUP: begin
                    if (!maint_needs_wb) begin
                        if (maint_index_store_tag) begin
                            tag_ram[maint_target_way][lookup_index] <= maint_tag_wdata[22:0];
                            tag_parity_ram[maint_target_way][lookup_index] <= ^maint_tag_wdata[22:0];
                        end else if ((maint_index_wbi || maint_hit_inv || maint_hit_wb_inv || maint_hit_wb) &&
                            maint_target_valid && (maint_clear_valid || maint_clear_dirty)) begin
                            if (maint_clear_valid)
                                tag_ram[maint_target_way][lookup_index][TAG_BITS+1] <= 1'b0;
                            else if (maint_clear_dirty)
                                tag_ram[maint_target_way][lookup_index][TAG_BITS] <= 1'b0;
                            tag_parity_ram[maint_target_way][lookup_index] <=
                                maint_clear_valid ?
                                ^{1'b0, tag_ram[maint_target_way][lookup_index][TAG_BITS:0]} :
                                ^{1'b1, tag_ram[maint_target_way][lookup_index][TAG_BITS:0]};
                        end
                    end else begin
                        maint_line <= data_rdata[maint_target_way];
                        awvalid <= 1'b1;
                        awaddr <= {maint_target_tag_entry[TAG_BITS-1:0], lookup_index, 5'd0};
                        word_cnt <= 3'd0;
                    end
                end

                CACHE_WB_REQ: begin
                    if (awready && awvalid) begin
                        awvalid <= 1'b0;
                        wvalid <= 1'b1;
                        wstrb <= 4'hF;
                        wdata <= maint_line[31:0];
                        wlast <= 1'b0;
                    end
                end

                CACHE_WB_DATA: begin
                    if (wready && wvalid) begin
                        if (wlast) begin
                            wvalid <= 1'b0;
                            wlast <= 1'b0;
                            bready <= 1'b1;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                            if (word_cnt == 3'd6) wlast <= 1'b1;
                            wdata <= maint_line[(word_cnt+1'b1)*32 +: 32];
                        end
                    end
                end

                CACHE_WB_RESP: begin
                    if (bready && bvalid) begin
                        bready <= 1'b0;
                        if (bresp != 2'b00) begin
                            maint_error <= 1'b1;
                        end else begin
                            if (maint_clear_valid)
                                tag_ram[maint_target_way][lookup_index][TAG_BITS+1] <= 1'b0;
                            else if (maint_clear_dirty)
                                tag_ram[maint_target_way][lookup_index][TAG_BITS] <= 1'b0;
                            tag_parity_ram[maint_target_way][lookup_index] <=
                                maint_clear_valid ?
                                ^{1'b0, tag_ram[maint_target_way][lookup_index][TAG_BITS:0]} :
                                ^{tag_ram[maint_target_way][lookup_index][TAG_BITS+1],
                                  1'b0, tag_ram[maint_target_way][lookup_index][TAG_BITS-1:0]};
                        end
                    end
                end

                CACHE_DONE: begin
                    // cache_op_done/cache_op_error are state-qualified outputs;
                    // the MEM stage samples them while this state is active.
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
                    if (bready && bvalid) begin
                        bready <= 1'b0;
                        if ((bresp == 2'b00) && ENABLE_COHERENCY) begin
                            // Keep a local write-through copy coherent without
                            // forcing the next local load through a refill.
                            for (sw=0; sw<WAYS; sw=sw+1)
                                if (tag_ram[sw][req_buf_addr[10:5]][TAG_BITS+1] &&
                                    (tag_ram[sw][req_buf_addr[10:5]][TAG_BITS-1:0] ==
                                     normalize_coh_addr(req_buf_addr)[31:11])) begin
                                    data_ram[sw][req_buf_addr[10:5]] <=
                                        merge_coh_word(data_ram[sw][req_buf_addr[10:5]],
                                                       req_buf_wdata, req_buf_be,
                                                       req_buf_addr[4:2]);
                                    data_parity_ram[sw][req_buf_addr[10:5]] <=
                                        ^merge_coh_word(data_ram[sw][req_buf_addr[10:5]],
                                                        req_buf_wdata, req_buf_be,
                                                        req_buf_addr[4:2]);
                                    tag_ram[sw][req_buf_addr[10:5]] <=
                                        {1'b1, 1'b0, normalize_coh_addr(req_buf_addr)[31:11]};
                                    tag_parity_ram[sw][req_buf_addr[10:5]] <=
                                        ^{1'b1, 1'b0, normalize_coh_addr(req_buf_addr)[31:11]};
                                end
                        end
                        req_buf_valid <= 1'b0;
                    end
                end
                UC_RDATA: begin
                    if (rready && rvalid) begin rready <= 1'b0; req_buf_valid <= 1'b0; end
                    else if (arready && arvalid) begin arvalid <= 1'b0; rready <= 1'b1; end
                end

            COMPARE: begin
                if (dcache_parity_error) begin
                    cache_error_pending <= 1'b1;
                end else if (cache_hit_for_request) begin
                        // Update PLRU: accessed (hit) way is MRU
                        plru_ram[lookup_index] <= plru_touch(plru_rdata, hit_way);
                        if (req_buf_we) begin
                            data_ram[hit_way][lookup_index] <= new_line;
                            data_parity_ram[hit_way][lookup_index] <= ^new_line;
                            tag_ram[hit_way][lookup_index]  <= {1'b1, 1'b1, lookup_tag};
                            tag_parity_ram[hit_way][lookup_index] <=
                                ^{1'b1, 1'b1, lookup_tag};
                        end
                        req_buf_valid <= 1'b0;
                    end else begin
                        // Miss: launch writeback (dirty victim) or refill
                        refill_error <= 1'b0;
                        cache_error_pending <= 1'b0;
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
                        if (bresp != 2'b00) begin
                            cache_error_pending <= 1'b1;
                        end else begin
                            arvalid <= 1'b1; araddr <= {req_buf_addr[31:5], 5'd0}; word_cnt <= 3'd0;
                        end
                    end
                end

                REFILL_REQ: begin
                    if (arready && arvalid) begin arvalid <= 1'b0; rready <= 1'b1; end
                end
                REFILL_DATA: begin
                    if (rready && rvalid) begin
                        line_buf[word_cnt*32 +: 32] <= rdata;
                        word_cnt <= word_cnt + 1'b1;
                        if (rresp != 2'b00) begin
                            refill_error <= 1'b1;
                            cache_error_pending <= 1'b1;
                        end
                        if (rlast) rready <= 1'b0;
                    end
                end
                WRITE_MERGE: begin
                    // Install refilled (optionally write-merged) line into victim way
                    data_ram[victim_way][lookup_index] <= new_line;
                    data_parity_ram[victim_way][lookup_index] <= ^new_line;
                    // A peer store may have arrived after the refill had
                    // already read the affected word. Do not publish this
                    // stale line; the next access must refill from memory.
                    tag_ram[victim_way][lookup_index]  <= {~coh_refill_collision, req_buf_we, lookup_tag};
                    tag_parity_ram[victim_way][lookup_index] <=
                        ^{~coh_refill_collision, req_buf_we, lookup_tag};
                    // Accessed way becomes MRU
                    plru_ram[lookup_index] <= plru_touch(plru_rdata, victim_way);
                    req_buf_valid <= 1'b0;
                    coh_refill_snoop_pending <= 1'b0;
                end
                ERROR_RESP: begin
                    if (cache_error_pending)
                        tag_ram[victim_way][lookup_index] <= {(TAG_BITS+2){1'b0}};
                    req_buf_valid <= 1'b0;
                    coh_refill_snoop_pending <= 1'b0;
                end
            endcase
        end
    end

endmodule
