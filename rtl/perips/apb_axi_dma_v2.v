// =============================================================================
// File Name: apb_axi_dma_v2.v
// Design:    Multi-channel Scatter-Gather DMA — full implementation
// Author:    Antigravity — Phase D
// Description:
//   Replaces the scaffold with a working multi-channel DMA. AXI transfer
//   engine, scatter-gather descriptor chain load, and channel arbitration
//   all functional. Not yet integrated (apb_axi_dma.v remains in DUT).
//
//   Data movement: single-beat word transfers on shared AXI master (matches
//   current single-outstanding fabric contract). Burst-mode upgrade tracked
//   in Phase C multi-outstanding work.
//
//   Descriptor format in memory (16 B, little-endian, word-aligned):
//     +0x0  SRC (32b)
//     +0x4  DST (32b)
//     +0x8  LEN (32b, bytes; multiple of 4)
//     +0xC  NEXT (32b, phys addr of next descriptor, 0 = terminate)
//
//   FSM per channel:
//     IDLE            → wait for enable
//     LOAD_SRC        → AR to descriptor+0x0
//     LOAD_DST        → AR to descriptor+0x4
//     LOAD_LEN        → AR to descriptor+0x8
//     LOAD_NEXT       → AR to descriptor+0xC
//     EXEC_R          → AR to cur_src, wait rvalid
//     EXEC_W          → AW+W to cur_dst, wait bvalid
//     NEXT_CHECK      → if SG && cur_next != 0 → LOAD_SRC; else DONE
//     DONE            → set done_r, IDLE
// =============================================================================

