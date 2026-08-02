// SoC-facing vendor-neutral QSPI pad mux.
//
// Ownership is decided by qspi_shared_pin_arbiter.  This block only maps the
// selected command/memory source to the legacy x1 pins and to a true four-lane
// tri-state pad boundary.  It contains no PHY delay, drive-strength, voltage,
// or board timing behavior.

module qspi_soc_pad_mux #(
    parameter ENABLE_QUAD_IO = 1'b0
) (
    input  wire       cmd_grant,
    input  wire       cmd_sclk,
    input  wire       cmd_cs_n,
    input  wire [3:0] cmd_io_o,
    input  wire [3:0] cmd_io_oe,

    input  wire       mem_grant,
    input  wire       mem_sclk,
    input  wire       mem_cs_n,
    input  wire       mem_mosi,

    output wire       spi_sclk,
    output wire       spi_cs_n,
    output wire       spi_mosi,
    output wire [3:0] qspi_io_o,
    output wire [3:0] qspi_io_oe,
    inout  wire [3:0] qspi_io
);
    wire selected_cmd = cmd_grant;
    wire selected_mem = !selected_cmd && mem_grant;

    assign spi_sclk = selected_cmd ? cmd_sclk :
                      selected_mem ? mem_sclk : 1'b0;
    assign spi_cs_n = selected_cmd ? cmd_cs_n :
                      selected_mem ? mem_cs_n : 1'b1;
    assign spi_mosi = selected_cmd ? cmd_io_o[0] :
                      selected_mem ? mem_mosi : 1'b0;

    assign qspi_io_o = selected_cmd ? cmd_io_o :
                       selected_mem ? {3'b000, mem_mosi} : 4'h0;
    assign qspi_io_oe = ENABLE_QUAD_IO ?
                        (selected_cmd ? cmd_io_oe :
                         selected_mem ? 4'b0001 : 4'h0) : 4'h0;

    assign qspi_io[0] = qspi_io_oe[0] ? qspi_io_o[0] : 1'bz;
    assign qspi_io[1] = qspi_io_oe[1] ? qspi_io_o[1] : 1'bz;
    assign qspi_io[2] = qspi_io_oe[2] ? qspi_io_o[2] : 1'bz;
    assign qspi_io[3] = qspi_io_oe[3] ? qspi_io_o[3] : 1'bz;
endmodule
