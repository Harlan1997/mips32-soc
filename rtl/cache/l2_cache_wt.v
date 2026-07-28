// =============================================================================
// File Name: l2_cache_wt.v
// Design:    L2 write-through no-write-allocate cache (Phase C real caching)
// Author:    Antigravity — Phase C
// Description:
//   Direct-mapped write-through L2 with burst-aware slave FSM. Chosen for
//   Phase C first-pass because it sidesteps the write-back + write-allocate
//   complexity that blocked earlier l2_cache_caching.v integration.
//
//   Policy:
//     * Writes  → forward burst to downstream; if line in cache, update
//                 word (write-through). Never allocate on write miss.
//     * Reads   → tag check. Hit: return from cache. Miss: forward AR to
//                 downstream, snoop each R beat into cache line, forward
//                 to upstream.
//
//   Burst handling:
//     * Slave HIT_R loops arlen+1 R beats out of one cached line (assumes
//       burst stays within one 32-byte line — L1 line-refill bursts do).
//     * Slave HIT_W accepts awlen+1 W beats one at a time, merging each
//       into cache/downstream, wlast → single BVALID.
//     * Miss path streams AR/R burst through with in-line snoop.
//
//   Geometry:
//     32 KB, 1-way direct-mapped, 32 B line → 1024 sets.
//     Word-in-line offset = 3 bits, index = 10 bits, tag = 17 bits.
//
//   Deferred:
//     * 8-way pseudo-LRU (per spec §2.1)
//     * MSHR + non-blocking
//     * Snoop coherence (port tied off)
// =============================================================================