module apb_axi_dma_v2 #(
    parameter N_CHANNELS = 4,
    parameter ID_WIDTH   = 4
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

    // v1-compat alias: channel 0 accessible at 0x00-0x0C with v1 register
    // order (SRC/DST/LEN/CTRL) and self-clearing CTRL[0]. v2 channels
    // continue at 0x40+. This lets existing v1 firmware and UVM
    // sequences target ch0 without change.
    wire v1_alias = (paddr[11:4] == 8'h0);

    // Global CTRL moved to 0x100 to free 0x00 range for v1 alias.
    reg global_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                             global_en <= 1'b1;   // default on (v1 legacy)
        else if (wr && paddr[11:0] == 12'h100)  global_en <= pwdata[0];
    end

    // Per-channel CSRs
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
    reg [31:0] desc_ptr_r [N_CHANNELS-1:0];  // current descriptor base addr

    integer c;

    // v2 channels: ch1 at 0x80, ch2 at 0xC0, etc. (0x00-0x3F is v1 alias
    // for ch0, 0x40-0x7F is v2 ch0, 0x100 is global CTRL.)
    wire [7:0] apb_ch       = (paddr[11:6] < 6'h1) ? 8'hFF : (paddr[11:6] - 8'd1);
    wire       apb_ch_valid = (paddr[11:6] >= 6'h1) && (paddr[11:6] < 6'h1 + N_CHANNELS[5:0]);

    // Channel state
    localparam ST_IDLE      = 4'd0;
    localparam ST_LOAD_SRC  = 4'd1;
    localparam ST_LOAD_DST  = 4'd2;
    localparam ST_LOAD_LEN  = 4'd3;
    localparam ST_LOAD_NEXT = 4'd4;
    localparam ST_EXEC_R    = 4'd5;
    localparam ST_EXEC_W    = 4'd6;
    localparam ST_NEXT_CHK  = 4'd7;
    localparam ST_DONE      = 4'd8;

    reg [3:0] ch_state [N_CHANNELS-1:0];
    reg [31:0] read_buf [N_CHANNELS-1:0];  // buffer between R and W
    reg        wait_r   [N_CHANNELS-1:0];  // AR fired, waiting for R
    reg        wait_aw  [N_CHANNELS-1:0];  // AW fired, waiting for W handshake
    reg        wait_w   [N_CHANNELS-1:0];  // W fired,  waiting for B
    reg        wait_b   [N_CHANNELS-1:0];  // both AW+W done, waiting for BVALID

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

    // AXI master mux: driven by active channel's state
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
                    // Separate wait flags for AW vs W so we don't re-drive
                    // AWVALID after handshake (AXI protocol violation).
                    m_awaddr  = cur_dst_r[act_ch];
                    m_awvalid = ~wait_aw[act_ch] & ~wait_b[act_ch];
                    m_wdata   = read_buf[act_ch];
                    m_wvalid  = ~wait_w[act_ch] & ~wait_b[act_ch];
                end
                default: ;
            endcase
        end
    end

    // Config write from APB
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
        end else if (wr && v1_alias) begin
            // v1 alias: ch0 CSRs at 0x00-0x0C, v1 register order and
            // CTRL semantics (bit0 EN, bit1 INT_EN, bit2 DONE W1C).
            case (paddr[3:2])
                2'h0: src_r[0]     <= pwdata;
                2'h1: dst_r[0]     <= pwdata;
                2'h2: len_r[0]     <= pwdata;
                2'h3: begin
                    en_r[0]      <= pwdata[0];   // 1 → start; auto-clears on done
                    int_en_r[0]  <= pwdata[1];
                    sg_mode_r[0] <= 1'b0;        // v1 has no SG mode
                    // pwdata[2] = W1C DONE handled in FSM block below.
                    // v1 semantics: writing CTRL[0]=1 (start) also implicitly
                    // clears previous DONE so channel can re-arm without an
                    // explicit W1C between back-to-back transfers.
                    // (done_r cleared in FSM block via v1-alias W1C below,
                    // triggered when pwdata[0]=1)
                end
                default: ;
            endcase
`ifdef DMA_V2_DEBUG
            $display("[%0t] DMA v1-alias WR paddr[3:2]=%h pwdata=%08h", $time, paddr[3:2], pwdata);
`endif
        end else if (wr && apb_ch_valid) begin
            case (paddr[5:2])
                4'h0: begin
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

    // Channel FSM + AXI handshake tracking
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                ch_state[c]   <= ST_IDLE;
                busy_r[c]     <= 1'b0;
                done_r[c]     <= 1'b0;
                err_r[c]      <= 1'b0;
                cur_src_r[c]  <= 32'h0;
                cur_dst_r[c]  <= 32'h0;
                cur_len_r[c]  <= 32'h0;
                cur_next_r[c] <= 32'h0;
                desc_ptr_r[c] <= 32'h0;
                read_buf[c]   <= 32'h0;
                wait_r[c]     <= 1'b0;
                wait_aw[c]    <= 1'b0;
                wait_w[c]     <= 1'b0;
                wait_b[c]     <= 1'b0;
            end
        end else begin
            for (c = 0; c < N_CHANNELS; c = c + 1) begin
                // Start
                if (ch_state[c] == ST_IDLE && en_r[c] && global_en && !done_r[c] && !busy_r[c]) begin
                    busy_r[c] <= 1'b1;
                    if (sg_mode_r[c]) begin
                        desc_ptr_r[c] <= desc_head_r[c];
                        ch_state[c]   <= ST_LOAD_SRC;
                    end else begin
                        cur_src_r[c]  <= src_r[c];
                        cur_dst_r[c]  <= dst_r[c];
                        cur_len_r[c]  <= len_r[c];
                        cur_next_r[c] <= 32'h0;
                        ch_state[c]   <= (len_r[c] == 32'h0) ? ST_DONE : ST_EXEC_R;
                    end
`ifdef DMA_V2_DEBUG
                    $display("[%0t] DMA ch%0d START src=%h dst=%h len=%h", $time, c, src_r[c], dst_r[c], len_r[c]);
`endif
                end
`ifdef DMA_V2_DEBUG
                if (ch_state[c] == ST_DONE) begin
                    $display("[%0t] DMA ch%0d DONE (en will auto-clear)", $time, c);
                end
`endif

                // Only the active channel drives AXI, so only it advances on handshakes
                if (act_valid && (act_ch[CH_W-1:0] == c[CH_W-1:0])) begin
                    // Capture AR handshake (set wait_r so m_arvalid drops next cycle)
                    if (m_arvalid && m_arready) begin
                        wait_r[c] <= 1'b1;
                    end
                    // Independent AW / W handshake capture. Once both done
                    // → wait_b (waiting for BVALID).
                    if (m_awvalid && m_awready) wait_aw[c] <= 1'b1;
                    if (m_wvalid  && m_wready)  wait_w[c]  <= 1'b1;
                    if ((wait_aw[c] || (m_awvalid && m_awready)) &&
                        (wait_w[c]  || (m_wvalid  && m_wready))) begin
                        wait_b[c] <= 1'b1;
                    end

                    // R data arrival — clears wait_r and advances state
                    if (m_rvalid && wait_r[c]) begin
                        wait_r[c] <= 1'b0;
                        case (ch_state[c])
                            ST_LOAD_SRC:  begin cur_src_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_DST; end
                            ST_LOAD_DST:  begin cur_dst_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_LEN; end
                            ST_LOAD_LEN:  begin cur_len_r[c]  <= m_rdata; ch_state[c] <= ST_LOAD_NEXT; end
                            ST_LOAD_NEXT: begin
                                cur_next_r[c] <= m_rdata;
                                ch_state[c]   <= (cur_len_r[c] == 32'h0) ? ST_NEXT_CHK : ST_EXEC_R;
                            end
                            ST_EXEC_R: begin
                                read_buf[c] <= m_rdata;
                                if (m_rresp != 2'b00) err_r[c] <= 1'b1;
                                ch_state[c] <= ST_EXEC_W;
                            end
                            default: ;
                        endcase
                    end

                    // B response arrival — clears all write flags, advances EXEC_W
                    if (m_bvalid && wait_b[c] && ch_state[c] == ST_EXEC_W) begin
                        wait_aw[c] <= 1'b0;
                        wait_w[c]  <= 1'b0;
                        wait_b[c]  <= 1'b0;
                        if (m_bresp != 2'b00) err_r[c] <= 1'b1;
                        cur_src_r[c] <= cur_src_r[c] + 32'd4;
                        cur_dst_r[c] <= cur_dst_r[c] + 32'd4;
                        if (cur_len_r[c] <= 32'd4) begin
                            ch_state[c] <= ST_NEXT_CHK;
                        end else begin
                            cur_len_r[c] <= cur_len_r[c] - 32'd4;
                            ch_state[c]  <= ST_EXEC_R;
                        end
                    end

                    if (ch_state[c] == ST_NEXT_CHK) begin
                        if (sg_mode_r[c] && cur_next_r[c] != 32'h0) begin
                            desc_ptr_r[c] <= cur_next_r[c];
                            ch_state[c]   <= ST_LOAD_SRC;
                        end else begin
                            ch_state[c] <= ST_DONE;
                        end
                    end

                    if (ch_state[c] == ST_DONE) begin
                        busy_r[c]   <= 1'b0;
                        done_r[c]   <= 1'b1;
                        ch_state[c] <= ST_IDLE;
                        // v1-compat: ch0 EN self-clears on done.
                        if (c == 0) en_r[0] <= 1'b0;
                    end
                end

                // v2 APB W1C on done / err via ch CTRL[3]/[4]
                if (wr && apb_ch_valid && apb_ch == c && paddr[5:2] == 4'h0) begin
                    if (pwdata[3]) done_r[c] <= 1'b0;
                    if (pwdata[4]) err_r[c]  <= 1'b0;
                end
                // v1-compat CTRL W1C on bit 2 (v1 DONE bit) — either
                // explicit W1C by software OR implicit clear when software
                // writes CTRL[0]=1 to start a new transfer.
                if (wr && v1_alias && paddr[3:2] == 2'h3 && c == 0 &&
                    (pwdata[2] || pwdata[0])) begin
                    done_r[0] <= 1'b0;
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

    // APB read
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            if (v1_alias) begin
                // v1 alias: ch0 CSRs at 0x00-0x0C, v1 register order and
                // CTRL bit map (bit0 EN, bit1 INT_EN, bit2 DONE).
                case (paddr[3:2])
                    2'h0: prdata = src_r[0];
                    2'h1: prdata = dst_r[0];
                    2'h2: prdata = len_r[0];
                    2'h3: prdata = {29'h0, done_r[0], int_en_r[0], en_r[0]};
                    default: prdata = 32'h0;
                endcase
            end else if (paddr[11:0] == 12'h100) begin
                prdata = {31'h0, global_en};
            end else if (paddr[11:0] == 12'h104) begin
                prdata = 32'h0;
                for (c = 0; c < N_CHANNELS; c = c + 1)
                    prdata[c] = int_en_r[c] & done_r[c];
            end else if (apb_ch_valid) begin
                case (paddr[5:2])
                    4'h0: prdata = {27'h0, err_r[apb_ch], done_r[apb_ch],
                                    int_en_r[apb_ch], sg_mode_r[apb_ch], en_r[apb_ch]};
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
