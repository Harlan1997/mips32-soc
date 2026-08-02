`timescale 1ns/1ps

// Vendor-neutral QSPI command/FIFO contract. The responder models only the
// pin timing needed by this block contract, not a vendor flash's full model.
module tb_qspi_cmd_behavioral;
    localparam [7:0] STATUS_BYTE = 8'hA5;
    localparam [31:0] QUAD_WORD = 32'hA1B2_C3D4;
    localparam [11:0] A_CTRL       = 12'h000;
    localparam [11:0] A_STATUS     = 12'h004;
    localparam [11:0] A_CLK_DIV    = 12'h008;
    localparam [11:0] A_IRQ_EN     = 12'h010;
    localparam [11:0] A_IRQ_STATUS = 12'h014;
    localparam [11:0] A_TIMEOUT    = 12'h018;
    localparam [11:0] A_LUT_BASE   = 12'h020;
    localparam [11:0] A_CMD_TRIG   = 12'h100;
    localparam [11:0] A_CMD_ADDR   = 12'h104;
    localparam [11:0] A_CMD_LEN    = 12'h108;
    localparam [11:0] A_TX_DATA    = 12'h110;
    localparam [11:0] A_RX_DATA    = 12'h114;
    localparam [11:0] A_FIFO_STAT  = 12'h118;

    reg clk, rst_n;
    reg psel, penable, pwrite;
    reg [11:0] paddr;
    reg [3:0] pstrb;
    reg [31:0] pwdata;
    wire [31:0] prdata;
    wire pready, pslverr;
    wire spi_sclk;
    wire [3:0] spi_cs_n;
    wire [3:0] spi_io_o;
    wire [3:0] spi_io_oe;
    wire [3:0] spi_io_i;
    wire irq;
    reg [3:0] flash_drive;
    integer sclk_edges, cs_assertions, write_groups;
    reg [7:0] write_cmd;
    reg [23:0] write_addr;
    reg [31:0] write_data;
    reg write_seen;
    reg [31:0] rd_value;

    qspi_cmd_behavioral dut (
        .clk(clk), .rst_n(rst_n), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_io_o(spi_io_o),
        .spi_io_oe(spi_io_oe), .spi_io_i(spi_io_i), .irq(irq)
    );

    assign spi_io_i = flash_drive;

    // The DUT samples on the falling edge. The current phase count identifies
    // the bit presented by the flash for that edge.
    always @(*) begin
        flash_drive = 4'h0;
        if (!spi_cs_n[0] && dut.state == 3'd5 && !dut.data_write &&
            dut.phase_lane_r == 3'd1 && dut.phase_bits_left != 0)
            flash_drive[0] = STATUS_BYTE[dut.phase_bits_left - 1'b1];
    end

    always #5 clk = ~clk;

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED qspi_cmd_behavioral");
            $finish;
        end
    endtask

    task automatic apb_write(input [11:0] address, input [31:0] data);
        begin
            @(negedge clk);
            psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
            paddr = address; pwdata = data; pstrb = 4'hf;
            @(negedge clk);
            penable = 1'b1;
            @(posedge clk);
            if (!pready || pslverr) fail("APB write was not accepted");
            @(negedge clk);
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        end
    endtask

    task automatic apb_read(input [11:0] address, output [31:0] data);
        begin
            @(negedge clk);
            psel = 1'b1; penable = 1'b0; pwrite = 1'b0;
            paddr = address; pwdata = 32'h0; pstrb = 4'h0;
            @(negedge clk);
            penable = 1'b1;
            // APB read data is valid throughout the access phase; sample it
            // before the edge that consumes an RX FIFO entry.
            #1 data = prdata;
            @(posedge clk);
            if (!pready || pslverr) fail("APB read was not accepted");
            @(negedge clk);
            psel = 1'b0; penable = 1'b0;
        end
    endtask

    task automatic wait_irq;
        integer timeout;
        begin
            timeout = 0;
            while (!irq && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!irq) fail("QSPI transaction did not assert IRQ");
        end
    endtask

    always @(negedge spi_cs_n[0]) begin
        cs_assertions = cs_assertions + 1;
        write_groups = 0;
        write_cmd = 0;
        write_addr = 0;
        write_data = 0;
    end

    // Capture x1 command/address groups and x4 data groups. A quad write has
    // 8 + 24 + 8 groups in this configuration.
    always @(posedge spi_sclk) begin
        sclk_edges = sclk_edges + 1;
        if (!spi_cs_n[0] && spi_io_oe != 0 && write_seen) begin
            if (write_groups < 8)
                write_cmd = {write_cmd[6:0], spi_io_o[0]};
            else if (write_groups < 32)
                write_addr = {write_addr[22:0], spi_io_o[0]};
            else if (write_groups < 40)
                write_data = {write_data[27:0], spi_io_o[3:0]};
            write_groups = write_groups + 1;
        end
    end

    initial begin
        clk = 1'b0; rst_n = 1'b0;
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        paddr = 0; pstrb = 0; pwdata = 0;
        flash_drive = 0; sclk_edges = 0; cs_assertions = 0;
        write_groups = 0; write_cmd = 0; write_addr = 0; write_data = 0;
        write_seen = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        apb_write(A_CLK_DIV, 32'd0);
        apb_write(A_IRQ_EN, 32'h1);
        apb_write(A_CTRL, 32'h1);

        // LUT0: status read (0x05), no address, one x1 data byte.
        apb_write(A_LUT_BASE, 32'h0000_0005);
        apb_write(A_CMD_LEN, 32'd1);
        apb_write(A_CMD_TRIG, 32'd0);
        // Busy retrigger sets error while preserving the original command.
        apb_write(A_CMD_TRIG, 32'd0);
        wait_irq();
        apb_read(A_RX_DATA, rd_value);
        if (rd_value !== 32'h0000_00A5) begin
            fail("status read returned the wrong RX byte");
        end
        apb_read(A_STATUS, rd_value);
        if (!rd_value[4] || !rd_value[3] || rd_value[2] !== 1'b1)
            fail("busy/error/IRQ status did not record the busy trigger");
        apb_read(A_FIFO_STAT, rd_value);
        if (rd_value[14:8] !== 7'd0 || rd_value[6:0] !== 7'd0)
            fail("FIFO status did not drain after RX read");
        apb_write(A_IRQ_STATUS, 32'h1);

        // LUT1: 0x32, 24-bit x1 address, four-byte x4 write data.
        apb_write(A_LUT_BASE + 12'h4,
                  (2 << 22) | (1 << 17) | (1 << 8) | 32'h32);
        apb_write(A_CMD_ADDR, 32'h0012_3456);
        apb_write(A_CMD_LEN, 32'd4);
        apb_write(A_TX_DATA, 32'hA1B2_C3D4);
        write_seen = 1'b1;
        apb_write(A_CMD_TRIG, 32'd1);
        wait_irq();
        if (write_groups !== 40)
            fail("quad write did not produce expected lane groups");
        if (write_cmd !== 8'h32)
            fail("quad write command opcode mismatch");
        if (write_addr !== 24'h12_3456) begin
            fail("quad write address mismatch");
        end
        if (write_data !== 32'hA1B2_C3D4)
            fail("quad write data lane sequence mismatch");
        if (cs_assertions !== 2 || sclk_edges == 0)
            fail("CS/SCLK pin activity was not observed");

        apb_write(A_IRQ_STATUS, 32'h1);
        apb_read(A_STATUS, rd_value);
        if (rd_value[0] || rd_value[3] || !rd_value[4])
            fail("QSPI did not return idle with sticky error status");
        apb_write(A_CTRL, 32'h3);
        apb_write(A_CTRL, 32'h1);
        apb_read(A_STATUS, rd_value);
        if (rd_value[0] || rd_value[3] || rd_value[4])
            fail("QSPI soft reset did not clear status");

        // A command that cannot make progress must terminate locally.  The
        // timeout is counted in reference-clock cycles, independent of the
        // SPI divisor, and leaves an observable event for software.
        apb_write(A_TIMEOUT, 32'd4);
        apb_write(A_CLK_DIV, 32'h0000_FFFF);
        apb_write(A_CTRL, 32'h1);
        apb_write(A_CMD_LEN, 32'd1);
        apb_write(A_CMD_TRIG, 32'd0);
        repeat (8) @(posedge clk);
        apb_read(A_STATUS, rd_value);
        if (rd_value[0] || !rd_value[3] || !rd_value[4] ||
            !rd_value[5] || rd_value[6])
            fail("command timeout did not return idle with timeout status");
        if (!spi_cs_n[0] || spi_sclk)
            fail("command timeout did not release SPI pins");
        apb_write(A_IRQ_STATUS, 32'h7);
        apb_read(A_STATUS, rd_value);
        if (rd_value[3] || rd_value[4] || rd_value[5] || rd_value[6])
            fail("timeout W1C did not clear event status");

        // CTRL[2] aborts an active transaction synchronously.  It records a
        // separate abort event and never leaves a stale command active.
        apb_write(A_TIMEOUT, 32'd1000);
        apb_write(A_CMD_TRIG, 32'd0);
        while (dut.state == 3'd0) @(posedge clk);
        apb_write(A_CTRL, 32'h5);
        apb_read(A_STATUS, rd_value);
        if (rd_value[0] || !rd_value[3] || !rd_value[4] ||
            rd_value[5] || !rd_value[6])
            fail("command abort did not return idle with abort status");
        if (!spi_cs_n[0] || spi_sclk)
            fail("command abort did not release SPI pins");
        apb_write(A_IRQ_STATUS, 32'h7);

        // External reset (the same reset asserted by the SoC WDT path) must
        // cancel an in-flight command and return the boundary to safe idle.
        apb_write(A_TIMEOUT, 32'd1000);
        apb_write(A_CMD_TRIG, 32'd0);
        while (dut.state == 3'd0) @(posedge clk);
        rst_n = 1'b0;
        #1;
        if (!spi_cs_n[0] || spi_sclk || irq)
            fail("reset-in-flight did not clear QSPI pins/status");
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        apb_read(A_STATUS, rd_value);
        if (rd_value[0] || rd_value[3] || rd_value[4] ||
            rd_value[5] || rd_value[6])
            fail("QSPI reset did not restore clean status");

        $display("REGRESSION_TEST_SUCCESS qspi_cmd_behavioral");
        $finish;
    end
endmodule
