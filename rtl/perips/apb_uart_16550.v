// =============================================================================
// File Name: apb_uart_16550.v
// Design:    PC16550D-compatible UART (functional subset)
// Author:    Antigravity — Phase D
// Description:
//   Subset of PC16550D spec targeted at bring-up / Linux 8250 driver on
//   8N1 @ programmable baud. See docs/block_specs/uart_16550_spec.md.
//   Standard 16550 register map (DLAB toggles DLL/DLM at 0x00/0x04).
//
//   Implemented this pass:
//     * Register map + DLAB latch
//     * TX / RX FIFOs (parameterized depth, default 16)
//     * 16× oversampled baud rate generator
//     * 8-bit data, 1 stop bit, no parity (8N1) fixed
//     * LSR (DR/OE/THRE/TEMT), IIR priority (RX>TX>Modem-stub)
//     * IER (ERBFI/ETBEI/ELSI)
//     * Loopback (MCR.LOOP)
//
//   Deferred to future pass (spec §1 remainder):
//     * 5/6/7-bit word, 1.5/2 stop bit, parity generation/check
//     * Framing / parity error detect, break send/detect
//     * Full modem status (DSR/DCD/RI/CTS delta bits)
//     * Auto-RTS/CTS hardware flow control
//     * FIFO trigger levels (currently: IRQ on any non-empty RX)
//
//   Existing apb_uart.v (simulation stub with $write) is kept untouched.
// =============================================================================

