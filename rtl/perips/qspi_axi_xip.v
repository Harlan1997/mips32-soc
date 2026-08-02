// AXI read-only XIP front-end for the vendor-neutral QSPI command contract.
//
// Each AXI beat is serialized through the command engine's APB programming
// interface. The default path uses 0x03 + 24-bit address + four x1 data bytes;
// ENABLE_QUAD_IO selects the vendor-neutral 0x6B + 24-bit address + x4 data
// contract. This is a correctness-oriented bridge: it supports one AXI read
// burst at a time and deliberately leaves continuous-read performance
// optimizations to a later implementation.

module qspi_axi_xip #(
    parameter integer COMMAND_TIMEOUT_CYCLES = 4096,
    parameter ENABLE_QUAD_IO = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire [1:0]  s_arlock,
    input  wire [3:0]  s_arcache,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [3:0]  s_rid,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    output wire        s_rvalid,
    input  wire        s_rready,

    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire [1:0]  s_awlock,
    input  wire [3:0]  s_awcache,
    input  wire [2:0]  s_awprot,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [3:0]  s_bid,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire [3:0]  qspi_io_o,
    output wire [3:0]  qspi_io_oe,
    inout  wire [3:0]  qspi_io,
    output wire        active
);
    localparam [3:0] ST_IDLE  = 4'd0;
    localparam [3:0] ST_CTRL  = 4'd1;
    localparam [3:0] ST_LUT   = 4'd2;
    localparam [3:0] ST_ADDR  = 4'd3;
    localparam [3:0] ST_LEN   = 4'd4;
    localparam [3:0] ST_TRIG  = 4'd5;
    localparam [3:0] ST_POLL  = 4'd6;
    localparam [3:0] ST_RX0   = 4'd7;
    localparam [3:0] ST_RX1   = 4'd8;
    localparam [3:0] ST_RX2   = 4'd9;
    localparam [3:0] ST_RX3   = 4'd10;
    localparam [3:0] ST_CLEAR = 4'd11;
    localparam [3:0] ST_RESP  = 4'd12;

    localparam [11:0] A_CTRL       = 12'h000;
    localparam [11:0] A_IRQ_STATUS = 12'h014;
    localparam [11:0] A_LUT0       = 12'h020;
    localparam [11:0] A_CMD_TRIG   = 12'h100;
    localparam [11:0] A_CMD_ADDR   = 12'h104;
    localparam [11:0] A_CMD_LEN    = 12'h108;
    localparam [11:0] A_RX_DATA    = 12'h114;

    reg [3:0] state;
    reg [3:0] read_id_r;
    reg [23:0] current_addr_r;
    reg [8:0] beats_left_r;
    reg [7:0] rx_b0_r, rx_b1_r, rx_b2_r;
    reg [31:0] rdata_r;
    reg [1:0] rresp_r;
    reg        wr_busy_r;
    reg        wr_bvalid_r;
    reg [3:0]  wr_id_r;

    wire [31:0] cmd_prdata;
    wire cmd_pready;
    wire cmd_pslverr;
    reg cmd_psel;
    reg cmd_penable;
    reg cmd_pwrite;
    reg [11:0] cmd_paddr;
    reg [31:0] cmd_pwdata;
    wire [3:0] cmd_cs_n;
    wire cmd_sclk;
    wire [3:0] cmd_io_o;
    wire [3:0] cmd_io_oe;
    wire [3:0] cmd_io_i = ENABLE_QUAD_IO ? qspi_io : {3'b000, spi_miso};
    wire cmd_irq;

    qspi_cmd_behavioral #(
        .COMMAND_TIMEOUT_CYCLES (COMMAND_TIMEOUT_CYCLES)
    ) u_cmd (
        .clk(clk), .rst_n(rst_n),
        .psel(cmd_psel), .penable(cmd_penable), .pwrite(cmd_pwrite),
        .paddr(cmd_paddr), .pstrb(4'hf), .pwdata(cmd_pwdata),
        .prdata(cmd_prdata), .pready(cmd_pready), .pslverr(cmd_pslverr),
        .spi_sclk(cmd_sclk), .spi_cs_n(cmd_cs_n),
        .spi_io_o(cmd_io_o), .spi_io_oe(cmd_io_oe), .spi_io_i(cmd_io_i),
        .irq(cmd_irq)
    );

    assign spi_sclk = cmd_sclk;
    assign spi_cs_n = cmd_cs_n[0];
    assign spi_mosi = cmd_io_o[0];
    assign qspi_io_o = cmd_io_o;
    assign qspi_io_oe = ENABLE_QUAD_IO ? cmd_io_oe : 4'h0;
    assign qspi_io[0] = qspi_io_oe[0] ? qspi_io_o[0] : 1'bz;
    assign qspi_io[1] = qspi_io_oe[1] ? qspi_io_o[1] : 1'bz;
    assign qspi_io[2] = qspi_io_oe[2] ? qspi_io_o[2] : 1'bz;
    assign qspi_io[3] = qspi_io_oe[3] ? qspi_io_o[3] : 1'bz;
    assign active   = ~cmd_cs_n[0];

    assign s_arready = (state == ST_IDLE) && !wr_busy_r && !wr_bvalid_r;
    assign s_rid     = read_id_r;
    assign s_rdata   = rdata_r;
    assign s_rresp   = rresp_r;
    assign s_rlast   = (beats_left_r == 9'd1);
    assign s_rvalid  = (state == ST_RESP);

    assign s_awready = !wr_busy_r && !wr_bvalid_r;
    assign s_wready  = wr_busy_r && !wr_bvalid_r;
    assign s_bid     = wr_id_r;
    assign s_bresp   = 2'b10;
    assign s_bvalid  = wr_bvalid_r;

    // The internal APB sequencer keeps one full APB access active for each
    // setup/poll/read state.  qspi_cmd_behavioral samples writes on the state
    // edge and exposes read data combinationally during the access.
    always @(*) begin
        cmd_psel    = 1'b0;
        cmd_penable = 1'b0;
        cmd_pwrite  = 1'b0;
        cmd_paddr   = 12'h000;
        cmd_pwdata  = 32'h0;
        case (state)
            ST_CTRL: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                cmd_paddr = A_CTRL; cmd_pwdata = 32'h1;
            end
            ST_LUT: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                cmd_paddr = A_LUT0;
                cmd_pwdata = ENABLE_QUAD_IO ? 32'h0080_016b :
                                                   32'h0000_0103;
            end
            ST_ADDR: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                cmd_paddr = A_CMD_ADDR; cmd_pwdata = {8'h0, current_addr_r};
            end
            ST_LEN: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                cmd_paddr = A_CMD_LEN; cmd_pwdata = 32'd4;
            end
            ST_TRIG: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                cmd_paddr = A_CMD_TRIG; cmd_pwdata = 32'd0;
            end
            ST_POLL: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b0;
                cmd_paddr = 12'h004;
            end
            ST_RX0, ST_RX1, ST_RX2, ST_RX3: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b0;
                cmd_paddr = A_RX_DATA;
            end
            ST_CLEAR: begin
                cmd_psel = 1'b1; cmd_penable = 1'b1; cmd_pwrite = 1'b1;
                // Clear done plus timeout/abort event latches before the
                // bridge starts the next beat.
                cmd_paddr = A_IRQ_STATUS; cmd_pwdata = 32'h7;
            end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_busy_r   <= 1'b0;
            wr_bvalid_r <= 1'b0;
            wr_id_r     <= 4'h0;
        end else begin
            if (s_awvalid && s_awready) begin
                wr_busy_r <= 1'b1;
                wr_id_r   <= s_awid;
            end
            if (s_wvalid && s_wready && s_wlast) begin
                wr_busy_r   <= 1'b0;
                wr_bvalid_r <= 1'b1;
            end
            if (wr_bvalid_r && s_bready)
                wr_bvalid_r <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            read_id_r      <= 4'h0;
            current_addr_r <= 24'h0;
            beats_left_r   <= 9'd0;
            rx_b0_r        <= 8'h0;
            rx_b1_r        <= 8'h0;
            rx_b2_r        <= 8'h0;
            rdata_r        <= 32'h0;
            rresp_r        <= 2'b00;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_arvalid && s_arready) begin
                        read_id_r      <= s_arid;
                        current_addr_r <= s_araddr[23:0];
                        beats_left_r   <= {1'b0, s_arlen} + 9'd1;
                        rresp_r        <= 2'b00;
                        state          <= ST_CTRL;
                    end
                end
                ST_CTRL:  state <= ST_LUT;
                ST_LUT:   state <= ST_ADDR;
                ST_ADDR:  state <= ST_LEN;
                ST_LEN:   state <= ST_TRIG;
                ST_TRIG:  state <= ST_POLL;
                ST_POLL: begin
                    if (!cmd_prdata[0] && cmd_prdata[3]) begin
                        if (cmd_prdata[4] || cmd_prdata[5] || cmd_prdata[6]) begin
                            rdata_r <= 32'h0;
                            rresp_r <= 2'b10;
                            state <= ST_CLEAR;
                        end else begin
                            state <= ST_RX0;
                        end
                    end
                end
                ST_RX0: begin
                    rx_b0_r <= cmd_prdata[7:0];
                    state <= ST_RX1;
                end
                ST_RX1: begin
                    rx_b1_r <= cmd_prdata[7:0];
                    state <= ST_RX2;
                end
                ST_RX2: begin
                    rx_b2_r <= cmd_prdata[7:0];
                    state <= ST_RX3;
                end
                ST_RX3: begin
                    rdata_r <= {rx_b0_r, rx_b1_r, rx_b2_r, cmd_prdata[7:0]};
                    rresp_r <= 2'b00;
                    state <= ST_CLEAR;
                end
                ST_CLEAR: state <= ST_RESP;
                ST_RESP: begin
                    if (s_rvalid && s_rready) begin
                        if (beats_left_r == 9'd1) begin
                            state <= ST_IDLE;
                        end else begin
                            beats_left_r <= beats_left_r - 9'd1;
                            current_addr_r <= current_addr_r + 24'd4;
                            state <= ST_CTRL;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
