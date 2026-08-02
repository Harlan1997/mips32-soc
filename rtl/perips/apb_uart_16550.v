// =============================================================================
// File Name: apb_uart_16550.v
// Design:    PC16550D-compatible UART — current DUT baseline
// Author:    Antigravity — Phase 4E Commercial Hardening
// Description:
//   PC16550D-compatible UART baseline per docs/block_specs/uart_16550_spec.md.
//   Integrated in soc_peripheral_subsystem.v.
//
//   Features:
//     * Standard 16550 register map + DLAB divisor access
//     * TX/RX FIFOs (parameterized depth, default 16 entries)
//     * 16× oversampled baud rate generator (16-bit divisor)
//     * Word length 5/6/7/8 (LCR[1:0]), Stop bits 1/1.5-2 (LCR[2]), Parity (LCR[5:3])
//     * Break send (LCR[6]) & Parity / framing / break detect (LSR[2:4])
//     * FIFO trigger levels: 1 / 4 / 8 / 14 chars (FCR[7:6])
//     * FIFO disabled (single-byte) compatibility mode
//     * RX character timeout interrupt when below threshold
//     * Auto-RTS (MCR[5]) & Modem status delta bits (MSR[3:0]) cleared on MSR read
//     * Loopback mode (MCR[4]): TX→RX, DTR→DSR, RTS→CTS, OUT1→RI, OUT2→DCD
//     * Interrupt priority: RX line status > RX data/timeout > TX empty > Modem
//     * Byte strobe handling: pstrb[0..3] byte lane selection
//     * pready=1, pslverr=0, unsupported reads return zero
// =============================================================================