module apb_uart_16550 #(
    parameter TX_FIFO_DEPTH = 16,
    parameter RX_FIFO_DEPTH = 16
) (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [4:0]  paddr,
    input  wire [3:0]  pstrb,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Serial pins
    output wire        uart_tx,
    input  wire        uart_rx,

    // Modem (tied stubs when unused)
    output wire        uart_rts_n,
    input  wire        uart_cts_n,
    output wire        uart_dtr_n,
    input  wire        uart_dsr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    // Combined interrupt
    output wire        irq
);

    // --------- APB glue ----------------------------------------------------
    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire   wr_stb  = psel & penable & pwrite;
    wire   rd_stb  = psel & penable & ~pwrite;

    // --------- Registers ---------------------------------------------------
    reg [7:0]  ier_r;      // 0x04, DLAB=0
    reg [7:0]  fcr_r;      // 0x08 write-only
    reg [7:0]  lcr_r;      // 0x0C
    reg [7:0]  mcr_r;      // 0x10
    reg [7:0]  scr_r;      // 0x1C
    reg [7:0]  dll_r;      // 0x00, DLAB=1
    reg [7:0]  dlm_r;      // 0x04, DLAB=1
    wire       dlab = lcr_r[7];

    // --------- TX FIFO -----------------------------------------------------
    reg  [7:0] tx_fifo [TX_FIFO_DEPTH-1:0];
    reg  [$clog2(TX_FIFO_DEPTH):0] tx_wr, tx_rd;
    wire       tx_empty = (tx_wr == tx_rd);
    wire       tx_full  = ((tx_wr[$clog2(TX_FIFO_DEPTH)-1:0] == tx_rd[$clog2(TX_FIFO_DEPTH)-1:0]) &&
                           (tx_wr[$clog2(TX_FIFO_DEPTH)] != tx_rd[$clog2(TX_FIFO_DEPTH)]));

    // --------- RX FIFO -----------------------------------------------------
    reg  [7:0] rx_fifo [RX_FIFO_DEPTH-1:0];
    reg  [$clog2(RX_FIFO_DEPTH):0] rx_wr, rx_rd;
    wire       rx_empty = (rx_wr == rx_rd);
    wire       rx_full  = ((rx_wr[$clog2(RX_FIFO_DEPTH)-1:0] == rx_rd[$clog2(RX_FIFO_DEPTH)-1:0]) &&
                           (rx_wr[$clog2(RX_FIFO_DEPTH)] != rx_rd[$clog2(RX_FIFO_DEPTH)]));
    reg        overrun_r;

    // --------- Baud-rate generator (16× oversample) ------------------------
    wire [15:0] divisor = ({dlm_r, dll_r} == 16'h0) ? 16'h1 : {dlm_r, dll_r};
    reg  [15:0] baud_cnt;
    reg         baud16_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt    <= 16'h0;
            baud16_tick <= 1'b0;
        end else if (baud_cnt >= divisor - 1) begin
            baud_cnt    <= 16'h0;
            baud16_tick <= 1'b1;
        end else begin
            baud_cnt    <= baud_cnt + 1'b1;
            baud16_tick <= 1'b0;
        end
    end

    // --------- TX shifter (8N1) --------------------------------------------
    // States: 0=idle, 1=start, 2..9=data, 10=stop
    reg [3:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [3:0]  tx_bit_ctr; // 0..15 count within a bit time
    reg        tx_line;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= 4'd0;
            tx_shift   <= 8'h0;
            tx_bit_ctr <= 4'd0;
            tx_line    <= 1'b1;
            tx_rd      <= 0;
        end else begin
            if (tx_state == 4'd0) begin
                tx_line <= 1'b1;
                if (!tx_empty) begin
                    tx_shift   <= tx_fifo[tx_rd[$clog2(TX_FIFO_DEPTH)-1:0]];
                    tx_rd      <= tx_rd + 1'b1;
                    tx_state   <= 4'd1;
                    tx_bit_ctr <= 4'd0;
                end
            end else if (baud16_tick) begin
                if (tx_bit_ctr == 4'd15) begin
                    tx_bit_ctr <= 4'd0;
                    case (tx_state)
                        4'd1: begin tx_line <= tx_shift[0]; tx_state <= 4'd2; end
                        4'd2: begin tx_line <= tx_shift[1]; tx_state <= 4'd3; end
                        4'd3: begin tx_line <= tx_shift[2]; tx_state <= 4'd4; end
                        4'd4: begin tx_line <= tx_shift[3]; tx_state <= 4'd5; end
                        4'd5: begin tx_line <= tx_shift[4]; tx_state <= 4'd6; end
                        4'd6: begin tx_line <= tx_shift[5]; tx_state <= 4'd7; end
                        4'd7: begin tx_line <= tx_shift[6]; tx_state <= 4'd8; end
                        4'd8: begin tx_line <= tx_shift[7]; tx_state <= 4'd9; end
                        4'd9: begin tx_line <= 1'b1;        tx_state <= 4'd10; end // stop
                        4'd10:begin tx_state <= 4'd0; end
                        default: tx_state <= 4'd0;
                    endcase
                    if (tx_state == 4'd1) tx_line <= 1'b0; // enter start bit at 15→0
                end else begin
                    tx_bit_ctr <= tx_bit_ctr + 1'b1;
                end
            end
        end
    end
    assign uart_tx = tx_line;

    // --------- RX shifter --------------------------------------------------
    wire rx_line = mcr_r[4] ? tx_line : uart_rx; // loopback
    reg  rx_line_sync1, rx_line_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_line_sync1 <= 1'b1;
            rx_line_sync2 <= 1'b1;
        end else begin
            rx_line_sync1 <= rx_line;
            rx_line_sync2 <= rx_line_sync1;
        end
    end

    reg [3:0] rx_state;
    reg [7:0] rx_shift;
    reg [3:0] rx_bit_ctr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= 4'd0;
            rx_shift   <= 8'h0;
            rx_bit_ctr <= 4'd0;
            rx_wr      <= 0;
            overrun_r  <= 1'b0;
        end else begin
            if (rx_state == 4'd0) begin
                if (!rx_line_sync2) begin  // start bit detected
                    rx_state   <= 4'd1;
                    rx_bit_ctr <= 4'd8;    // half bit time to align to middle
                end
            end else if (baud16_tick) begin
                if (rx_bit_ctr == 4'd15) begin
                    rx_bit_ctr <= 4'd0;
                    case (rx_state)
                        4'd1: begin rx_shift[0] <= rx_line_sync2; rx_state <= 4'd2; end
                        4'd2: begin rx_shift[1] <= rx_line_sync2; rx_state <= 4'd3; end
                        4'd3: begin rx_shift[2] <= rx_line_sync2; rx_state <= 4'd4; end
                        4'd4: begin rx_shift[3] <= rx_line_sync2; rx_state <= 4'd5; end
                        4'd5: begin rx_shift[4] <= rx_line_sync2; rx_state <= 4'd6; end
                        4'd6: begin rx_shift[5] <= rx_line_sync2; rx_state <= 4'd7; end
                        4'd7: begin rx_shift[6] <= rx_line_sync2; rx_state <= 4'd8; end
                        4'd8: begin rx_shift[7] <= rx_line_sync2; rx_state <= 4'd9; end
                        4'd9: begin
                            if (rx_line_sync2 && !rx_full) begin
                                rx_fifo[rx_wr[$clog2(RX_FIFO_DEPTH)-1:0]] <= rx_shift;
                                rx_wr <= rx_wr + 1'b1;
                            end else if (!rx_full == 1'b0) begin
                                overrun_r <= 1'b1;
                            end
                            rx_state <= 4'd0;
                        end
                        default: rx_state <= 4'd0;
                    endcase
                end else begin
                    rx_bit_ctr <= rx_bit_ctr + 1'b1;
                end
            end
        end
    end

    // --------- FIFO write / TX push from APB -------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr  <= 0;
            ier_r  <= 8'h0;
            fcr_r  <= 8'h0;
            lcr_r  <= 8'h03;    // default 8N1
            mcr_r  <= 8'h0;
            scr_r  <= 8'h0;
            dll_r  <= 8'h1;
            dlm_r  <= 8'h0;
        end else if (wr_stb) begin
            case (paddr[4:2])
                3'b000: begin // 0x00
                    if (dlab) dll_r <= pwdata[7:0];
                    else if (!tx_full) begin
                        tx_fifo[tx_wr[$clog2(TX_FIFO_DEPTH)-1:0]] <= pwdata[7:0];
                        tx_wr <= tx_wr + 1'b1;
                    end
                end
                3'b001: begin // 0x04
                    if (dlab) dlm_r <= pwdata[7:0];
                    else      ier_r <= pwdata[7:0];
                end
                3'b010: fcr_r <= pwdata[7:0];   // 0x08 FCR
                3'b011: lcr_r <= pwdata[7:0];   // 0x0C
                3'b100: mcr_r <= pwdata[7:0];   // 0x10
                3'b111: scr_r <= pwdata[7:0];   // 0x1C
                default: ;
            endcase
            if (paddr[4:2] == 3'b010 && pwdata[1]) rx_wr <= rx_rd; // clear RX FIFO
            if (paddr[4:2] == 3'b010 && pwdata[2]) tx_wr <= tx_rd; // clear TX FIFO
        end
    end

    // --------- APB read + FIFO pop -----------------------------------------
    // LSR: bit0 DR, bit1 OE, bit5 THRE, bit6 TEMT
    wire [7:0] lsr = {1'b0, tx_empty && tx_state == 4'd0, tx_empty, 3'b000, overrun_r, ~rx_empty};

    // IIR: bit0 = pending (0 = int pending)
    wire rx_int   = ier_r[0] & ~rx_empty;
    wire tx_int   = ier_r[1] & tx_empty;
    wire [7:0] iir = rx_int ? 8'hC4 :  // RX data available
                     tx_int ? 8'hC2 :  // TX empty
                              8'hC1;   // no int pending

    assign irq = rx_int | tx_int;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_rd     <= 0;
            prdata    <= 32'h0;
        end else if (rd_stb) begin
            case (paddr[4:2])
                3'b000: begin // RBR / DLL
                    if (dlab) prdata <= {24'h0, dll_r};
                    else begin
                        prdata <= {24'h0, rx_empty ? 8'h0 : rx_fifo[rx_rd[$clog2(RX_FIFO_DEPTH)-1:0]]};
                        if (!rx_empty) rx_rd <= rx_rd + 1'b1;
                    end
                end
                3'b001: prdata <= {24'h0, dlab ? dlm_r : ier_r};
                3'b010: begin prdata <= {24'h0, iir}; overrun_r <= 1'b0; end
                3'b011: prdata <= {24'h0, lcr_r};
                3'b100: prdata <= {24'h0, mcr_r};
                3'b101: prdata <= {24'h0, lsr};
                3'b110: prdata <= {24'h0,
                                   ~uart_dcd_n, ~uart_ri_n, ~uart_dsr_n, ~uart_cts_n & ~mcr_r[4],
                                   4'h0};
                3'b111: prdata <= {24'h0, scr_r};
                default: prdata <= 32'h0;
            endcase
        end
    end

    // --------- Modem outputs -----------------------------------------------
    assign uart_rts_n = ~mcr_r[1];
    assign uart_dtr_n = ~mcr_r[0];

endmodule
