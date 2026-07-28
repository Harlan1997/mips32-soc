// =============================================================================
// File Name: l2_cache_caching.v
// Design:    L2 Unified Cache — 8-way set-associative write-back write-allocate
// Author:    Antigravity — Phase C / TASK-003
// Description:
//   Commercial-grade 128KB 8-way set-associative L2 cache with Pseudo-LRU
//   replacement, write-back and write-allocate policy, and AXI4 slave/master
//   interfaces adhering to the single-outstanding external fabric contract.
//
//   Geometry (default parameters):
//     * SIZE_BYTES = 131072 (128 KB)
//     * LINE_BYTES = 32 (32-byte cache line)
//     * WAYS       = 8 (8-way set associative)
//     * NUM_SETS   = 512 sets
//     * OFFSET_BITS= 5, WORD_BITS = 3, INDEX_BITS = 9, TAG_BITS = 18
//
//   Coherence / Snoop:
//     * Snoop port is tied off (snoop_ack = snoop_valid, snoop_hit = 0).
// =============================================================================

`include "soc_config.vh"

module l2_cache_caching #(
    parameter SIZE_BYTES = 131072,
    parameter LINE_BYTES = 32,
    parameter WAYS       = 8,
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,

    // Upstream slave interface
    input  wire [ID_WIDTH-1:0]   s_awid,
    input  wire [ADDR_WIDTH-1:0] s_awaddr,
    input  wire [7:0]            s_awlen,
    input  wire [2:0]            s_awsize,
    input  wire [1:0]            s_awburst,
    input  wire                  s_awvalid,
    output reg                   s_awready,

    input  wire [DATA_WIDTH-1:0] s_wdata,
    input  wire [3:0]            s_wstrb,
    input  wire                  s_wlast,
    input  wire                  s_wvalid,
    output reg                   s_wready,

    output reg  [ID_WIDTH-1:0]   s_bid,
    output reg  [1:0]            s_bresp,
    output reg                   s_bvalid,
    input  wire                  s_bready,

    input  wire [ID_WIDTH-1:0]   s_arid,
    input  wire [ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]            s_arlen,
    input  wire [2:0]            s_arsize,
    input  wire [1:0]            s_arburst,
    input  wire                  s_arvalid,
    output reg                   s_arready,

    output reg  [ID_WIDTH-1:0]   s_rid,
    output reg  [DATA_WIDTH-1:0] s_rdata,
    output reg  [1:0]            s_rresp,
    output reg                   s_rlast,
    output reg                   s_rvalid,
    input  wire                  s_rready,

    // Downstream master interface
    output reg  [ID_WIDTH-1:0]   m_awid,
    output reg  [ADDR_WIDTH-1:0] m_awaddr,
    output reg  [7:0]            m_awlen,
    output reg  [2:0]            m_awsize,
    output reg  [1:0]            m_awburst,
    output reg                   m_awvalid,
    input  wire                  m_awready,

    output reg  [DATA_WIDTH-1:0] m_wdata,
    output reg  [3:0]            m_wstrb,
    output reg                   m_wlast,
    output reg                   m_wvalid,
    input  wire                  m_wready,

    input  wire [ID_WIDTH-1:0]   m_bid,
    input  wire [1:0]            m_bresp,
    input  wire                  m_bvalid,
    output reg                   m_bready,

    output reg  [ID_WIDTH-1:0]   m_arid,
    output reg  [ADDR_WIDTH-1:0] m_araddr,
    output reg  [7:0]            m_arlen,
    output reg  [2:0]            m_arsize,
    output reg  [1:0]            m_arburst,
    output reg                   m_arvalid,
    input  wire                  m_arready,

    input  wire [ID_WIDTH-1:0]   m_rid,
    input  wire [DATA_WIDTH-1:0] m_rdata,
    input  wire [1:0]            m_rresp,
    input  wire                  m_rlast,
    input  wire                  m_rvalid,
    output reg                   m_rready,

    // Snoop port (tied off)
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

    // Reserved snoop tie-off
    assign snoop_ack = snoop_valid;
    assign snoop_hit = 1'b0;

    // Derived geometry parameters
    localparam OFFSET_BITS  = 5;                                      // 32-byte line -> 5 bits
    localparam WORDS_PER_LN = LINE_BYTES / (DATA_WIDTH / 8);          // 8 words per line
    localparam WORD_BITS    = 3;                                      // 3 bits word offset
    localparam NUM_SETS     = SIZE_BYTES / (LINE_BYTES * WAYS);      // 512 sets for 128KB 8-way
    localparam INDEX_BITS   = $clog2(NUM_SETS);                       // 9 bits
    localparam PA_WIDTH     = 29;                                      // MIPS 29-bit physical address space
    localparam TAG_BITS     = PA_WIDTH - INDEX_BITS - OFFSET_BITS;    // 15 bits

    // Unsupported upstream request checks.
    // Only word-size (4B), word-aligned, INCR bursts are supported. Burst LENGTH
    // is not restricted: the FSM services arbitrary-length INCR bursts (including
    // those that cross cache lines) by re-looking-up index/tag/hit per beat, so
    // a len>7 burst is legal and must return OKAY (the SoC fabric issues 9-beat
    // SRAM-alias bursts). beat_cnt and the address adder are 8-bit / 29-bit wide,
    // covering the full AXI INCR range (len up to 255).
    wire is_unsupported_aw = (s_awsize != 3'b010) ||
                             (s_awaddr[1:0] != 2'b00) ||
                             (s_awburst != 2'b01);

    wire is_unsupported_ar = (s_arsize != 3'b010) ||
                             (s_araddr[1:0] != 2'b00) ||
                             (s_arburst != 2'b01);

    // Cache Storage Arrays.
    // These model retention RAM macros (data/tag arrays) plus valid/dirty/PLRU
    // flops. Like the SoC SRAM model (rtl/perips/axi_sram.v), their contents are
    // established once at cold boot via an initial block and are NOT wiped by the
    // warm rst_n pulses the verification environment injects (JTAG reset-recovery
    // coverage). Only the FSM control state resets on rst_n. This makes the
    // write-back policy reset-safe: a line written dirty before a warm reset is
    // still present (and authoritative) afterwards, so committed writes are not
    // silently dropped and post-reset reads hit in L2 rather than refilling stale
    // data from downstream. NOTE for silicon: real valid bits need a power-on
    // reset to flash-invalidate at true cold boot; this behavioral model relies
    // on the initial block for that, matching axi_sram.v.
    reg [TAG_BITS-1:0]   tag_ram   [0:NUM_SETS-1][0:WAYS-1];
    reg                  valid_ram [0:NUM_SETS-1][0:WAYS-1];
    reg                  dirty_ram [0:NUM_SETS-1][0:WAYS-1];
    reg [DATA_WIDTH-1:0] data_ram  [0:NUM_SETS-1][0:WAYS-1][0:WORDS_PER_LN-1];
    reg [6:0]            plru_ram  [0:NUM_SETS-1];

    // Cold-boot initialization (retention arrays; not reset by warm rst_n).
    integer cb_s, cb_w;
    initial begin
        for (cb_s = 0; cb_s < NUM_SETS; cb_s = cb_s + 1) begin
            plru_ram[cb_s] = 7'd0;
            for (cb_w = 0; cb_w < WAYS; cb_w = cb_w + 1) begin
                valid_ram[cb_s][cb_w] = 1'b0;
                dirty_ram[cb_s][cb_w] = 1'b0;
            end
        end
    end

    // FSM States
    localparam ST_IDLE        = 4'd0;
    localparam ST_W_ACCEPT    = 4'd1;
    localparam ST_LOOKUP      = 4'd2;
    localparam ST_R_HIT_BURST = 4'd3;
    localparam ST_W_HIT_MERGE = 4'd4;
    localparam ST_MISS_ALLOC  = 4'd5;
    localparam ST_EVICT_AW    = 4'd6;
    localparam ST_EVICT_W     = 4'd7;
    localparam ST_EVICT_B     = 4'd8;
    localparam ST_REFILL_AR   = 4'd9;
    localparam ST_REFILL_R    = 4'd10;
    localparam ST_W_RESP      = 4'd11;
    localparam ST_ERR_RESP_R  = 4'd12;
    localparam ST_ERR_RESP_B  = 4'd13;
    localparam ST_W_DRAIN_ERR = 4'd14;

    reg [3:0] state;

    // Latched request variables
    reg                    req_is_write;
    reg [ID_WIDTH-1:0]     req_id;
    reg [ADDR_WIDTH-1:0]   req_addr;
    reg [7:0]              req_len;
    reg [2:0]              req_size;
    reg [1:0]              req_burst;
    reg [7:0]              beat_cnt;
    reg [1:0]              resp_err;

    // Latched W beat data
    reg [DATA_WIDTH-1:0]   req_wdata;
    reg [3:0]              req_wstrb;
    reg                    req_wlast;

    // Allocated way and eviction counter / refill counter
    reg [2:0]              alloc_way;
    reg [2:0]              fill_cnt;
    reg [2:0]              evict_cnt;
    reg [ADDR_WIDTH-1:0]   evict_addr;

    // Helper functions for Pseudo-LRU
    function [2:0] get_plru_victim;
        input [6:0] p;
        begin
            if (p[0] == 1'b0) begin
                if (p[2] == 1'b0)
                    get_plru_victim = (p[6] == 1'b0) ? 3'd7 : 3'd6;
                else
                    get_plru_victim = (p[5] == 1'b0) ? 3'd5 : 3'd4;
            end else begin
                if (p[1] == 1'b0)
                    get_plru_victim = (p[4] == 1'b0) ? 3'd3 : 3'd2;
                else
                    get_plru_victim = (p[3] == 1'b0) ? 3'd1 : 3'd0;
            end
        end
    endfunction

    function [2:0] get_victim_way;
        input [WAYS-1:0] valids;
        input [6:0] p;
        begin
            if (!valids[0])      get_victim_way = 3'd0;
            else if (!valids[1]) get_victim_way = 3'd1;
            else if (!valids[2]) get_victim_way = 3'd2;
            else if (!valids[3]) get_victim_way = 3'd3;
            else if (!valids[4]) get_victim_way = 3'd4;
            else if (!valids[5]) get_victim_way = 3'd5;
            else if (!valids[6]) get_victim_way = 3'd6;
            else if (!valids[7]) get_victim_way = 3'd7;
            else                 get_victim_way = get_plru_victim(p);
        end
    endfunction

    function [6:0] update_plru;
        input [6:0] p;
        input [2:0] w;
        reg [6:0] p_next;
        begin
            p_next = p;
            p_next[0] = (w < 4) ? 1'b1 : 1'b0;
            if (w < 4) begin
                p_next[1] = (w < 2) ? 1'b1 : 1'b0;
                if (w < 2)
                    p_next[3] = (w == 0) ? 1'b1 : 1'b0;
                else
                    p_next[4] = (w == 2) ? 1'b1 : 1'b0;
            end else begin
                p_next[2] = (w < 6) ? 1'b1 : 1'b0;
                if (w < 6)
                    p_next[5] = (w == 4) ? 1'b1 : 1'b0;
                else
                    p_next[6] = (w == 6) ? 1'b1 : 1'b0;
            end
            update_plru = p_next;
        end
    endfunction

    // Address breakdown for current beat (using 29-bit physical address space)
    wire [PA_WIDTH-1:0]   current_beat_pa   = req_addr[28:0] + (beat_cnt << 2);
    wire [INDEX_BITS-1:0] req_index         = current_beat_pa[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   req_tag           = current_beat_pa[PA_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    wire [WORD_BITS-1:0]  req_wordoff       = current_beat_pa[OFFSET_BITS-1:2];

    // Tag matching across ways
    reg [WAYS-1:0] way_hit;
    reg [WAYS-1:0] valids_of_index;
    integer i;
    always @(*) begin
        for (i = 0; i < WAYS; i = i + 1) begin
            valids_of_index[i] = valid_ram[req_index][i];
            way_hit[i]         = valid_ram[req_index][i] && (tag_ram[req_index][i] == req_tag);
        end
    end

    wire hit = |way_hit;

    reg [2:0] hit_way;
    always @(*) begin
        hit_way = 3'd0;
        for (i = 0; i < WAYS; i = i + 1) begin
            if (way_hit[i]) hit_way = i[2:0];
        end
    end

    // Default AXI output drives
    always @(*) begin
        s_awready = 1'b0;
        s_wready  = 1'b0;
        s_arready = 1'b0;
        s_bvalid  = 1'b0;
        s_rvalid  = 1'b0;
        s_rlast   = 1'b0;
        s_bid     = req_id;
        s_rid     = req_id;
        s_rdata   = data_ram[req_index][hit_way][req_wordoff];
        s_rresp   = 2'b00;
        s_bresp   = 2'b00;

        m_awvalid = 1'b0;
        m_awid    = req_id;
        m_awaddr  = evict_addr;
        m_awlen   = 8'd7;
        m_awsize  = 3'b010;
        m_awburst = 2'b01;

        m_wvalid  = 1'b0;
        m_wdata   = data_ram[req_index][alloc_way][evict_cnt];
        m_wstrb   = 4'hF;
        m_wlast   = (evict_cnt == 3'd7);

        m_bready  = 1'b0;

        m_arvalid = 1'b0;
        m_arid    = req_id;
        m_araddr  = {3'b000, current_beat_pa[28:5], 5'b00000};
        m_arlen   = 8'd7;
        m_arsize  = 3'b010;
        m_arburst = 2'b01;

        m_rready  = 1'b0;

        case (state)
            ST_IDLE: begin
                s_awready = 1'b1;
                s_arready = ~s_awvalid;
            end

            ST_W_ACCEPT: begin
                s_wready = 1'b1;
            end

            ST_R_HIT_BURST: begin
                s_rvalid = hit;
                s_rlast  = hit && (beat_cnt == req_len);
            end

            ST_W_RESP: begin
                s_bvalid = 1'b1;
            end

            ST_EVICT_AW: begin
                m_awvalid = 1'b1;
            end

            ST_EVICT_W: begin
                m_wvalid = 1'b1;
            end

            ST_EVICT_B: begin
                m_bready = 1'b1;
            end

            ST_REFILL_AR: begin
                m_arvalid = 1'b1;
            end

            ST_REFILL_R: begin
                m_rready = 1'b1;
            end

            ST_ERR_RESP_R: begin
                s_rvalid = 1'b1;
                s_rresp  = resp_err;
                s_rdata  = {DATA_WIDTH{1'b0}};
                s_rlast  = (beat_cnt == req_len);
            end

            ST_ERR_RESP_B: begin
                s_bvalid = 1'b1;
                s_bresp  = resp_err;
            end

            ST_W_DRAIN_ERR: begin
                s_wready = 1'b1;
            end

            default: ;
        endcase
    end

    // Sequential FSM & Cache Array Updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            req_is_write <= 1'b0;
            req_id       <= {ID_WIDTH{1'b0}};
            req_addr     <= {ADDR_WIDTH{1'b0}};
            req_len      <= 8'd0;
            req_size     <= 3'd0;
            req_burst    <= 2'd0;
            beat_cnt     <= 8'd0;

            req_wdata    <= {DATA_WIDTH{1'b0}};
            req_wstrb    <= 4'h0;
            req_wlast    <= 1'b0;

            alloc_way    <= 3'd0;
            fill_cnt     <= 3'd0;
            evict_cnt    <= 3'd0;
            evict_addr   <= {ADDR_WIDTH{1'b0}};
            resp_err     <= 2'b00;

            // NOTE: valid_ram / dirty_ram / plru_ram / tag_ram / data_ram are
            // retention arrays (see declaration above) and are intentionally NOT
            // cleared here. Clearing them on a warm rst_n pulse would drop
            // committed dirty lines before writeback. Cold-boot init is done in
            // the initial block.
        end else begin
            case (state)
                ST_IDLE: begin
                    beat_cnt <= 8'd0;
                    resp_err <= 2'b00;
                    if (s_awvalid) begin
                        req_is_write <= 1'b1;
                        req_id       <= s_awid;
                        req_addr     <= s_awaddr;
                        req_len      <= s_awlen;
                        req_size     <= s_awsize;
                        req_burst    <= s_awburst;
                        if (is_unsupported_aw) begin
                            resp_err <= 2'b10; // SLVERR
                        end
                        state <= ST_W_ACCEPT;
                    end else if (s_arvalid) begin
                        req_is_write <= 1'b0;
                        req_id       <= s_arid;
                        req_addr     <= s_araddr;
                        req_len      <= s_arlen;
                        req_size     <= s_arsize;
                        req_burst    <= s_arburst;
                        if (is_unsupported_ar) begin
                            resp_err <= 2'b10; // SLVERR
                            state    <= ST_ERR_RESP_R;
                        end else begin
                            state    <= ST_LOOKUP;
                        end
                    end
                end

                ST_W_ACCEPT: begin
                    if (s_wvalid && s_wready) begin
                        req_wdata <= s_wdata;
                        req_wstrb <= s_wstrb;
                        req_wlast <= s_wlast;
                        if (resp_err != 2'b00) begin
                            if (s_wlast)
                                state <= ST_ERR_RESP_B;
                            else
                                state <= ST_W_DRAIN_ERR;
                        end else begin
                            state <= ST_LOOKUP;
                        end
                    end
                end

                ST_LOOKUP: begin
                    if (hit) begin
                        if (req_is_write) begin
                            state <= ST_W_HIT_MERGE;
                        end else begin
                            plru_ram[req_index] <= update_plru(plru_ram[req_index], hit_way);
                            state <= ST_R_HIT_BURST;
                        end
                    end else begin
                        state <= ST_MISS_ALLOC;
                    end
                end

                ST_W_HIT_MERGE: begin
                    data_ram[req_index][hit_way][req_wordoff] <= {
                        req_wstrb[3] ? req_wdata[31:24] : data_ram[req_index][hit_way][req_wordoff][31:24],
                        req_wstrb[2] ? req_wdata[23:16] : data_ram[req_index][hit_way][req_wordoff][23:16],
                        req_wstrb[1] ? req_wdata[15:8]  : data_ram[req_index][hit_way][req_wordoff][15:8],
                        req_wstrb[0] ? req_wdata[7:0]   : data_ram[req_index][hit_way][req_wordoff][7:0]
                    };
                    dirty_ram[req_index][hit_way] <= 1'b1;
                    plru_ram[req_index] <= update_plru(plru_ram[req_index], hit_way);

                    if (req_wlast) begin
                        state <= ST_W_RESP;
                    end else begin
                        beat_cnt <= beat_cnt + 1'b1;
                        state    <= ST_W_ACCEPT;
                    end
                end

                ST_R_HIT_BURST: begin
                    if (hit) begin
                        if (s_rready) begin
                            plru_ram[req_index] <= update_plru(plru_ram[req_index], hit_way);
                            if (beat_cnt == req_len) begin
                                beat_cnt <= 8'd0;
                                state    <= ST_IDLE;
                            end else begin
                                beat_cnt <= beat_cnt + 1'b1;
                            end
                        end
                    end else begin
                        state <= ST_MISS_ALLOC;
                    end
                end

                ST_W_RESP: begin
                    if (s_bready) begin
                        beat_cnt <= 8'd0;
                        state    <= ST_IDLE;
                    end
                end

                ST_MISS_ALLOC: begin
                    alloc_way <= get_victim_way(valids_of_index, plru_ram[req_index]);
                    if (valid_ram[req_index][get_victim_way(valids_of_index, plru_ram[req_index])] &&
                        dirty_ram[req_index][get_victim_way(valids_of_index, plru_ram[req_index])]) begin
                        evict_addr <= {3'b000, tag_ram[req_index][get_victim_way(valids_of_index, plru_ram[req_index])],
                                       req_index, {OFFSET_BITS{1'b0}}};
                        evict_cnt  <= 3'd0;
                        state      <= ST_EVICT_AW;
                    end else begin
                        state      <= ST_REFILL_AR;
                    end
                end

                ST_EVICT_AW: begin
                    if (m_awready) begin
                        evict_cnt <= 3'd0;
                        state     <= ST_EVICT_W;
                    end
                end

                ST_EVICT_W: begin
                    if (m_wready) begin
                        if (evict_cnt == 3'd7) begin
                            state <= ST_EVICT_B;
                        end else begin
                            evict_cnt <= evict_cnt + 1'b1;
                        end
                    end
                end

                ST_EVICT_B: begin
                    if (m_bvalid) begin
                        if (m_bresp != 2'b00) begin
                            resp_err <= m_bresp;
                            if (req_is_write) begin
                                if (req_wlast)
                                    state <= ST_ERR_RESP_B;
                                else
                                    state <= ST_W_DRAIN_ERR;
                            end else begin
                                state <= ST_ERR_RESP_R;
                            end
                        end else begin
                            state <= ST_REFILL_AR;
                        end
                    end
                end

                ST_REFILL_AR: begin
                    if (m_arready) begin
                        fill_cnt <= 3'd0;
                        resp_err <= 2'b00;
                        state    <= ST_REFILL_R;
                    end
                end

                ST_REFILL_R: begin
                    if (m_rvalid) begin
                        data_ram[req_index][alloc_way][fill_cnt] <= m_rdata;
                        if (m_rresp != 2'b00 && resp_err == 2'b00) begin
                            resp_err <= m_rresp;
                        end
                        if (m_rlast || (fill_cnt == 3'd7)) begin
                            fill_cnt <= 3'd0;
                            if (resp_err != 2'b00 || m_rresp != 2'b00) begin
                                valid_ram[req_index][alloc_way] <= 1'b0;
                                dirty_ram[req_index][alloc_way] <= 1'b0;
                                resp_err <= (resp_err != 2'b00) ? resp_err : m_rresp;
                                if (req_is_write) begin
                                    if (req_wlast)
                                        state <= ST_ERR_RESP_B;
                                    else
                                        state <= ST_W_DRAIN_ERR;
                                end else begin
                                    state <= ST_ERR_RESP_R;
                                end
                            end else begin
                                tag_ram[req_index][alloc_way]   <= req_tag;
                                valid_ram[req_index][alloc_way] <= 1'b1;
                                dirty_ram[req_index][alloc_way] <= 1'b0;
                                state                           <= ST_LOOKUP;
                            end
                        end else begin
                            fill_cnt <= fill_cnt + 1'b1;
                        end
                    end
                end

                ST_W_DRAIN_ERR: begin
                    if (s_wvalid && s_wready) begin
                        if (s_wlast) begin
                            state <= ST_ERR_RESP_B;
                        end
                    end
                end

                ST_ERR_RESP_R: begin
                    if (s_rready) begin
                        if (beat_cnt == req_len) begin
                            beat_cnt <= 8'd0;
                            state    <= ST_IDLE;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                        end
                    end
                end

                ST_ERR_RESP_B: begin
                    if (s_bready) begin
                        beat_cnt <= 8'd0;
                        state    <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
