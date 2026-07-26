// =============================================================================
// File Name: l2_cache.v
// Design:    L2 Unified Cache — direct-mapped functional implementation
// Author:    Antigravity — Phase C
// Description:
//   Working L2 cache. This impl uses direct-mapped organization (1-way) as
//   a first-pass; the 8-way pseudo-LRU per spec §2.1 is a follow-up. The
//   external port set matches the scaffold so integration is drop-in.
//
//   Geometry (parameterized; defaults match spec §1 modulo way count):
//     * SIZE_BYTES = 32 KB (direct-mapped keeps the same 512 sets × 8 way
//       structural budget by using 1024 sets × 1 way for this pass)
//     * LINE_BYTES = 32
//     * INDEX_BITS = 10 (1024 sets)
//     * OFFSET_BITS = 5
//     * TAG_BITS = 17
//     * WORD_BITS = 3 (8 words per line)
//   Policy: Write-back + write-allocate, blocking (no MSHR).
//
//   FSM:
//     ST_IDLE     — wait for slave request
//     ST_LOOKUP   — tag compare
//     ST_HIT_R    — return read data from array
//     ST_HIT_W    — update data + dirty
//     ST_MISS_ALLOC — dirty check
//     ST_EVICT_AW / ST_EVICT_W — write dirty line back to downstream
//     ST_REFILL_AR / ST_REFILL_R — fetch new line from downstream
//     ST_REFILL_DONE — update tag/valid/data, return to service
//
//   Deferred:
//     * 8-way associative with pseudo-LRU (real spec)
//     * Non-blocking MSHR array
//     * Multi-outstanding downstream transactions
//     * Snoop (upstream coherence — port still tied off)
// =============================================================================

