`timescale 1ns/1ps

// SoC-facing QSPI pad boundary contract.  The owner/grant policy is tested
// separately; this gate checks lane mapping, legacy x1 compatibility and
// tri-state release for command and memory owners.
module tb_qspi_soc_pad_mux;
    reg cmd_grant, cmd_sclk, cmd_cs_n;
    reg [3:0] cmd_io_o, cmd_io_oe;
    reg mem_grant, mem_sclk, mem_cs_n, mem_mosi;
    reg [3:0] mem_io_o, mem_io_oe;
    wire spi_sclk, spi_cs_n, spi_mosi;
    wire [3:0] qspi_io_o, qspi_io_oe;
    tri [3:0] qspi_io;
    integer failures;

    qspi_soc_pad_mux #(.ENABLE_QUAD_IO(1'b1)) dut (
        .cmd_grant(cmd_grant), .cmd_sclk(cmd_sclk), .cmd_cs_n(cmd_cs_n),
        .cmd_io_o(cmd_io_o), .cmd_io_oe(cmd_io_oe),
        .mem_grant(mem_grant), .mem_sclk(mem_sclk), .mem_cs_n(mem_cs_n),
        .mem_mosi(mem_mosi), .mem_io_o(mem_io_o), .mem_io_oe(mem_io_oe),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .qspi_io_o(qspi_io_o), .qspi_io_oe(qspi_io_oe),
        .qspi_io(qspi_io)
    );

    task automatic check(input [255:0] what, input condition);
        begin
            if (!condition) begin
                $display("ERROR: %0s", what);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        cmd_grant = 1'b1; cmd_sclk = 1'b1; cmd_cs_n = 1'b0;
        cmd_io_o = 4'hA; cmd_io_oe = 4'hF;
        mem_grant = 1'b0; mem_sclk = 1'b0; mem_cs_n = 1'b1; mem_mosi = 1'b0;
        mem_io_o = 4'h0; mem_io_oe = 4'h0;
        #1;
        check("command clock mapping", spi_sclk === 1'b1);
        check("command cs mapping", spi_cs_n === 1'b0);
        check("command legacy lane mapping", spi_mosi === 1'b0);
        check("command quad output mapping", qspi_io === 4'hA);
        check("command quad output-enable mapping", qspi_io_oe === 4'hF);

        // Command owner releases all lanes during a read data phase.
        cmd_io_oe = 4'h0;
        #1;
        check("command read phase is high impedance", qspi_io === 4'bz);
        check("command read phase keeps cs", spi_cs_n === 1'b0);

        // Memory owner remains x1-only at the shared boundary.
        cmd_grant = 1'b0; mem_grant = 1'b1; mem_sclk = 1'b1;
        mem_cs_n = 1'b0; mem_mosi = 1'b1;
        mem_io_o = 4'b0001; mem_io_oe = 4'b0001;
        #1;
        check("memory clock mapping", spi_sclk === 1'b1);
        check("memory cs mapping", spi_cs_n === 1'b0);
        check("memory legacy lane mapping", spi_mosi === 1'b1);
        check("memory only drives lane zero", qspi_io[0] === 1'b1 &&
              qspi_io[3:1] === 3'bzzz);
        check("memory output-enable is lane zero", qspi_io_oe === 4'b0001);

        // Command grant is the explicit owner; an accidental simultaneous
        // grant cannot make the memory source drive the pads.
        cmd_grant = 1'b1; cmd_sclk = 1'b0; cmd_cs_n = 1'b0;
        cmd_io_o = 4'h5; cmd_io_oe = 4'hF;
        #1;
        check("command wins simultaneous grant", qspi_io === 4'h5);

        cmd_grant = 1'b0; mem_grant = 1'b0;
        #1;
        check("idle qspi pads are high impedance", qspi_io === 4'bz);
        check("idle legacy clock is safe", spi_sclk === 1'b0);
        check("idle legacy cs is safe", spi_cs_n === 1'b1);

        if (failures != 0) begin
            $display("REGRESSION_TEST_FAILED qspi_soc_pad_mux failures=%0d", failures);
            $finish;
        end
        $display("REGRESSION_TEST_SUCCESS qspi_soc_pad_mux");
        $finish;
    end
endmodule
