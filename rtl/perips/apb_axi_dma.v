// =============================================================================
// File Name: apb_axi_dma.v
// Design:    Multi-channel Scatter-Gather DMA — Commercial DUT Baseline (Phase 4C)
// Author:    Antigravity — Phase 4C
// Description:
//   Multi-channel DMA block under the single-outstanding AXI fabric contract.
//   Supports direct memory copy and scatter-gather descriptor chains with
//   deterministic error handling, busy reprogramming protection, bounded
//   descriptor depth, W1C status re-arm, and interrupt generation.
//
//   Single-beat word transfers on shared AXI master:
//     AWLEN/ARLEN = 0, AWSIZE/ARSIZE = 3'b010, WSTRB = 4'hF.
//
//   Descriptor format in memory (16 B, word-aligned):
//     +0x0  SRC (32b)
//     +0x4  DST (32b)
//     +0x8  LEN (32b, bytes; 4-byte aligned)
//     +0xC  NEXT (32b, phys addr of next descriptor, 0 = terminate)
//
//   Register layout:
//     Legacy v1 alias at 0x00..0x0C for ch0 (SRC, DST, LEN, CTRL).
//     v2 channel windows at 0x40 + channel * 0x40:
//       +0x00 CTRL       [0:EN, 1:SG_MODE, 2:INT_EN, 3:DONE_W1C, 4:ERR_W1C, 7:5:ERR_CODE]
//       +0x04 SRC        [31:0]
//       +0x08 DST        [31:0]
//       +0x0C LEN        [31:0]
//       +0x10 DESC_HEAD  [31:0]
//       +0x14 STATUS     [0:BUSY, 1:DONE, 2:ERR, 5:3:ERR_CODE]
//       +0x18 CUR_SRC    [31:0]
//       +0x1C CUR_DST    [31:0]
//       +0x20 CUR_LEN    [31:0]
//       +0x24 DESC_PTR   [31:0]
//     Global:
//       0x100 GLOBAL_CTRL[0]
//       0x104 IRQ_STATUS [N_CHANNELS-1:0]
// =============================================================================