module l2_cache #(
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

    // Snoop (tied off — future coherence)
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

    localparam OFFSET_BITS  = 5;              // 32 B line → 5 bits
    localparam WORD_BITS    = OFFSET_BITS-2;  // 3 words-in-line index bits
    localparam WORDS_PER_LN = (1 << WORD_BITS);
    localparam INDEX_BITS   = $clog2(SIZE_BYTES / LINE_BYTES);   // 10 for 32 KB
    localparam NUM_SETS     = (1 << INDEX_BITS);
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    assign snoop_ack = snoop_valid;
    assign snoop_hit = 1'b0;

    // -------- Cache arrays --------
    reg [TAG_BITS-1:0]   tag_ram   [NUM_SETS-1:0];
    reg                  valid_ram [NUM_SETS-1:0];
    reg                  dirty_ram [NUM_SETS-1:0];
    reg [DATA_WIDTH-1:0] data_ram  [NUM_SETS-1:0][WORDS_PER_LN-1:0];

    integer i, j;
    initial begin
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            valid_ram[i] = 1'b0;
            dirty_ram[i] = 1'b0;
            tag_ram[i]   = {TAG_BITS{1'b0}};
            for (j = 0; j < WORDS_PER_LN; j = j + 1)
                data_ram[i][j] = 32'h0;
        end
    end

    // -------- FSM --------
    localparam ST_IDLE       = 4'd0;
    localparam ST_LOOKUP     = 4'd1;
    localparam ST_HIT_R      = 4'd2;
    localparam ST_HIT_W      = 4'd3;
    localparam ST_MISS_ALLOC = 4'd4;
    localparam ST_EVICT_AW   = 4'd5;
    localparam ST_EVICT_W    = 4'd6;
    localparam ST_EVICT_B    = 4'd7;
    localparam ST_REFILL_AR  = 4'd8;
    localparam ST_REFILL_R   = 4'd9;
    localparam ST_RESP_W     = 4'd10;
    localparam ST_RESP_R     = 4'd11;

    reg [3:0] state;

    // -------- Request latch --------
    reg                    req_is_write;
    reg [ID_WIDTH-1:0]     req_id;
    reg [ADDR_WIDTH-1:0]   req_addr;
    reg [7:0]              req_len;         // arlen / awlen (0-based)
    reg [7:0]              beat_cnt;        // current beat within burst
    reg [DATA_WIDTH-1:0]   req_wdata;
    reg [3:0]              req_wstrb;

    // beat_addr updates as burst progresses (INCR type, +4 per beat)
    wire [ADDR_WIDTH-1:0] beat_addr = req_addr + (beat_cnt << 2);
    wire [INDEX_BITS-1:0] req_index  = beat_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   req_tag    = beat_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    wire [WORD_BITS-1:0]  req_wordoff = beat_addr[OFFSET_BITS-1:2];

    wire hit = valid_ram[req_index] && (tag_ram[req_index] == req_tag);
    wire is_last_beat = (beat_cnt == req_len);

    // -------- Refill counters --------
    reg [WORD_BITS-1:0] fill_cnt;
    reg [WORD_BITS-1:0] evict_cnt;
    reg [ADDR_WIDTH-1:0] evict_addr;

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
        s_rdata   = data_ram[req_index][req_wordoff];
        s_rresp   = 2'b00;
        s_bresp   = 2'b00;

        // Single-beat refill/evict to match single-outstanding fabric contract.
        m_awvalid = 1'b0;
        m_awid    = req_id;
        m_awaddr  = evict_addr + (evict_cnt << 2);
        m_awlen   = 8'd0;
        m_awsize  = 3'b010;
        m_awburst = 2'b01;
        m_wvalid  = 1'b0;
        m_wdata   = data_ram[req_index][evict_cnt];
        m_wstrb   = 4'hF;
        m_wlast   = 1'b1;
        m_bready  = 1'b1;
        m_arvalid = 1'b0;
        m_arid    = req_id;
        m_araddr  = {req_addr[ADDR_WIDTH-1:OFFSET_BITS], {(OFFSET_BITS-2){1'b0}}, 2'b00}
                    + (fill_cnt << 2);
        m_arlen   = 8'd0;
        m_arsize  = 3'b010;
        m_arburst = 2'b01;
        m_rready  = 1'b1;

        case (state)
            ST_IDLE: begin
                s_awready = 1'b1;
                s_arready = ~s_awvalid;
            end
            ST_HIT_R: begin
                s_rvalid = 1'b1;
                s_rlast  = is_last_beat;
            end
            ST_HIT_W: begin
                s_wready = 1'b1;
            end
            ST_RESP_W: begin
                s_bvalid = 1'b1;
            end
            ST_EVICT_AW: begin
                m_awvalid = 1'b1;
            end
            ST_EVICT_W: begin
                m_wvalid = 1'b1;
            end
            ST_REFILL_AR: begin
                m_arvalid = 1'b1;
            end
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            req_is_write  <= 1'b0;
            req_id        <= {ID_WIDTH{1'b0}};
            req_addr      <= {ADDR_WIDTH{1'b0}};
            req_len       <= 8'h0;
            beat_cnt      <= 8'h0;
            req_wdata     <= {DATA_WIDTH{1'b0}};
            req_wstrb     <= 4'hF;
            fill_cnt      <= {WORD_BITS{1'b0}};
            evict_cnt     <= {WORD_BITS{1'b0}};
            evict_addr    <= {ADDR_WIDTH{1'b0}};
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_ram[i] <= 1'b0;
                dirty_ram[i] <= 1'b0;
            end
        end else begin
            case (state)
                ST_IDLE: begin
                    beat_cnt <= 8'h0;
                    if (s_awvalid) begin
                        req_is_write <= 1'b1;
                        req_id       <= s_awid;
                        req_addr     <= s_awaddr;
                        req_len      <= s_awlen;
                        state        <= ST_HIT_W;
                    end else if (s_arvalid) begin
                        req_is_write <= 1'b0;
                        req_id       <= s_arid;
                        req_addr     <= s_araddr;
                        req_len      <= s_arlen;
                        state        <= ST_LOOKUP;
                    end
                end

                ST_HIT_W: begin
                    if (s_wvalid) begin
                        req_wdata <= s_wdata;
                        req_wstrb <= s_wstrb;
                        state     <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    if (hit) begin
                        if (req_is_write) begin
                            // Byte-strobe merge
                            data_ram[req_index][req_wordoff] <= {
                                req_wstrb[3] ? req_wdata[31:24] : data_ram[req_index][req_wordoff][31:24],
                                req_wstrb[2] ? req_wdata[23:16] : data_ram[req_index][req_wordoff][23:16],
                                req_wstrb[1] ? req_wdata[15:8]  : data_ram[req_index][req_wordoff][15:8],
                                req_wstrb[0] ? req_wdata[7:0]   : data_ram[req_index][req_wordoff][7:0]
                            };
                            dirty_ram[req_index] <= 1'b1;
                            state <= ST_RESP_W;
                        end else begin
                            state <= ST_HIT_R;
                        end
                    end else begin
                        state <= ST_MISS_ALLOC;
                    end
                end

                ST_HIT_R: begin
                    if (s_rready) begin
                        if (is_last_beat) begin
                            state    <= ST_IDLE;
                            beat_cnt <= 8'h0;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                            // If the next beat lives in a different cache
                            // line (rare — L1 refill is usually line-sized
                            // and aligned) go re-lookup.
                            state <= ST_LOOKUP;
                        end
                    end
                end

                ST_RESP_W: begin
                    // Single B response for the entire write burst per AXI
                    // spec. Multi-beat write bursts across cache lines are
                    // not exercised in the current single-outstanding
                    // fabric contract; extend here when they land.
                    if (s_bready) begin
                        state    <= ST_IDLE;
                        beat_cnt <= 8'h0;
                    end
                end

                ST_MISS_ALLOC: begin
                    if (valid_ram[req_index] && dirty_ram[req_index]) begin
                        evict_addr <= {tag_ram[req_index], req_index, {OFFSET_BITS{1'b0}}};
                        evict_cnt  <= {WORD_BITS{1'b0}};
                        state      <= ST_EVICT_AW;
                    end else begin
                        state <= ST_REFILL_AR;
                    end
                end

                ST_EVICT_AW: begin
                    if (m_awready) state <= ST_EVICT_W;
                end

                ST_EVICT_W: begin
                    if (m_wready) state <= ST_EVICT_B;
                end

                ST_EVICT_B: begin
                    if (m_bvalid) begin
                        if (evict_cnt == WORDS_PER_LN - 1) begin
                            evict_cnt <= {WORD_BITS{1'b0}};
                            state     <= ST_REFILL_AR;
                        end else begin
                            evict_cnt <= evict_cnt + 1'b1;
                            state     <= ST_EVICT_AW;
                        end
                    end
                end

                ST_REFILL_AR: begin
                    if (m_arready) state <= ST_REFILL_R;
                end

                ST_REFILL_R: begin
                    if (m_rvalid) begin
                        data_ram[req_index][fill_cnt] <= m_rdata;
                        if (fill_cnt == WORDS_PER_LN - 1) begin
                            tag_ram[req_index]   <= req_tag;
                            valid_ram[req_index] <= 1'b1;
                            dirty_ram[req_index] <= 1'b0;
                            fill_cnt             <= {WORD_BITS{1'b0}};
                            state                <= ST_LOOKUP;
                        end else begin
                            fill_cnt <= fill_cnt + 1'b1;
                            state    <= ST_REFILL_AR;   // issue next single-beat AR
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
