// =============================================================================
// File Name: apb_axi_dma_v2.v
// Design:    Multi-channel Scatter-Gather DMA (Phase D scaffold)
// Author:    Antigravity — Phase D
// Description:
//   Multi-channel DMA replacing the single-channel apb_axi_dma.v. Each
//   channel supports either simple block transfer (LEN bytes contiguous)
//   or scatter-gather via a linked descriptor list in memory. A fixed-
//   priority arbiter (ch0 = highest) shares one AXI master port across
//   channels. Existing single-channel DMA is kept until block-level UVM
//   verification of v2 is complete.
//
//   Descriptor format (16 B, next=0 marks list end):
//     +0x0  SRC   (32b)
//     +0x4  DST   (32b)
//     +0x8  LEN   (32b, bytes; must be multiple of 4)
//     +0xC  NEXT  (32b, phys addr of next descriptor, 0 = terminate)
//
//   Per-channel register block (each channel at 0x40 offset, N ≤ 8):
//     +0x00 CTRL       [0]=EN, [1]=SG_MODE, [2]=INT_EN
//                      [3]=DONE (W1C), [4]=ERR (W1C)
//     +0x04 SRC_ADDR   (used when SG_MODE=0)
//     +0x08 DST_ADDR
//     +0x0C LEN
//     +0x10 DESC_HEAD  (SG_MODE=1: first descriptor addr)
//     +0x14 STATUS     RO: [0]=busy, [1]=done, [2]=err
//     +0x18 CUR_SRC    RO: currently executing src
//     +0x1C CUR_DST    RO: currently executing dst
//
//   Global regs at 0x000:
//     +0x00 GLOBAL_CTRL  [0]=EN_ALL
//     +0x04 GLOBAL_INT   RO bitmap of channel-level INT_EN & done
//
//   AXI data path: single-beat word transfers initially (matches current
//   single-outstanding fabric contract). Burst mode = Phase C+ upgrade.
// =============================================================================