module apb_axi_dma #(
    parameter N_CHANNELS      = 4,
    parameter ID_WIDTH        = 4,
    parameter MAX_DESCRIPTORS = 16
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    output reg  [ID_WIDTH-1:0] m_awid,
    output reg  [31:0]         m_awaddr,
    output wire [7:0]          m_awlen,
    output wire [2:0]          m_awsize,
    output wire [1:0]          m_awburst,
    output reg                 m_awvalid,
    input  wire                m_awready,

    output reg  [31:0]         m_wdata,
    output wire [3:0]          m_wstrb,
    output wire                m_wlast,
    output reg                 m_wvalid,
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
    output reg                 m_arvalid,
    input  wire                m_arready,

    input  wire [ID_WIDTH-1:0] m_rid,
    input  wire [31:0]         m_rdata,
    input  wire [1:0]          m_rresp,
    input  wire                m_rlast,
    input  wire                m_rvalid,
    output wire                m_rready,

    output wire [N_CHANNELS-1:0] ch_int
);

    localparam CH_W = $clog2(N_CHANNELS);

    // Error codes
    localparam ERR_NONE       = 3'd0;
    localparam ERR_ALIGN      = 3'd1;
    localparam ERR_AXI_READ   = 3'd2;
    localparam ERR_AXI_WRITE  = 3'd3;
    localparam ERR_DESC       = 3'd4;
    localparam ERR_DESC_LIMIT = 3'd5;

    assign pready    = 1'b1;
    assign pslverr   = 1'b0;
    assign m_awlen   = 8'd0;
    assign m_awsize  = 3'b010;
    assign m_awburst = 2'b01;
    assign m_wstrb   = 4'hF;
    assign m_wlast   = 1'b1;
    assign m_arlen   = 8'd0;
    assign m_arsize  = 3'b010;
    assign m_arburst = 2'b01;
    assign m_bready  = 1'b1;
    assign m_rready  = 1'b1;

    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;

    // Legacy v1 alias: channel 0 at 0x00..0x0C
    wire v1_alias = (paddr[11:4] == 8'h0);

    // Global CTRL & IRQ_STATUS
    reg global_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                            global_en <= 1'b1;
        else if (wr && paddr[11:0] == 12'h100) global_en <= pwdata[0];
    end

    // Per-channel CSRs
    reg [31:0] src_r       [N_CHANNELS-1:0];
    reg [31:0] dst_r       [N_CHANNELS-1:0];
    reg [31:0] len_r       [N_CHANNELS-1:0];
    reg [31:0] desc_head_r [N_CHANNELS-1:0];
    reg        en_r        [N_CHANNELS-1:0];
    reg        sg_mode_r   [N_CHANNELS-1:0];
    reg        int_en_r    [N_CHANNELS-1:0];
    reg        done_r      [N_CHANNELS-1:0];
    reg        err_r       [N_CHANNELS-1:0];
    reg [2:0]  err_code_r  [N_CHANNELS-1:0];
    reg        busy_r      [N_CHANNELS-1:0];
    reg [31:0] cur_src_r   [N_CHANNELS-1:0];
    reg [31:0] cur_dst_r   [N_CHANNELS-1:0];
    reg [31:0] cur_len_r   [N_CHANNELS-1:0];
    reg [31:0] cur_next_r  [N_CHANNELS-1:0];
    reg [31:0] desc_ptr_r  [N_CHANNELS-1:0];
    reg [4:0]  desc_cnt_r  [N_CHANNELS-1:0];

    integer c;

    // v2 channel decode
    wire [7:0] apb_ch       = (paddr[11:6] < 6'h1) ? 8'hFF : (paddr[11:6] - 8'd1);
    wire       apb_ch_valid = (paddr[11:6] >= 6'h1) && (paddr[11:6] < 6'h1 + N_CHANNELS[5:0]) &&
                              !(paddr[11:0] == 12'h100 || paddr[11:0] == 12'h104);

    // FSM States
    localparam ST_IDLE      = 4'd0;
    localparam ST_LOAD_SRC  = 4'd1;
    localparam ST_LOAD_DST  = 4'd2;
    localparam ST_LOAD_LEN  = 4'd3;
    localparam ST_LOAD_NEXT = 4'd4;
    localparam ST_DESC_CHK  = 4'd5;
    localparam ST_EXEC_R    = 4'd6;
    localparam ST_EXEC_W    = 4'd7;
    localparam ST_NEXT_CHK  = 4'd8;

    reg [3:0]  ch_state [N_CHANNELS-1:0];
    reg [31:0] read_buf [N_CHANNELS-1:0];
    reg        wait_r   [N_CHANNELS-1:0];
    reg        wait_aw  [N_CHANNELS-1:0];
    reg        wait_w   [N_CHANNELS-1:0];
    reg        wait_b   [N_CHANNELS-1:0];

    // Arbiter: pick lowest-numbered busy channel
    reg [CH_W-1:0] act_ch;
    reg            act_valid;
    integer k;
    always @(*) begin
        act_ch    = {CH_W{1'b0}};
        act_valid = 1'b0;
        for (k = 0; k < N_CHANNELS; k = k + 1) begin
            if (busy_r[k] && !act_valid) begin
                act_ch    = k[CH_W-1:0];
                act_valid = 1'b1;
            end
        end
    end

    // AXI master mux
    always @(*) begin
        m_arid    = 4'h5;
        m_araddr  = 32'h0;
        m_arvalid = 1'b0;
        m_awid    = 4'h5;
        m_awaddr  = 32'h0;
        m_awvalid = 1'b0;
        m_wvalid  = 1'b0;
        m_wdata   = 32'h0;
        if (act_valid) begin
            case (ch_state[act_ch])
                ST_LOAD_SRC:  begin m_araddr = desc_ptr_r[act_ch] + 32'h0;  m_arvalid = ~wait_r[act_ch]; end
                ST_LOAD_DST:  begin m_araddr = desc_ptr_r[act_ch] + 32'h4;  m_arvalid = ~wait_r[act_ch]; end
                ST_LOAD_LEN:  begin m_araddr = desc_ptr_r[act_ch] + 32'h8;  m_arvalid = ~wait_r[act_ch]; end
                ST_LOAD_NEXT: begin m_araddr = desc_ptr_r[act_ch] + 32'hC;  m_arvalid = ~wait_r[act_ch]; end
                ST_EXEC_R:    begin m_araddr = cur_src_r[act_ch];           m_arvalid = ~wait_r[act_ch]; end
                ST_EXEC_W:    begin
                    m_awaddr  = cur_dst_r[act_ch];
                    m_awvalid = ~wait_aw[act_ch] & ~wait_b[act_ch];
                    m_wdata   = read_buf[act_ch];
                    m_wvalid  = ~wait_w[act_ch] & ~wait_b[act_ch];
                end
                default: ;
            endcase
        end
    end

    // Channel FSM & CSR Configuration & Status Tracking
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
                ch_state[c]    <= ST_IDLE;
                busy_r[c]      <= 1'b0;
                done_r[c]      <= 1'b0;
                err_r[c]       <= 1'b0;
                err_code_r[c]  <= ERR_NONE;
                cur_src_r[c]   <= 32'h0;
                cur_dst_r[c]   <= 32'h0;
                cur_len_r[c]   <= 32'h0;
                cur_next_r[c]  <= 32'h0;
                desc_ptr_r[c]  <= 32'h0;
                desc_cnt_r[c]  <= 5'd0;
                read_buf[c]    <= 32'h0;
                wait_r[c]      <= 1'b0;
                wait_aw[c]     <= 1'b0;
                wait_w[c]      <= 1'b0;
                wait_b[c]      <= 1'b0;
            end
        end else begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                // -------------------------------------------------------------
                // 1. Channel FSM & Status Update
                // -------------------------------------------------------------
                if (ch_state[c] == ST_IDLE && en_r[c] && global_en && !busy_r[c]) begin
                    en_r[c]       <= 1'b0; // consume start request
                    done_r[c]     <= 1'b0;
                    err_r[c]      <= 1'b0;
                    err_code_r[c] <= ERR_NONE;
                    desc_cnt_r[c] <= 5'd0;

                    if (sg_mode_r[c]) begin
                        if (desc_head_r[c][1:0] != 2'b00) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_DESC;
                            ch_state[c]   <= ST_IDLE;
                        end else begin
                            busy_r[c]     <= 1'b1;
                            desc_ptr_r[c] <= desc_head_r[c];
                            ch_state[c]   <= ST_LOAD_SRC;
                        end
                    end else begin
                        if (src_r[c][1:0] != 2'b00 || dst_r[c][1:0] != 2'b00 || len_r[c][1:0] != 2'b00) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_ALIGN;
                            ch_state[c]   <= ST_IDLE;
                        end else begin
                            cur_src_r[c]  <= src_r[c];
                            cur_dst_r[c]  <= dst_r[c];
                            cur_len_r[c]  <= len_r[c];
                            cur_next_r[c] <= 32'h0;
                            if (len_r[c] == 32'h0) begin
                                busy_r[c]   <= 1'b0;
                                done_r[c]   <= 1'b1;
                                ch_state[c] <= ST_IDLE;
                            end else begin
                                busy_r[c]   <= 1'b1;
                                ch_state[c] <= ST_EXEC_R;
                            end
                        end
                    end
                end

                // Active channel execution
                if (act_valid && (act_ch[CH_W-1:0] == c[CH_W-1:0])) begin
                    if (m_arvalid && m_arready) wait_r[c] <= 1'b1;
                    if (m_awvalid && m_awready) wait_aw[c] <= 1'b1;
                    if (m_wvalid  && m_wready)  wait_w[c]  <= 1'b1;
                    if ((wait_aw[c] || (m_awvalid && m_awready)) &&
                        (wait_w[c]  || (m_wvalid  && m_wready))) begin
                        wait_b[c] <= 1'b1;
                    end
                    if (m_rvalid && wait_r[c]) begin
                        wait_r[c] <= 1'b0;
                        if (m_rresp != 2'b00) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_AXI_READ;
                            ch_state[c]   <= ST_IDLE;
                        end else begin
                            case (ch_state[c])
                                ST_LOAD_SRC:  begin cur_src_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_DST; end
                                ST_LOAD_DST:  begin cur_dst_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_LEN; end
                                ST_LOAD_LEN:  begin cur_len_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_NEXT; end
                                ST_LOAD_NEXT: begin
                                    cur_next_r[c] <= m_rdata;
                                    ch_state[c]   <= ST_DESC_CHK;
                                end
                                ST_EXEC_R: begin
                                    read_buf[c] <= m_rdata;
                                    ch_state[c] <= ST_EXEC_W;
                                end
                                default: ;
                            endcase
                        end
                    end
                    if (ch_state[c] == ST_DESC_CHK) begin
                        desc_cnt_r[c] <= desc_cnt_r[c] + 5'd1;
                        if (desc_cnt_r[c] >= MAX_DESCRIPTORS[4:0]) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_DESC_LIMIT;
                            ch_state[c]   <= ST_IDLE;
                        end else if (cur_src_r[c][1:0] != 2'b00 || cur_dst_r[c][1:0] != 2'b00 ||
                                     cur_len_r[c][1:0] != 2'b00 || cur_next_r[c][1:0] != 2'b00 ||
                                     (cur_len_r[c] == 32'h0 && cur_next_r[c] != 32'h0)) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_DESC;
                            ch_state[c]   <= ST_IDLE;
                        end else if (cur_len_r[c] == 32'h0 && cur_next_r[c] == 32'h0) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            ch_state[c]   <= ST_IDLE;
                        end else begin
                            ch_state[c]   <= ST_EXEC_R;
                        end
                    end
                    if (m_bvalid && wait_b[c] && ch_state[c] == ST_EXEC_W) begin
                        wait_aw[c] <= 1'b0;
                        wait_w[c]  <= 1'b0;
                        wait_b[c]  <= 1'b0;
                        if (m_bresp != 2'b00) begin
                            busy_r[c]     <= 1'b0;
                            done_r[c]     <= 1'b1;
                            err_r[c]      <= 1'b1;
                            err_code_r[c] <= ERR_AXI_WRITE;
                            ch_state[c]   <= ST_IDLE;
                        end else begin
                            cur_src_r[c] <= cur_src_r[c] + 32'd4;
                            cur_dst_r[c] <= cur_dst_r[c] + 32'd4;
                            if (cur_len_r[c] <= 32'd4) begin
                                ch_state[c] <= ST_NEXT_CHK;
                            end else begin
                                cur_len_r[c] <= cur_len_r[c] - 32'd4;
                                ch_state[c]  <= ST_EXEC_R;
                            end
                        end
                    end
                    if (ch_state[c] == ST_NEXT_CHK) begin
                        if (sg_mode_r[c] && cur_next_r[c] != 32'h0) begin
                            if (cur_next_r[c][1:0] != 2'b00) begin
                                busy_r[c]     <= 1'b0;
                                done_r[c]     <= 1'b1;
                                err_r[c]      <= 1'b1;
                                err_code_r[c] <= ERR_DESC;
                                ch_state[c]   <= ST_IDLE;
                            end else begin
                                desc_ptr_r[c] <= cur_next_r[c];
                                ch_state[c]   <= ST_LOAD_SRC;
                            end
                        end else begin
                            busy_r[c]   <= 1'b0;
                            done_r[c]   <= 1'b1;
                            ch_state[c] <= ST_IDLE;
                        end
                    end
                end

                // -------------------------------------------------------------
                // 2. APB CSR Write Handling (overrides FSM updates on SW write)
                // -------------------------------------------------------------
                if (wr && v1_alias && (c == 0)) begin
                    case (paddr[3:2])
                        2'h0: if (!busy_r[0]) src_r[0] <= pwdata;
                        2'h1: if (!busy_r[0]) dst_r[0] <= pwdata;
                        2'h2: if (!busy_r[0]) len_r[0] <= pwdata;
                        2'h3: begin
                            int_en_r[0] <= pwdata[1];
                            if (!busy_r[0]) begin
                                en_r[0]      <= pwdata[0];
                                sg_mode_r[0] <= 1'b0;
                            end
                            if (pwdata[2] || pwdata[0]) begin
                                done_r[0]     <= 1'b0;
                                err_r[0]      <= 1'b0;
                                err_code_r[0] <= ERR_NONE;
                            end
                        end
                        default: ;
                    endcase
                end else if (wr && apb_ch_valid && (apb_ch == c)) begin
                    case (paddr[5:2])
                        4'h0: begin
                            int_en_r[c] <= pwdata[2];
                            if (!busy_r[c]) begin
                                en_r[c]      <= pwdata[0];
                                sg_mode_r[c] <= pwdata[1];
                            end
                            if (pwdata[3]) done_r[c] <= 1'b0;
                            if (pwdata[4]) err_r[c]  <= 1'b0;
                            if (pwdata[3] || pwdata[4]) begin
                                if ((!done_r[c] || pwdata[3]) && (!err_r[c] || pwdata[4])) begin
                                    err_code_r[c] <= ERR_NONE;
                                end
                            end
                            if (pwdata[0] && !busy_r[c]) begin
                                done_r[c]     <= 1'b0;
                                err_r[c]      <= 1'b0;
                                err_code_r[c] <= ERR_NONE;
                            end
                        end
                        4'h1: if (!busy_r[c]) src_r[c]       <= pwdata;
                        4'h2: if (!busy_r[c]) dst_r[c]       <= pwdata;
                        4'h3: if (!busy_r[c]) len_r[c]       <= pwdata;
                        4'h4: if (!busy_r[c]) desc_head_r[c] <= pwdata;
                        default: ;
                    endcase
                end
            end
        end
    end

    // Interrupts
    genvar g;
    generate
        for (g = 0; g < N_CHANNELS; g = g + 1) begin: g_int
            assign ch_int[g] = int_en_r[g] & (done_r[g] | err_r[g]);
        end
    endgenerate

    // APB Read
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            if (v1_alias) begin
                case (paddr[3:2])
                    2'h0: prdata = src_r[0];
                    2'h1: prdata = dst_r[0];
                    2'h2: prdata = len_r[0];
                    2'h3: prdata = {27'h0, err_r[0], 1'b0, done_r[0], int_en_r[0], en_r[0] | busy_r[0]};
                    default: prdata = 32'h0;
                endcase
            end else if (paddr[11:0] == 12'h100) begin
                prdata = {31'h0, global_en};
            end else if (paddr[11:0] == 12'h104) begin
                prdata = {{(32-N_CHANNELS){1'b0}}, ch_int};
            end else if (apb_ch_valid) begin
                case (paddr[5:2])
                    4'h0: prdata = {24'h0, err_code_r[apb_ch], err_r[apb_ch], done_r[apb_ch],
                                    int_en_r[apb_ch], sg_mode_r[apb_ch], en_r[apb_ch]};
                    4'h1: prdata = src_r[apb_ch];
                    4'h2: prdata = dst_r[apb_ch];
                    4'h3: prdata = len_r[apb_ch];
                    4'h4: prdata = desc_head_r[apb_ch];
                    4'h5: prdata = {26'h0, err_code_r[apb_ch], err_r[apb_ch], done_r[apb_ch], busy_r[apb_ch]};
                    4'h6: prdata = cur_src_r[apb_ch];
                    4'h7: prdata = cur_dst_r[apb_ch];
                    4'h8: prdata = cur_len_r[apb_ch];
                    4'h9: prdata = desc_ptr_r[apb_ch];
                    default: prdata = 32'h0;
                endcase
            end
        end
    end

endmodule