module apb_uart_16550 #(
    parameter TX_FIFO_DEPTH = 16,
    parameter RX_FIFO_DEPTH = 16
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [4:0]  paddr,
    input  wire [3:0]  pstrb,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    output wire        uart_tx,
    input  wire        uart_rx,

    output wire        uart_rts_n,
    input  wire        uart_cts_n,
    output wire        uart_dtr_n,
    input  wire        uart_dsr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    output wire        irq,
    output wire        rx_irq,
    output wire        tx_irq
);

    localparam TX_AW = $clog2(TX_FIFO_DEPTH);
    localparam RX_AW = $clog2(RX_FIFO_DEPTH);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    wire [7:0] write_data = pstrb[0] ? pwdata[7:0]   :
                            pstrb[1] ? pwdata[15:8]  :
                            pstrb[2] ? pwdata[23:16] :
                            pstrb[3] ? pwdata[31:24] : pwdata[7:0];

    wire wr_stb = psel & penable & pwrite & (|pstrb);
    wire rd_stb = psel & penable & ~pwrite;

    // ================= registers =================
    reg [7:0] ier_r;
    reg [7:0] fcr_r;
    reg [7:0] lcr_r;
    reg [7:0] mcr_r;
    reg [7:0] scr_r;
    reg [7:0] dll_r, dlm_r;

    wire dlab = lcr_r[7];

    // LCR fields
    wire [1:0] wls      = lcr_r[1:0];        // 00=5, 01=6, 10=7, 11=8 bits
    wire       stb2     = lcr_r[2];          // 1.5/2 stops when 1
    wire       pen      = lcr_r[3];
    wire       eps      = lcr_r[4];
    wire       sp       = lcr_r[5];          // stick parity
    wire       brk_send = lcr_r[6];

    // FCR fields
    wire       fifo_en    = fcr_r[0];
    wire [1:0] rx_trigger = fcr_r[7:6];   // 00=1, 01=4, 10=8, 11=14 (16-FIFO)

    // ================= TX FIFO / Holding =================
    reg  [7:0] tx_fifo [TX_FIFO_DEPTH-1:0];
    reg  [TX_AW:0] tx_wr, tx_rd;
    wire tx_empty = (tx_wr == tx_rd);
    wire [TX_AW:0] tx_count = tx_wr - tx_rd;
    wire tx_full  = fifo_en ? ((tx_wr[TX_AW-1:0] == tx_rd[TX_AW-1:0]) && (tx_wr[TX_AW] != tx_rd[TX_AW]))
                            : (tx_count >= 1);

    // ================= RX FIFO / Holding (data + error flags) =================
    // Each entry: {parity_err, framing_err, break, 8-bit data}
    reg [10:0] rx_fifo [RX_FIFO_DEPTH-1:0];
    reg  [RX_AW:0] rx_wr, rx_rd;
    wire rx_empty = (rx_wr == rx_rd);
    wire [RX_AW:0] rx_count = rx_wr - rx_rd;
    wire rx_full  = fifo_en ? ((rx_wr[RX_AW-1:0] == rx_rd[RX_AW-1:0]) && (rx_wr[RX_AW] != rx_rd[RX_AW]))
                            : (rx_count >= 1);
    reg  overrun_r;
    wire lsr_read_pulse;

    // Trigger threshold value based on FCR
    reg [3:0] rx_trig_level;
    always @(*) begin
        case (rx_trigger)
            2'b00: rx_trig_level = 4'd1;
            2'b01: rx_trig_level = 4'd4;
            2'b10: rx_trig_level = 4'd8;
            2'b11: rx_trig_level = 4'd14;
        endcase
    end

    // ================= Baud generator (16×) =================
    wire [15:0] divisor = ({dlm_r, dll_r} == 16'h0) ? 16'h1 : {dlm_r, dll_r};
    reg  [15:0] baud_cnt;
    reg         baud16_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 16'h0; baud16_tick <= 1'b0;
        end else if (baud_cnt >= divisor - 1) begin
            baud_cnt <= 16'h0; baud16_tick <= 1'b1;
        end else begin
            baud_cnt <= baud_cnt + 1'b1; baud16_tick <= 1'b0;
        end
    end

    // Width in bits per char, based on WLS
    reg [3:0] data_bits;
    always @(*) begin
        case (wls)
            2'b00: data_bits = 4'd5;
            2'b01: data_bits = 4'd6;
            2'b10: data_bits = 4'd7;
            2'b11: data_bits = 4'd8;
        endcase
    end

    // ================= TX shifter =================
    localparam TX_IDLE   = 3'd0;
    localparam TX_START  = 3'd1;
    localparam TX_DATA   = 3'd2;
    localparam TX_PARITY = 3'd3;
    localparam TX_STOP1  = 3'd4;
    localparam TX_STOP2  = 3'd5;

    reg [2:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [3:0]  tx_bit_ctr;
    reg [3:0]  tx_bit_idx;
    reg        tx_line;
    reg        tx_parity_bit;

    function automatic pop_parity(input [7:0] data, input [3:0] width);
        integer k; reg p;
        begin
            p = 1'b0;
            for (k = 0; k < 8; k = k + 1)
                if (k < width) p = p ^ data[k];
            pop_parity = p;
        end
    endfunction

    wire cts_n_int = mcr_r[4] ? ~mcr_r[1] : uart_cts_n;
    // MCR[5] enables hardware CTS gating.  When asserted, a high (inactive)
    // CTS input pauses TX between frames; reset/default operation is unchanged.
    wire tx_cts_allowed = !mcr_r[5] || !cts_n_int;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state      <= TX_IDLE;
            tx_shift      <= 8'h0;
            tx_bit_ctr    <= 4'h0;
            tx_bit_idx    <= 4'h0;
            tx_line       <= 1'b1;
            tx_parity_bit <= 1'b0;
        end else begin
            if (brk_send) tx_line <= 1'b0;

            if (tx_state == TX_IDLE) begin
                if (!brk_send) tx_line <= 1'b1;
                if (!tx_empty && !brk_send && tx_cts_allowed) begin
                    tx_shift   <= tx_fifo[tx_rd[TX_AW-1:0]];
                    tx_state   <= TX_START;
                    tx_bit_ctr <= 4'h0;
                    tx_bit_idx <= 4'h0;
                    tx_line    <= 1'b0;  // start bit
                    if (sp) tx_parity_bit <= ~eps;
                    else    tx_parity_bit <= pop_parity(tx_fifo[tx_rd[TX_AW-1:0]], data_bits) ^ ~eps;
                end
            end else if (baud16_tick) begin
                if (tx_bit_ctr == 4'd15) begin
                    tx_bit_ctr <= 4'h0;
                    case (tx_state)
                        TX_START: begin
                            tx_line    <= tx_shift[0];
                            tx_bit_idx <= 4'h1;
                            tx_state   <= TX_DATA;
                        end
                        TX_DATA: begin
                            if (tx_bit_idx < data_bits) begin
                                tx_line    <= tx_shift[tx_bit_idx];
                                tx_bit_idx <= tx_bit_idx + 1'b1;
                            end else begin
                                if (pen) begin
                                    tx_line  <= tx_parity_bit;
                                    tx_state <= TX_PARITY;
                                end else begin
                                    tx_line  <= 1'b1;
                                    tx_state <= TX_STOP1;
                                end
                            end
                        end
                        TX_PARITY: begin
                            tx_line  <= 1'b1;
                            tx_state <= TX_STOP1;
                        end
                        TX_STOP1: begin
                            if (stb2) begin
                                tx_line  <= 1'b1;
                                tx_state <= TX_STOP2;
                            end else begin
                                tx_state <= TX_IDLE;
                            end
                        end
                        TX_STOP2: begin
                            tx_state <= TX_IDLE;
                        end
                        default: tx_state <= TX_IDLE;
                    endcase
                end else begin
                    tx_bit_ctr <= tx_bit_ctr + 1'b1;
                end
            end
        end
    end
    assign uart_tx = tx_line;

    // ================= TX FIFO Pointers =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr <= 0;
        end else if (wr_stb && paddr[4:2] == 3'b010 && write_data[2]) begin
            tx_wr <= 0;
        end else if (wr_stb && paddr[4:2] == 3'b000 && !dlab && !tx_full) begin
            tx_fifo[tx_wr[TX_AW-1:0]] <= write_data;
            tx_wr <= tx_wr + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd <= 0;
        end else if (wr_stb && paddr[4:2] == 3'b010 && write_data[2]) begin
            tx_rd <= 0;
        end else if (tx_state == TX_IDLE && !tx_empty && !brk_send && tx_cts_allowed) begin
            tx_rd <= tx_rd + 1'b1;
        end
    end

    // ================= RX shifter & FIFO Write =================
    wire rx_pin      = mcr_r[4] ? tx_line   : uart_rx;
    // cts_n_int is declared with the TX flow-control contract above.
    wire dsr_n_int   = mcr_r[4] ? ~mcr_r[0] : uart_dsr_n;
    wire dcd_n_int   = mcr_r[4] ? ~mcr_r[3] : uart_dcd_n;
    wire ri_n_int    = mcr_r[4] ? ~mcr_r[2] : uart_ri_n;

    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_sync1 <= 1'b1; rx_sync2 <= 1'b1; end
        else        begin rx_sync1 <= rx_pin; rx_sync2 <= rx_sync1; end
    end

    localparam RX_IDLE   = 3'd0;
    localparam RX_START  = 3'd1;
    localparam RX_DATA   = 3'd2;
    localparam RX_PARITY = 3'd3;
    localparam RX_STOP   = 3'd4;

    reg [2:0] rx_state;
    reg [7:0] rx_shift;
    reg [3:0] rx_bit_ctr;
    reg [3:0] rx_bit_idx;
    reg       rx_parity_r;
    reg       rx_err_par, rx_err_fram, rx_brk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_shift    <= 8'h0;
            rx_bit_ctr  <= 4'h0;
            rx_bit_idx  <= 4'h0;
            rx_parity_r <= 1'b0;
            rx_wr       <= 0;
            overrun_r   <= 1'b0;
            rx_err_par  <= 1'b0;
            rx_err_fram <= 1'b0;
            rx_brk      <= 1'b0;
        end else if (wr_stb && paddr[4:2] == 3'b010 && write_data[1]) begin
            rx_wr     <= 0;
            overrun_r <= 1'b0;
        end else begin
            if (lsr_read_pulse) overrun_r <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (!rx_sync2) begin
                        rx_state    <= RX_START;
                        rx_bit_ctr  <= 4'd8;
                        rx_bit_idx  <= 4'd0;
                        rx_err_par  <= 1'b0;
                        rx_err_fram <= 1'b0;
                        rx_brk      <= 1'b0;
                    end
                end
                default: if (baud16_tick) begin
                    if (rx_bit_ctr == 4'd15) begin
                        rx_bit_ctr <= 4'h0;
                        case (rx_state)
                            RX_START: begin
                                if (!rx_sync2) begin
                                    rx_state <= RX_DATA;
                                end else begin
                                    rx_state <= RX_IDLE;
                                end
                            end
                            RX_DATA: begin
                                rx_shift[rx_bit_idx] <= rx_sync2;
                                if (rx_bit_idx == data_bits - 1) begin
                                    rx_parity_r <= 1'b0;
                                    if (pen) rx_state <= RX_PARITY;
                                    else     rx_state <= RX_STOP;
                                end else begin
                                    rx_bit_idx <= rx_bit_idx + 1'b1;
                                end
                            end
                            RX_PARITY: begin
                                if (sp) begin
                                    if (rx_sync2 != ~eps) rx_err_par <= 1'b1;
                                end else begin
                                    if (rx_sync2 != (pop_parity(rx_shift, data_bits) ^ ~eps))
                                        rx_err_par <= 1'b1;
                                end
                                rx_state <= RX_STOP;
                            end
                            RX_STOP: begin
                                if (!rx_sync2) rx_err_fram <= 1'b1;
                                if (rx_shift == 8'h0 && (!rx_sync2 || rx_err_fram)) rx_brk <= 1'b1;
                                if (!rx_full) begin
                                    rx_fifo[rx_wr[RX_AW-1:0]] <= {rx_err_par, !rx_sync2, (rx_shift == 8'h0 && (!rx_sync2 || rx_err_fram)), rx_shift};
                                    rx_wr <= rx_wr + 1'b1;
                                end else begin
                                    overrun_r <= 1'b1;
                                end
                                rx_state <= RX_IDLE;
                            end
                            default: rx_state <= RX_IDLE;
                        endcase
                    end else begin
                        rx_bit_ctr <= rx_bit_ctr + 1'b1;
                    end
                end
            endcase
        end
    end

    // ================= RX FIFO Read Pointer =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_rd <= 0;
        end else if (wr_stb && paddr[4:2] == 3'b010 && write_data[1]) begin
            rx_rd <= 0;
        end else if (rd_stb && paddr[4:2] == 3'b000 && !dlab && !rx_empty) begin
            rx_rd <= rx_rd + 1'b1;
        end
    end

    // ================= RX Timeout Counter =================
    wire [15:0] char_ticks = (16 * (1 + data_bits + (pen ? 4'd1 : 4'd0) + (stb2 ? 4'd2 : 4'd1)));
    wire [15:0] timeout_limit = 4 * char_ticks;
    reg  [15:0] timeout_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 16'h0;
        end else if ((rd_stb && paddr[4:2] == 3'b000 && !dlab) ||
                     (wr_stb && paddr[4:2] == 3'b010 && write_data[1]) ||
                     !fifo_en || rx_empty) begin
            timeout_cnt <= 16'h0;
        end else if (baud16_tick) begin
            if (fifo_en && (rx_count > 0) && (rx_count < rx_trig_level)) begin
                if (rx_state != RX_IDLE) begin
                    timeout_cnt <= 16'h0;
                end else if (timeout_cnt < timeout_limit) begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                end
            end else begin
                timeout_cnt <= 16'h0;
            end
        end
    end

    wire rx_timeout_int = ier_r[0] & fifo_en & (rx_count > 0) & (rx_count < rx_trig_level) & (timeout_cnt >= timeout_limit);

    // ================= Write Registers =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ier_r <= 8'h0;
            fcr_r <= 8'h0;
            lcr_r <= 8'h03;   // default 8N1
            mcr_r <= 8'h0;
            scr_r <= 8'h0;
            dll_r <= 8'h1;
            dlm_r <= 8'h0;
        end else if (wr_stb) begin
            case (paddr[4:2])
                3'b000: if (dlab) dll_r <= write_data;
                3'b001: if (dlab) dlm_r <= write_data;
                        else      ier_r <= write_data[3:0];
                3'b010: fcr_r <= {write_data[7:6], 5'b00000, write_data[0]};
                3'b011: lcr_r <= write_data;
                3'b100: mcr_r <= write_data;
                3'b111: scr_r <= write_data;
                default: ;
            endcase
        end
    end

    // ================= APB read & FIFO pop =================
    wire [7:0] rx_head      = rx_empty ? 8'h0 : rx_fifo[rx_rd[RX_AW-1:0]][7:0];
    wire       rx_head_par  = rx_empty ? 1'b0 : rx_fifo[rx_rd[RX_AW-1:0]][10];
    wire       rx_head_fram = rx_empty ? 1'b0 : rx_fifo[rx_rd[RX_AW-1:0]][9];
    wire       rx_head_brk  = rx_empty ? 1'b0 : rx_fifo[rx_rd[RX_AW-1:0]][8];

    // RFE calculation (LSR[7])
    reg rx_fifo_has_err;
    integer i_err;
    reg [RX_AW:0] err_pos;
    always @(*) begin
        rx_fifo_has_err = 1'b0;
        if (fifo_en) begin
            for (i_err = 0; i_err < RX_FIFO_DEPTH; i_err = i_err + 1) begin
                if (i_err < rx_count) begin
                    err_pos = rx_rd + i_err;
                    if (|rx_fifo[err_pos[RX_AW-1:0]][10:8])
                        rx_fifo_has_err = 1'b1;
                end
            end
        end
    end

    // LSR bits
    wire [7:0] lsr = { rx_fifo_has_err,                        // 7: RFE
                       tx_empty && (tx_state == TX_IDLE),       // 6: TEMT
                       tx_empty,                               // 5: THRE
                       rx_head_brk,                            // 4: BI
                       rx_head_fram,                           // 3: FE
                       rx_head_par,                            // 2: PE
                       overrun_r,                              // 1: OE
                       ~rx_empty };                            // 0: DR

    // Interrupt identification
    wire rx_line_err_int  = ier_r[2] & (rx_head_par | rx_head_fram | rx_head_brk | overrun_r);
    wire rx_data_trig_int = ier_r[0] & (rx_count >= (fifo_en ? rx_trig_level : 4'd1));
    wire tx_empty_int     = ier_r[1] & tx_empty;

    // Delta on modem status
    reg cts_n_prev, dsr_n_prev, dcd_n_prev, ri_n_prev;
    reg d_cts, d_dsr, d_dcd, d_ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cts_n_prev <= 1'b1; dsr_n_prev <= 1'b1; dcd_n_prev <= 1'b1; ri_n_prev <= 1'b1;
            d_cts <= 0; d_dsr <= 0; d_dcd <= 0; d_ri <= 0;
        end else begin
            cts_n_prev <= cts_n_int;
            dsr_n_prev <= dsr_n_int;
            dcd_n_prev <= dcd_n_int;
            ri_n_prev  <= ri_n_int;
            if (cts_n_int != cts_n_prev) d_cts <= 1'b1;
            if (dsr_n_int != dsr_n_prev) d_dsr <= 1'b1;
            if (dcd_n_int != dcd_n_prev) d_dcd <= 1'b1;
            if (~ri_n_int  &  ri_n_prev) d_ri  <= 1'b1;  // trailing edge only for RI
            if (rd_stb && paddr[4:2] == 3'b110) begin
                d_cts <= 1'b0; d_dsr <= 1'b0; d_dcd <= 1'b0; d_ri <= 1'b0;
            end
        end
    end
    wire modem_int = ier_r[3] & (d_cts | d_dsr | d_dcd | d_ri);

    wire [1:0] iir_fifo_bits = fifo_en ? 2'b11 : 2'b00;
    wire [7:0] iir = rx_line_err_int  ? {iir_fifo_bits, 2'b00, 4'b0110} :
                     rx_data_trig_int ? {iir_fifo_bits, 2'b00, 4'b0100} :
                     rx_timeout_int   ? {iir_fifo_bits, 2'b00, 4'b1100} :
                     tx_empty_int     ? {iir_fifo_bits, 2'b00, 4'b0010} :
                     modem_int        ? {iir_fifo_bits, 2'b00, 4'b0000} :
                                        {iir_fifo_bits, 2'b00, 4'b0001};

    assign rx_irq = rx_line_err_int | rx_data_trig_int | rx_timeout_int;
    assign tx_irq = tx_empty_int;
    assign irq = rx_irq | tx_irq | modem_int;

    // Combinational APB read
    assign lsr_read_pulse = rd_stb && (paddr[4:2] == 3'b101);
    always @(*) begin
        prdata = 32'h0;
        if (rd_stb) begin
            case (paddr[4:2])
                3'b000: prdata = {24'h0, dlab ? dll_r : rx_head};
                3'b001: prdata = {24'h0, dlab ? dlm_r : {4'h0, ier_r[3:0]}};
                3'b010: prdata = {24'h0, iir};
                3'b011: prdata = {24'h0, lcr_r};
                3'b100: prdata = {24'h0, mcr_r};
                3'b101: prdata = {24'h0, lsr};
                3'b110: prdata = {24'h0,
                                  ~dcd_n_int, ~ri_n_int, ~dsr_n_int, ~cts_n_int,
                                  d_dcd, d_ri, d_dsr, d_cts};
                3'b111: prdata = {24'h0, scr_r};
                default: prdata = 32'h0;
            endcase
        end
    end

    // ================= Modem outputs =================
    wire auto_rts_deassert = mcr_r[5] & (rx_count >= rx_trig_level);
    assign uart_rts_n = ~mcr_r[1] | auto_rts_deassert;
    assign uart_dtr_n = ~mcr_r[0];

endmodule