module apb_axi_dma_v2 #(
    parameter N_CHANNELS = 4,
    parameter ID_WIDTH   = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave (channels laid out on 0x40 stride starting from 0x40)
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // AXI master (shared across channels)
    output reg  [ID_WIDTH-1:0] m_awid,
    output reg  [31:0]         m_awaddr,
    output wire [7:0]          m_awlen,
    output wire [2:0]          m_awsize,
    output wire [1:0]          m_awburst,
    output wire                m_awvalid,
    input  wire                m_awready,

    output reg  [31:0]         m_wdata,
    output wire [3:0]          m_wstrb,
    output wire                m_wlast,
    output wire                m_wvalid,
    input  wire                m_wready,

    input  wire [ID_WIDTH-1:0] m_bid,
    input  wire [1:0]          m_bresp,
    input  wire                m_bvalid,
    output wire                m_bready,

    output reg  [ID_WIDTH-1:0] m_arid,
    output reg  [31:0]         m_araddr,
    output wire [7:0]          m_arlen,
    output wire [2:0]          m_arsize,
    output wire [1:0]          m_arburst,
    output wire                m_arvalid,
    input  wire                m_arready,

    input  wire [ID_WIDTH-1:0] m_rid,
    input  wire [31:0]         m_rdata,
    input  wire [1:0]          m_rresp,
    input  wire                m_rlast,
    input  wire                m_rvalid,
    output wire                m_rready,

    // Per-channel interrupts (OR-ed downstream to VIC)
    output wire [N_CHANNELS-1:0] ch_int
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    assign m_awlen   = 8'd0;
    assign m_awsize  = 3'b010;
    assign m_awburst = 2'b01;
    assign m_wstrb   = 4'hF;
    assign m_wlast   = 1'b1;
    assign m_arlen   = 8'd0;
    assign m_arsize  = 3'b010;
    assign m_arburst = 2'b01;

    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;

    // ---------------- Global regs ----------------
    reg global_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                              global_en <= 1'b0;
        else if (wr && paddr[11:0] == 12'h000)   global_en <= pwdata[0];
    end

    // ---------------- Per-channel register file ----------------
    reg [31:0] src_r      [N_CHANNELS-1:0];
    reg [31:0] dst_r      [N_CHANNELS-1:0];
    reg [31:0] len_r      [N_CHANNELS-1:0];
    reg [31:0] desc_head_r[N_CHANNELS-1:0];
    reg        en_r       [N_CHANNELS-1:0];
    reg        sg_mode_r  [N_CHANNELS-1:0];
    reg        int_en_r   [N_CHANNELS-1:0];
    reg        done_r     [N_CHANNELS-1:0];
    reg        err_r      [N_CHANNELS-1:0];
    reg        busy_r     [N_CHANNELS-1:0];
    reg [31:0] cur_src_r  [N_CHANNELS-1:0];
    reg [31:0] cur_dst_r  [N_CHANNELS-1:0];
    reg [31:0] cur_len_r  [N_CHANNELS-1:0];
    reg [31:0] cur_next_r [N_CHANNELS-1:0];

    integer c;

    // APB write decode: channel index = paddr[11:6] - 1  (ch0 starts at 0x40)
    wire [7:0] apb_ch = (paddr[11:6] == 6'h0) ? 8'hFF : (paddr[11:6] - 8'd1);
    wire       apb_ch_valid = (paddr[11:6] != 6'h0) && (apb_ch < N_CHANNELS[7:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                src_r[c]       <= 32'h0;
                dst_r[c]       <= 32'h0;
                len_r[c]       <= 32'h0;
                desc_head_r[c] <= 32'h0;
                en_r[c]        <= 1'b0;
                sg_mode_r[c]   <= 1'b0;
                int_en_r[c]    <= 1'b0;
            end
        end else if (wr && apb_ch_valid) begin
            case (paddr[5:2])
                4'h0: begin // CTRL
                    en_r[apb_ch]      <= pwdata[0];
                    sg_mode_r[apb_ch] <= pwdata[1];
                    int_en_r[apb_ch]  <= pwdata[2];
                end
                4'h1: src_r[apb_ch]       <= pwdata;
                4'h2: dst_r[apb_ch]       <= pwdata;
                4'h3: len_r[apb_ch]       <= pwdata;
                4'h4: desc_head_r[apb_ch] <= pwdata;
                default: ;
            endcase
        end
    end

    // ---------------- Fixed-priority arbiter (ch0 highest) ----------------
    reg  [$clog2(N_CHANNELS+1)-1:0] active_ch;
    reg                              active_ch_valid;
    reg [N_CHANNELS-1:0]             req_pending;

    // Request = channel enabled + not busy + not done
    integer k;
    always @(*) begin
        req_pending = {N_CHANNELS{1'b0}};
        for (k = 0; k < N_CHANNELS; k = k + 1) begin
            req_pending[k] = en_r[k] & ~busy_r[k] & ~done_r[k] & global_en;
        end
    end

    // ---------------- Per-channel FSM ----------------
    // Simplified: LOAD_DESC (SG only) → EXEC (word-by-word) → NEXT/DONE
    localparam ST_IDLE      = 3'd0;
    localparam ST_LOAD_DESC = 3'd1;
    localparam ST_EXEC_R    = 3'd2;
    localparam ST_EXEC_W    = 3'd3;
    localparam ST_NEXT      = 3'd4;
    localparam ST_DONE      = 3'd5;

    reg [2:0]  ch_state [N_CHANNELS-1:0];
    reg [1:0]  desc_word_ctr [N_CHANNELS-1:0]; // scatter-gather desc load progress
    reg [31:0] read_word_buf [N_CHANNELS-1:0];

    // AXI issue: only one channel drives at a time
    // Skeleton: this arbiter picks first pending channel each cycle
    always @(*) begin
        active_ch       = {$clog2(N_CHANNELS+1){1'b0}};
        active_ch_valid = 1'b0;
        for (k = 0; k < N_CHANNELS; k = k + 1) begin
            if (busy_r[k] && !active_ch_valid) begin
                active_ch       = k[$clog2(N_CHANNELS+1)-1:0];
                active_ch_valid = 1'b1;
            end
        end
    end

    // AXI master mux (skeleton: not fully wired to per-channel FSM state; a
    // future integration pass will drive m_arvalid / m_awvalid from
    // ch_state[active_ch] transitions).
    assign m_arvalid = 1'b0;
    assign m_awvalid = 1'b0;
    assign m_wvalid  = 1'b0;
    assign m_bready  = 1'b1;
    assign m_rready  = 1'b1;

    always @(*) begin
        m_arid   = 4'h5;
        m_araddr = 32'h0;
        m_awid   = 4'h5;
        m_awaddr = 32'h0;
        m_wdata  = 32'h0;
        if (active_ch_valid) begin
            m_araddr = cur_src_r[active_ch];
            m_awaddr = cur_dst_r[active_ch];
        end
    end

    // ---------------- Per-channel state advance (skeleton) ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                ch_state[c]      <= ST_IDLE;
                busy_r[c]        <= 1'b0;
                done_r[c]        <= 1'b0;
                err_r[c]         <= 1'b0;
                cur_src_r[c]     <= 32'h0;
                cur_dst_r[c]     <= 32'h0;
                cur_len_r[c]     <= 32'h0;
                cur_next_r[c]    <= 32'h0;
                desc_word_ctr[c] <= 2'h0;
                read_word_buf[c] <= 32'h0;
            end
        end else begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                case (ch_state[c])
                    ST_IDLE: begin
                        if (req_pending[c]) begin
                            busy_r[c] <= 1'b1;
                            if (sg_mode_r[c]) begin
                                cur_next_r[c]    <= desc_head_r[c];
                                desc_word_ctr[c] <= 2'h0;
                                ch_state[c]      <= ST_LOAD_DESC;
                            end else begin
                                cur_src_r[c] <= src_r[c];
                                cur_dst_r[c] <= dst_r[c];
                                cur_len_r[c] <= len_r[c];
                                ch_state[c]  <= ST_EXEC_R;
                            end
                        end
                    end
                    // The following states will drive the AXI master port
                    // once the integration pass wires them up. Currently
                    // they are placeholder transitions to keep FSM well
                    // formed and lint-clean.
                    ST_LOAD_DESC: ch_state[c] <= ST_EXEC_R;
                    ST_EXEC_R:    ch_state[c] <= ST_EXEC_W;
                    ST_EXEC_W:    ch_state[c] <= ST_NEXT;
                    ST_NEXT: begin
                        if (sg_mode_r[c] && cur_next_r[c] != 32'h0) begin
                            ch_state[c] <= ST_LOAD_DESC;
                        end else begin
                            ch_state[c] <= ST_DONE;
                        end
                    end
                    ST_DONE: begin
                        busy_r[c]   <= 1'b0;
                        done_r[c]   <= 1'b1;
                        ch_state[c] <= ST_IDLE;
                    end
                    default: ch_state[c] <= ST_IDLE;
                endcase

                // W1C on done/err
                if (wr && apb_ch_valid && apb_ch == c && paddr[5:2] == 4'h0) begin
                    if (pwdata[3]) done_r[c] <= 1'b0;
                    if (pwdata[4]) err_r[c]  <= 1'b0;
                end
            end
        end
    end

    // ---------------- Interrupt ----------------
    genvar g;
    generate
        for (g = 0; g < N_CHANNELS; g = g + 1) begin: g_int
            assign ch_int[g] = int_en_r[g] & (done_r[g] | err_r[g]);
        end
    endgenerate

    // ---------------- APB read ----------------
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            if (paddr[11:6] == 6'h0) begin
                case (paddr[5:2])
                    4'h0: prdata = {31'h0, global_en};
                    4'h1: begin
                        prdata = 32'h0;
                        for (c = 0; c < N_CHANNELS; c = c + 1)
                            prdata[c] = int_en_r[c] & done_r[c];
                    end
                    default: prdata = 32'h0;
                endcase
            end else if (apb_ch_valid) begin
                case (paddr[5:2])
                    4'h0: prdata = {27'h0, err_r[apb_ch], done_r[apb_ch], int_en_r[apb_ch], sg_mode_r[apb_ch], en_r[apb_ch]};
                    4'h1: prdata = src_r[apb_ch];
                    4'h2: prdata = dst_r[apb_ch];
                    4'h3: prdata = len_r[apb_ch];
                    4'h4: prdata = desc_head_r[apb_ch];
                    4'h5: prdata = {29'h0, err_r[apb_ch], done_r[apb_ch], busy_r[apb_ch]};
                    4'h6: prdata = cur_src_r[apb_ch];
                    4'h7: prdata = cur_dst_r[apb_ch];
                    default: prdata = 32'h0;
                endcase
            end
        end
    end

endmodule
