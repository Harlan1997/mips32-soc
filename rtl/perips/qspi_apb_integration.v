// APB integration wrapper for the vendor-neutral QSPI command contract.
//
// The legacy status block remains at offsets 0x00..0x0c.  The behavioral
// command controller is exposed at an extended window beginning at 0x20:
// host offset = command-controller offset + 0x20.  This keeps existing
// software-visible timeout status stable while allowing command/FIFO work to
// be exercised through the real SoC APB bridge.

module qspi_apb_integration #(
    parameter ENABLE_SHARED_ARB = 1'b0,
    parameter ENABLE_QUAD_IO    = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,
        input  wire        controller_present,
        input  wire        xip_timeout_sticky,
    input  wire        error_event,
    input  wire [31:0] error_value,

    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [3:0]  pstrb,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire [3:0]  qspi_io_i,
    output wire [3:0]  qspi_io_o,
    output wire [3:0]  qspi_io_oe,
    input  wire        shared_grant,
    output wire        active,
    output wire        request,
    output wire        irq
);
    wire status_sel = psel && (paddr[11:0] < 12'h020);
    wire cmd_sel = psel && (paddr[11:0] >= 12'h020) &&
                   (paddr[11:0] < 12'h1a0);
    wire [11:0] cmd_paddr = paddr[11:0] - 12'h020;

    wire [31:0] status_prdata;
    wire status_pready;
    wire status_pslverr;
    wire [31:0] cmd_prdata;
    wire cmd_pready;
    wire cmd_pslverr;
    wire cmd_sclk;
    wire [3:0] cmd_cs_n;
    wire [3:0] cmd_io_o;
    wire [3:0] cmd_io_oe;
    wire [3:0] cmd_io_i = ENABLE_QUAD_IO ? qspi_io_i : {3'b000, spi_miso};
    wire cmd_irq;
    wire trigger_access = cmd_sel && penable && pwrite &&
                          (cmd_paddr == 12'h100);
    wire arbiter_wait = ENABLE_SHARED_ARB && trigger_access && !shared_grant;
    wire cmd_engine_sel = cmd_sel && !arbiter_wait;

    apb_qspi_status u_status (
        .clk                (clk),
        .rst_n              (rst_n),
        .controller_present (controller_present),
        .xip_timeout_sticky (xip_timeout_sticky),
        .error_event        (error_event),
        .error_value        (error_value),
        .psel               (status_sel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (paddr[4:0]),
        .pwdata             (pwdata),
        .prdata             (status_prdata),
        .pready             (status_pready),
        .pslverr            (status_pslverr)
    );

    qspi_cmd_behavioral u_cmd (
        .clk                (clk),
        .rst_n              (rst_n),
        .psel               (cmd_engine_sel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (cmd_paddr),
        .pstrb              (pstrb),
        .pwdata             (pwdata),
        .prdata             (cmd_prdata),
        .pready             (cmd_pready),
        .pslverr            (cmd_pslverr),
        .spi_sclk           (cmd_sclk),
        .spi_cs_n           (cmd_cs_n),
        .spi_io_o           (cmd_io_o),
        .spi_io_oe          (cmd_io_oe),
        .spi_io_i           (cmd_io_i),
        .irq                (cmd_irq)
    );

    assign prdata  = status_sel ? status_prdata :
                     cmd_sel    ? cmd_prdata : 32'h0;
    assign pready  = status_sel ? status_pready :
                     cmd_sel    ? (arbiter_wait ? 1'b0 : cmd_pready) : 1'b1;
    assign pslverr = status_sel ? status_pslverr :
                     cmd_sel    ? (arbiter_wait ? 1'b0 : cmd_pslverr) : 1'b0;

    // Legacy x1 pins remain visible for the default product configuration.
    // When ENABLE_QUAD_IO is set, qspi_io_o/qspi_io_oe carry the full command
    // engine lane contract to qspi_soc_pad_mux.
    assign spi_sclk = cmd_sclk;
    assign spi_cs_n = cmd_cs_n[0];
    assign spi_mosi = cmd_io_o[0];
    assign qspi_io_o = cmd_io_o;
    assign qspi_io_oe = cmd_io_oe;
    assign active   = ~cmd_cs_n[0];
    assign request  = ENABLE_SHARED_ARB && (trigger_access || active);
    assign irq      = cmd_irq;

endmodule