module l2_cache_wt #(
    parameter SIZE_BYTES = 32768,
    parameter LINE_BYTES = 32,
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,

    // Upstream slave
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

    // Downstream master
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

    // Snoop (tied off)
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

    localparam OFFSET_BITS  = 5;
    localparam WORD_BITS    = OFFSET_BITS - 2;         // 3
    localparam WORDS_PER_LN = (1 << WORD_BITS);        // 8
    localparam INDEX_BITS   = $clog2(SIZE_BYTES / LINE_BYTES);
    localparam NUM_SETS     = (1 << INDEX_BITS);
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    assign snoop_ack = snoop_valid;
    assign snoop_hit = 1'b0;

    // -------- Cache arrays --------
    reg [TAG_BITS-1:0]   tag_ram   [NUM_SETS-1:0];
    reg                  valid_ram [NUM_SETS-1:0];
    reg [DATA_WIDTH-1:0] data_ram  [NUM_SETS-1:0][WORDS_PER_LN-1:0];

    integer i, j;
    initial begin
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            valid_ram[i] = 1'b0;
            tag_ram[i]   = {TAG_BITS{1'b0}};
            for (j = 0; j < WORDS_PER_LN; j = j + 1)
                data_ram[i][j] = 32'h0;
        end
    end

    // -------- FSM --------
    localparam ST_IDLE       = 4'd0;
    // Read path
    localparam ST_R_LOOKUP   = 4'd1;
    localparam ST_R_HIT_LOOP = 4'd2;
    localparam ST_R_MISS_AR  = 4'd3;
    localparam ST_R_MISS_R   = 4'd4;
    // Write path (write-through, no allocate)
    localparam ST_W_ACCEPT   = 4'd5;   // wait for W beats
    localparam ST_W_AW_FWD   = 4'd6;   // forward AW downstream
    localparam ST_W_W_FWD    = 4'd7;   // forward W beat downstream
    localparam ST_W_B_WAIT   = 4'd8;   // wait downstream B
    localparam ST_W_RESP     = 4'd9;   // send upstream B

    reg [3:0] state;

    // -------- Request latches --------
    reg [ID_WIDTH-1:0]   req_id;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg [7:0]            req_len;
    reg [2:0]            req_size;
    reg [1:0]            req_burst;
    reg [7:0]            beat_cnt;

    // Write-path W-beat FIFO (single entry — accept next W only when
    // downstream ready). Simpler than a real FIFO.
    reg [DATA_WIDTH-1:0] w_buf_data;
    reg [3:0]            w_buf_strb;
    reg                  w_buf_last;
    reg                  w_buf_valid;

    wire [ADDR_WIDTH-1:0] beat_addr   = req_addr + (beat_cnt << 2);
    wire [INDEX_BITS-1:0] beat_index  = beat_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   beat_tag    = beat_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    wire [WORD_BITS-1:0]  beat_wordoff = beat_addr[OFFSET_BITS-1:2];
    wire hit = valid_ram[beat_index] && (tag_ram[beat_index] == beat_tag);
    wire is_last_beat = (beat_cnt == req_len);

    // Full-line refill helpers, keyed off the CURRENT beat's address (beat_addr)
    // rather than the burst start. A read burst may cross cache-line boundaries
    // (the external master issues such bursts), so each beat must resolve to its
    // own line: a read miss fetches that entire aligned line (every word valid,
    // not just the requested beats — else a later hit on an un-fetched word
    // returns stale 0), and a beat crossing into an un-cached line triggers a
    // fresh refill mid-burst.
    wire [INDEX_BITS-1:0] line_index = beat_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   line_tag   = beat_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    wire [ADDR_WIDTH-1:0] line_base  = {beat_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    reg  [WORD_BITS-1:0]  fill_idx;

    // -------- Default AXI drives --------
    always @(*) begin
        s_awready = 1'b0;
        s_wready  = 1'b0;
        s_arready = 1'b0;
        s_bvalid  = 1'b0;
        s_rvalid  = 1'b0;
        s_rlast   = 1'b0;
        s_bid     = req_id;
        s_rid     = req_id;
        s_rdata   = data_ram[beat_index][beat_wordoff];
        s_rresp   = 2'b00;
        s_bresp   = 2'b00;

        m_awvalid = 1'b0;
        m_awid    = req_id;
        m_awaddr  = req_addr;
        m_awlen   = req_len;
        m_awsize  = req_size;
        m_awburst = req_burst;
        m_wvalid  = 1'b0;
        m_wdata   = w_buf_data;
        m_wstrb   = w_buf_strb;
        m_wlast   = w_buf_last;
        m_bready  = 1'b0;
        m_arvalid = 1'b0;
        m_arid    = req_id;
        m_araddr  = req_addr;
        m_arlen   = req_len;
        m_arsize  = req_size;
        m_arburst = req_burst;
        m_rready  = 1'b0;

        case (state)
            ST_IDLE: begin
                s_awready = 1'b1;
                s_arready = ~s_awvalid;
            end
            ST_R_HIT_LOOP: begin
                // Only present valid read data while the current beat's line is
                // cached. If a multi-line burst steps into an un-cached line,
                // hit drops and the FSM diverts to refill it (see sequential).
                s_rvalid = hit;
                s_rlast  = is_last_beat;
            end
            ST_R_MISS_AR: begin
                // Fetch the whole aligned line (WORDS_PER_LN beats), not just
                // the upstream burst, so the cached line is fully valid.
                m_arvalid = 1'b1;
                m_araddr  = line_base;
                m_arlen   = WORDS_PER_LN - 1;
                m_arsize  = 3'b010;
                m_arburst = 2'b01;
            end
            ST_R_MISS_R: begin
                // Sink the full-line refill from downstream; do not bridge to
                // upstream here (upstream is served from cache after the fill).
                m_rready = 1'b1;
            end
            ST_W_ACCEPT: begin
                s_wready = ~w_buf_valid;
            end
            ST_W_AW_FWD: begin
                m_awvalid = 1'b1;
            end
            ST_W_W_FWD: begin
                m_wvalid = w_buf_valid;
            end
            ST_W_B_WAIT: begin
                m_bready = 1'b1;
                // Also accept next W beat if any into buffer
                s_wready = ~w_buf_valid;
            end
            ST_W_RESP: begin
                s_bvalid = 1'b1;
            end
            default: ;
        endcase
    end

    // -------- Sequential --------
    // AW forward tracking, B response gating
    reg m_aw_sent;
    reg m_b_rcvd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            req_id      <= {ID_WIDTH{1'b0}};
            req_addr    <= {ADDR_WIDTH{1'b0}};
            req_len     <= 8'h0;
            req_size    <= 3'h0;
            req_burst   <= 2'h0;
            beat_cnt    <= 8'h0;
            fill_idx    <= {WORD_BITS{1'b0}};
            w_buf_valid <= 1'b0;
            w_buf_data  <= {DATA_WIDTH{1'b0}};
            w_buf_strb  <= 4'hF;
            w_buf_last  <= 1'b0;
            m_aw_sent   <= 1'b0;
            m_b_rcvd    <= 1'b0;
            for (i = 0; i < NUM_SETS; i = i + 1) valid_ram[i] <= 1'b0;
        end else begin
            case (state)
                //--------------------------------------------------
                ST_IDLE: begin
                    beat_cnt  <= 8'h0;
                    m_aw_sent <= 1'b0;
                    m_b_rcvd  <= 1'b0;
                    if (s_awvalid) begin
                        req_id    <= s_awid;
                        req_addr  <= s_awaddr;
                        req_len   <= s_awlen;
                        req_size  <= s_awsize;
                        req_burst <= s_awburst;
                        state     <= ST_W_ACCEPT;
                    end else if (s_arvalid) begin
                        req_id    <= s_arid;
                        req_addr  <= s_araddr;
                        req_len   <= s_arlen;
                        req_size  <= s_arsize;
                        req_burst <= s_arburst;
                        state     <= ST_R_LOOKUP;
                    end
                end
                //--------------------------------------------------
                ST_R_LOOKUP: begin
                    if (hit) state <= ST_R_HIT_LOOP;
                    else begin
                        fill_idx <= {WORD_BITS{1'b0}};
                        state    <= ST_R_MISS_AR;
                    end
                end
                //--------------------------------------------------
                ST_R_HIT_LOOP: begin
                    if (!hit) begin
                        // Burst crossed into an un-cached line: refill it first,
                        // then resume serving this beat (beat_cnt unchanged).
                        fill_idx <= {WORD_BITS{1'b0}};
                        state    <= ST_R_MISS_AR;
                    end else if (s_rready) begin
                        if (is_last_beat) begin
                            beat_cnt <= 8'h0;
                            state    <= ST_IDLE;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                        end
                    end
                end
                //--------------------------------------------------
                ST_R_MISS_AR: begin
                    if (m_arready) state <= ST_R_MISS_R;
                end
                //--------------------------------------------------
                ST_R_MISS_R: begin
                    // Sink the full-line refill: place each beat at its word
                    // slot in the line. On last beat, validate the line and go
                    // serve the upstream read from cache (ST_R_HIT_LOOP).
                    if (m_rvalid) begin
                        data_ram[line_index][fill_idx] <= m_rdata;
                        if (m_rlast || (fill_idx == WORDS_PER_LN-1)) begin
                            tag_ram[line_index]   <= line_tag;
                            valid_ram[line_index] <= 1'b1;
                            // Resume serving at the current beat (do NOT reset
                            // beat_cnt: a mid-burst refill must continue the
                            // upstream burst where it left off).
                            state                 <= ST_R_HIT_LOOP;
                        end else begin
                            fill_idx <= fill_idx + 1'b1;
                        end
                    end
                end
                //--------------------------------------------------
                ST_W_ACCEPT: begin
                    // Grab first W beat, then forward AW.
                    if (s_wvalid && !w_buf_valid) begin
                        w_buf_data  <= s_wdata;
                        w_buf_strb  <= s_wstrb;
                        w_buf_last  <= s_wlast;
                        w_buf_valid <= 1'b1;
                        // Write-through: update cache if hit at THIS beat's
                        // address. (beat_cnt starts at 0 for first W.)
                        if (valid_ram[beat_index] && (tag_ram[beat_index] == beat_tag)) begin
                            data_ram[beat_index][beat_wordoff] <= {
                                s_wstrb[3] ? s_wdata[31:24] : data_ram[beat_index][beat_wordoff][31:24],
                                s_wstrb[2] ? s_wdata[23:16] : data_ram[beat_index][beat_wordoff][23:16],
                                s_wstrb[1] ? s_wdata[15:8]  : data_ram[beat_index][beat_wordoff][15:8],
                                s_wstrb[0] ? s_wdata[7:0]   : data_ram[beat_index][beat_wordoff][7:0]
                            };
                        end
                        // Forward AW exactly once per burst. Subsequent beats
                        // stream straight to the W-forward state; a second AW
                        // would violate AXI (one AW per burst) and deadlock the
                        // downstream slave waiting for W beats.
                        state <= m_aw_sent ? ST_W_W_FWD : ST_W_AW_FWD;
                    end
                end
                //--------------------------------------------------
                ST_W_AW_FWD: begin
                    if (m_awready) begin
                        m_aw_sent <= 1'b1;
                        state     <= ST_W_W_FWD;
                    end
                end
                //--------------------------------------------------
                ST_W_W_FWD: begin
                    if (w_buf_valid && m_wready) begin
                        // Sent this beat.
                        w_buf_valid <= 1'b0;
                        if (w_buf_last) begin
                            state <= ST_W_B_WAIT;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                            state    <= ST_W_ACCEPT;   // grab next W beat
                        end
                    end
                end
                //--------------------------------------------------
                ST_W_B_WAIT: begin
                    if (m_bvalid) begin
                        m_b_rcvd <= 1'b1;
                        state    <= ST_W_RESP;
                    end
                end
                //--------------------------------------------------
                ST_W_RESP: begin
                    if (s_bready) begin
                        state    <= ST_IDLE;
                        beat_cnt <= 8'h0;
                    end
                end
                //--------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
