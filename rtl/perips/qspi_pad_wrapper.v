// Vendor-neutral QSPI pad boundary.
//
// The command engine owns protocol timing and lane direction.  This wrapper
// only converts its four-bit output/output-enable/input contract to a true
// tri-state pad bus, leaving electrical/PHY timing to the eventual pad ring.

module qspi_pad_wrapper #(
    parameter TX_FIFO_DEPTH = 32,
    parameter RX_FIFO_DEPTH = 32,
    parameter LUT_SLOTS     = 8,
    parameter CS_COUNT      = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    psel,
    input  wire                    penable,
    input  wire                    pwrite,
    input  wire [11:0]             paddr,
    input  wire [3:0]              pstrb,
    input  wire [31:0]             pwdata,
    output wire [31:0]             prdata,
    output wire                    pready,
    output wire                    pslverr,
    output wire                    spi_sclk,
    output wire [CS_COUNT-1:0]     spi_cs_n,
    inout  wire [3:0]              spi_io,
    output wire                    active,
    output wire                    irq
);
    wire [3:0] spi_io_o;
    wire [3:0] spi_io_oe;
    wire [3:0] spi_io_i = spi_io;

    qspi_cmd_behavioral #(
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .LUT_SLOTS(LUT_SLOTS),
        .CS_COUNT(CS_COUNT)
    ) u_cmd (
        .clk(clk), .rst_n(rst_n), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_io_o(spi_io_o),
        .spi_io_oe(spi_io_oe), .spi_io_i(spi_io_i), .irq(irq)
    );

    assign spi_io[0] = spi_io_oe[0] ? spi_io_o[0] : 1'bz;
    assign spi_io[1] = spi_io_oe[1] ? spi_io_o[1] : 1'bz;
    assign spi_io[2] = spi_io_oe[2] ? spi_io_o[2] : 1'bz;
    assign spi_io[3] = spi_io_oe[3] ? spi_io_o[3] : 1'bz;
    assign active = (spi_cs_n[0] == 1'b0);
endmodule
