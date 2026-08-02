// Vendor-neutral QSPI command/FIFO behavioral contract.
//
// This block is intentionally independent of axi_spi_flash and soc_top. It
// provides the APB command API and pin-level SPI transaction behavior needed
// to verify the production command contract before a vendor PHY/pad wrapper is
// available. XIP/AXI integration, flash timing, and electrical behavior remain
// outside this model.

module qspi_cmd_behavioral #(
    parameter TX_FIFO_DEPTH = 32,
    parameter RX_FIFO_DEPTH = 32,
    parameter LUT_SLOTS     = 8,
    parameter CS_COUNT      = 4,
    parameter integer COMMAND_TIMEOUT_CYCLES = 4096
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    psel,
    input  wire                    penable,
    input  wire                    pwrite,
    input  wire [11:0]             paddr,
    input  wire [3:0]              pstrb,
    input  wire [31:0]             pwdata,
    output reg  [31:0]             prdata,
    output wire                    pready,
    output wire                    pslverr,

    output wire                    spi_sclk,
    output wire [CS_COUNT-1:0]     spi_cs_n,
    output wire [3:0]              spi_io_o,
    output wire [3:0]              spi_io_oe,
    input  wire [3:0]              spi_io_i,
    output wire                    irq
);

    localparam [11:0] A_CTRL       = 12'h000;
    localparam [11:0] A_STATUS     = 12'h004;
    localparam [11:0] A_CLK_DIV    = 12'h008;
    localparam [11:0] A_CS_CTRL    = 12'h00c;
    localparam [11:0] A_IRQ_EN     = 12'h010;
    localparam [11:0] A_IRQ_STATUS = 12'h014;
    localparam [11:0] A_TIMEOUT    = 12'h018;
    localparam [11:0] A_LUT_BASE   = 12'h020;
    localparam [11:0] A_XIP_INDEX  = 12'h044;
    localparam [11:0] A_CMD_TRIG   = 12'h100;
    localparam [11:0] A_CMD_ADDR   = 12'h104;
    localparam [11:0] A_CMD_LEN    = 12'h108;
    localparam [11:0] A_TX_DATA    = 12'h110;
    localparam [11:0] A_RX_DATA    = 12'h114;
    localparam [11:0] A_FIFO_STAT  = 12'h118;

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_CMD   = 3'd1;
    localparam [2:0] ST_ADDR  = 3'd2;
    localparam [2:0] ST_MODE  = 3'd3;
    localparam [2:0] ST_DUMMY = 3'd4;
    localparam [2:0] ST_DATA  = 3'd5;

    localparam integer TX_AW = $clog2(TX_FIFO_DEPTH);
    localparam integer RX_AW = $clog2(RX_FIFO_DEPTH);

    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;
    wire tx_push = wr && (paddr == A_TX_DATA);
    wire rx_pop  = rd && (paddr == A_RX_DATA);
    wire soft_reset = wr && (paddr == A_CTRL) && pwdata[1];
    // CTRL[2] is a write-one command abort pulse and is not retained.
    wire abort_cmd = wr && (paddr == A_CTRL) && pwdata[2];

    reg [31:0] ctrl_r;
    reg [15:0] clk_div_r;
    reg [31:0] cs_ctrl_r;
    reg [31:0] irq_en_r;
    reg [31:0] timeout_limit_r;
    reg [31:0] cmd_addr_r;
    reg [15:0] cmd_len_r;
    reg [2:0]  xip_index_r;
    reg [31:0] lut_r [0:LUT_SLOTS-1];

    reg [31:0] tx_fifo [0:TX_FIFO_DEPTH-1];
    reg [31:0] rx_fifo [0:RX_FIFO_DEPTH-1];
    reg [TX_AW-1:0] tx_wr, tx_rd;
    reg [RX_AW-1:0] rx_wr, rx_rd;
    reg [6:0] tx_count_r;
    reg [6:0] rx_count_r;
    wire tx_full  = (tx_count_r >= TX_FIFO_DEPTH);
    wire rx_empty = (rx_count_r == 0);
    wire tx_empty = (tx_count_r == 0);

    reg tx_pop_pulse;
    reg rx_push_pulse;
    reg [31:0] rx_push_data;

    reg [2:0] state;
    reg [31:0] active_lut_r;
    reg [31:0] active_addr_r;
    reg [15:0] data_bytes_left;
    reg [31:0] tx_shift_r;
    reg [7:0]  rx_shift_r;
    reg [6:0]  phase_bits_left;
    reg [2:0] phase_lane_r;
    reg [31:0] tx_word_r;
    reg [2:0]  tx_bytes_left_r;
    reg spi_sclk_r;
    reg [15:0] div_count_r;
    reg [31:0] timeout_count_r;
    reg irq_pending_r;
    reg error_r;
    reg timeout_r;
    reg aborted_r;

    wire [1:0] addr_type = active_lut_r[9:8];
    wire [1:0] mode_type = active_lut_r[11:10];
    wire [4:0] dummy_cycles = active_lut_r[16:12];
    wire       data_write = active_lut_r[17];
    wire [1:0] cmd_lane_code = active_lut_r[19:18];
    wire [1:0] addr_lane_code = active_lut_r[21:20];
    wire [1:0] data_lane_code = active_lut_r[23:22];

    function automatic [2:0] lane_decode(input [1:0] code);
        begin
            case (code)
                2'b01: lane_decode = 3'd2;
                2'b10: lane_decode = 3'd4;
                default: lane_decode = 3'd1;
            endcase
        end
    endfunction

    function automatic [7:0] append_lane(input [7:0] old_value,
                                          input [2:0] lane,
                                          input [3:0] pin_value);
        begin
            case (lane)
                3'd2: append_lane = {old_value[5:0], pin_value[1:0]};
                3'd4: append_lane = {old_value[3:0], pin_value[3:0]};
                default: append_lane = {old_value[6:0], pin_value[0]};
            endcase
        end
    endfunction

    wire spi_tick = (state != ST_IDLE) && (div_count_r >= clk_div_r);
    wire [7:0] selected_cmd = active_lut_r[7:0];
    wire trigger_write = wr && (paddr == A_CMD_TRIG);
    wire trigger_busy = trigger_write && (state != ST_IDLE);
    wire trigger_disabled = trigger_write && !ctrl_r[0];
    wire disable_abort = wr && (paddr == A_CTRL) && !pwdata[0] &&
                         (state != ST_IDLE);
    wire timeout_expired = (state != ST_IDLE) &&
                           (timeout_limit_r != 0) &&
                           (timeout_count_r >= (timeout_limit_r - 1'b1));

    assign pready = 1'b1;
    assign pslverr = 1'b0;
    assign irq = irq_en_r[0] & irq_pending_r;
    assign spi_sclk = spi_sclk_r;

    reg [CS_COUNT-1:0] cs_n_r;
    always @(*) begin
        cs_n_r = {CS_COUNT{1'b1}};
        if (state != ST_IDLE && cs_ctrl_r[1:0] < CS_COUNT)
            cs_n_r[cs_ctrl_r[1:0]] = 1'b0;
    end
    assign spi_cs_n = cs_n_r;

    reg [3:0] io_o_r;
    reg [3:0] io_oe_r;
    always @(*) begin
        io_o_r = 4'h0;
        io_oe_r = 4'h0;
        if (state == ST_CMD || state == ST_ADDR || state == ST_MODE ||
            (state == ST_DATA && data_write)) begin
            io_oe_r = (phase_lane_r == 3'd4) ? 4'hf :
                      (phase_lane_r == 3'd2) ? 4'h3 : 4'h1;
            if (phase_lane_r == 3'd4)
                io_o_r = tx_shift_r[31:28];
            else if (phase_lane_r == 3'd2)
                io_o_r = {2'b00, tx_shift_r[31:30]};
            else
                io_o_r[0] = tx_shift_r[31];
        end
    end
    assign spi_io_o = io_o_r;
    assign spi_io_oe = io_oe_r;

    // APB-visible configuration and command registers.
    integer i_lut;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_r <= 32'h0;
            clk_div_r <= 16'h0;
            cs_ctrl_r <= 32'h0;
            irq_en_r <= 32'h0;
            timeout_limit_r <= COMMAND_TIMEOUT_CYCLES;
            cmd_addr_r <= 32'h0;
            cmd_len_r <= 16'h0;
            xip_index_r <= 3'h0;
            for (i_lut = 0; i_lut < LUT_SLOTS; i_lut = i_lut + 1)
                lut_r[i_lut] <= 32'h0;
        end else if (wr) begin
            case (paddr)
                A_CTRL:       ctrl_r <= {pwdata[31:3], 1'b0, pwdata[1:0]};
                A_CLK_DIV:    clk_div_r <= pwdata[15:0];
                A_CS_CTRL:    cs_ctrl_r <= pwdata;
                A_IRQ_EN:     irq_en_r <= pwdata;
                A_TIMEOUT:    timeout_limit_r <= pwdata;
                A_CMD_ADDR:   cmd_addr_r <= pwdata;
                A_CMD_LEN:    cmd_len_r <= pwdata[15:0];
                A_XIP_INDEX:  xip_index_r <= pwdata[2:0];
                default: begin
                    if (paddr >= A_LUT_BASE && paddr < (A_LUT_BASE + LUT_SLOTS*4))
                        lut_r[(paddr - A_LUT_BASE) >> 2] <= pwdata;
                end
            endcase
        end
    end

    // TX/RX FIFO pointers and counts. Engine pulses are delayed by one clock
    // from the phase transition so the old FIFO head is loaded safely.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr <= 0; tx_rd <= 0; tx_count_r <= 0;
            rx_wr <= 0; rx_rd <= 0; rx_count_r <= 0;
        end else if (soft_reset) begin
            tx_wr <= 0; tx_rd <= 0; tx_count_r <= 0;
            rx_wr <= 0; rx_rd <= 0; rx_count_r <= 0;
        end else begin
            if (tx_push && !tx_full) begin
                tx_fifo[tx_wr] <= pwdata;
                tx_wr <= tx_wr + 1'b1;
            end
            if (tx_pop_pulse && !tx_empty)
                tx_rd <= tx_rd + 1'b1;
            case ({tx_push && !tx_full, tx_pop_pulse && !tx_empty})
                2'b10: tx_count_r <= tx_count_r + 1'b1;
                2'b01: tx_count_r <= tx_count_r - 1'b1;
                default: tx_count_r <= tx_count_r;
            endcase

            if (rx_push_pulse && (rx_count_r < RX_FIFO_DEPTH)) begin
                rx_fifo[rx_wr] <= rx_push_data;
                rx_wr <= rx_wr + 1'b1;
            end
            if (rx_pop && !rx_empty)
                rx_rd <= rx_rd + 1'b1;
            case ({rx_push_pulse && (rx_count_r < RX_FIFO_DEPTH), rx_pop && !rx_empty})
                2'b10: rx_count_r <= rx_count_r + 1'b1;
                2'b01: rx_count_r <= rx_count_r - 1'b1;
                default: rx_count_r <= rx_count_r;
            endcase
        end
    end

    task automatic start_data_phase;
        begin
            state <= ST_DATA;
            phase_bits_left <= 7'd8;
            phase_lane_r <= lane_decode(data_lane_code);
            rx_shift_r <= 8'h0;
            if (data_write) begin
                if (tx_bytes_left_r != 0) begin
                    tx_shift_r <= {tx_word_r[31:24], 24'h0};
                    tx_word_r <= {tx_word_r[23:0], 8'h0};
                    tx_bytes_left_r <= tx_bytes_left_r - 1'b1;
                end else if (!tx_empty) begin
                    tx_shift_r <= {tx_fifo[tx_rd][31:24], 24'h0};
                    tx_word_r <= {tx_fifo[tx_rd][23:0], 8'h0};
                    tx_bytes_left_r <= 3'd3;
                    tx_pop_pulse <= 1'b1;
                end else begin
                    tx_shift_r <= 32'h0;
                    error_r <= 1'b1;
                end
            end
        end
    endtask

    task automatic finish_or_data;
        begin
            if (dummy_cycles != 0) begin
                state <= ST_DUMMY;
                phase_bits_left <= {2'b0, dummy_cycles};
                phase_lane_r <= 3'd1;
            end else if (data_bytes_left != 0) begin
                start_data_phase();
            end else begin
                state <= ST_IDLE;
                irq_pending_r <= 1'b1;
            end
        end
    endtask

    // Each tick toggles SCLK; outputs are stable while SCLK is low and inputs
    // are sampled on the following high-to-low edge.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            active_lut_r <= 0;
            active_addr_r <= 0;
            data_bytes_left <= 0;
            tx_shift_r <= 0;
            rx_shift_r <= 0;
            phase_bits_left <= 0;
            phase_lane_r <= 1;
            tx_word_r <= 0;
            tx_bytes_left_r <= 0;
            spi_sclk_r <= 0;
            div_count_r <= 0;
            timeout_count_r <= 0;
            irq_pending_r <= 0;
            error_r <= 0;
            timeout_r <= 0;
            aborted_r <= 0;
            tx_pop_pulse <= 0;
            rx_push_pulse <= 0;
            rx_push_data <= 0;
        end else begin
            tx_pop_pulse <= 1'b0;
            rx_push_pulse <= 1'b0;

            if (wr && paddr == A_IRQ_STATUS) begin
                if (pwdata[0]) irq_pending_r <= 1'b0;
                if (pwdata[1]) timeout_r <= 1'b0;
                if (pwdata[2]) aborted_r <= 1'b0;
                if (pwdata[1] || pwdata[2]) error_r <= 1'b0;
            end

            if (soft_reset) begin
                state <= ST_IDLE;
                spi_sclk_r <= 1'b0;
                div_count_r <= 0;
                timeout_count_r <= 0;
                irq_pending_r <= 1'b0;
                error_r <= 1'b0;
                timeout_r <= 1'b0;
                aborted_r <= 1'b0;
                tx_word_r <= 0;
                tx_bytes_left_r <= 0;
            end else if (abort_cmd || disable_abort) begin
                // Abort atomically releases CS/SCLK and records a completion
                // event; no late command response is generated.
                state <= ST_IDLE;
                spi_sclk_r <= 1'b0;
                div_count_r <= 0;
                timeout_count_r <= 0;
                error_r <= 1'b1;
                aborted_r <= 1'b1;
                irq_pending_r <= 1'b1;
                tx_word_r <= 0;
                tx_bytes_left_r <= 0;
            end else if (timeout_expired) begin
                state <= ST_IDLE;
                spi_sclk_r <= 1'b0;
                div_count_r <= 0;
                timeout_count_r <= 0;
                error_r <= 1'b1;
                timeout_r <= 1'b1;
                irq_pending_r <= 1'b1;
                tx_word_r <= 0;
                tx_bytes_left_r <= 0;
            end else if (trigger_busy || trigger_disabled) begin
                error_r <= 1'b1;
            end else if (state == ST_IDLE) begin
                spi_sclk_r <= 1'b0;
                div_count_r <= 0;
                timeout_count_r <= 0;
                if (trigger_write && ctrl_r[0]) begin
                    active_lut_r <= lut_r[pwdata[2:0]];
                    active_addr_r <= cmd_addr_r;
                    data_bytes_left <= cmd_len_r;
                    tx_shift_r <= {lut_r[pwdata[2:0]][7:0], 24'h0};
                    rx_shift_r <= 0;
                    phase_bits_left <= 7'd8;
                    phase_lane_r <= lane_decode(lut_r[pwdata[2:0]][19:18]);
                    state <= ST_CMD;
                end
            end else if (!ctrl_r[0]) begin
                state <= ST_IDLE;
                spi_sclk_r <= 1'b0;
                timeout_count_r <= 0;
                error_r <= 1'b1;
                aborted_r <= 1'b1;
                irq_pending_r <= 1'b1;
            end else if (spi_tick) begin
                timeout_count_r <= timeout_count_r + 1'b1;
                div_count_r <= 0;
                if (!spi_sclk_r) begin
                    spi_sclk_r <= 1'b1;
                end else begin
                    spi_sclk_r <= 1'b0;

                    if (state == ST_DATA && !data_write) begin
                        rx_shift_r <= append_lane(rx_shift_r, phase_lane_r, spi_io_i);
                        if (phase_bits_left <= phase_lane_r) begin
                            rx_push_data <= {24'h0,
                                append_lane(rx_shift_r, phase_lane_r, spi_io_i)};
                            rx_push_pulse <= 1'b1;
                            rx_shift_r <= 8'h0;
                        end
                    end else if (phase_bits_left > phase_lane_r) begin
                        tx_shift_r <= tx_shift_r << phase_lane_r;
                    end

                    if (phase_bits_left <= phase_lane_r) begin
                        case (state)
                            ST_CMD: begin
                                if (addr_type != 0) begin
                                    state <= ST_ADDR;
                                    phase_bits_left <= (addr_type == 2) ? 7'd32 : 7'd24;
                                    phase_lane_r <= lane_decode(addr_lane_code);
                                    tx_shift_r <= (addr_type == 2) ?
                                                   active_addr_r :
                                                   {active_addr_r[23:0], 8'h0};
                                end else if (mode_type != 0) begin
                                    state <= ST_MODE;
                                    phase_bits_left <= 7'd8;
                                    phase_lane_r <= 3'd1;
                                    tx_shift_r <= {8'hA5, 24'h0};
                                end else begin
                                    finish_or_data();
                                end
                            end
                            ST_ADDR: begin
                                if (mode_type != 0) begin
                                    state <= ST_MODE;
                                    phase_bits_left <= 7'd8;
                                    phase_lane_r <= 3'd1;
                                    tx_shift_r <= {8'hA5, 24'h0};
                                end else begin
                                    finish_or_data();
                                end
                            end
                            ST_MODE: begin
                                finish_or_data();
                            end
                            ST_DUMMY: begin
                                if (data_bytes_left != 0)
                                    start_data_phase();
                                else begin
                                    state <= ST_IDLE;
                                    irq_pending_r <= 1'b1;
                                end
                            end
                            ST_DATA: begin
                                if (data_bytes_left > 1) begin
                                    data_bytes_left <= data_bytes_left - 1'b1;
                                    start_data_phase();
                                end else begin
                                    data_bytes_left <= 0;
                                    state <= ST_IDLE;
                                    irq_pending_r <= 1'b1;
                                end
                            end
                            default: begin
                                state <= ST_IDLE;
                                irq_pending_r <= 1'b1;
                            end
                        endcase
                    end else begin
                        phase_bits_left <= phase_bits_left - phase_lane_r;
                    end
                end
            end else if (div_count_r < clk_div_r) begin
                timeout_count_r <= timeout_count_r + 1'b1;
                div_count_r <= div_count_r + 1'b1;
            end
        end
    end

    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            case (paddr)
                A_CTRL:       prdata = ctrl_r;
                A_STATUS:     prdata = {25'h0, aborted_r, timeout_r, error_r,
                                         irq_pending_r, rx_empty, tx_full,
                                         (state != ST_IDLE)};
                A_CLK_DIV:    prdata = {16'h0, clk_div_r};
                A_CS_CTRL:    prdata = cs_ctrl_r;
                A_IRQ_EN:     prdata = irq_en_r;
                A_IRQ_STATUS: prdata = {29'h0, aborted_r, timeout_r, irq_pending_r};
                A_TIMEOUT:    prdata = timeout_limit_r;
                A_XIP_INDEX:  prdata = {29'h0, xip_index_r};
                A_CMD_ADDR:   prdata = cmd_addr_r;
                A_CMD_LEN:    prdata = {16'h0, cmd_len_r};
                A_RX_DATA:    prdata = rx_empty ? 32'h0 : rx_fifo[rx_rd];
                A_FIFO_STAT:  prdata = {17'h0, rx_count_r, 1'b0, tx_count_r};
                default: begin
                    if (paddr >= A_LUT_BASE && paddr < (A_LUT_BASE + LUT_SLOTS*4))
                        prdata = lut_r[(paddr - A_LUT_BASE) >> 2];
                end
            endcase
        end
    end
endmodule
