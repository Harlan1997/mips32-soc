`timescale 1ns/1ps

// Four-lane pad direction/data contract for qspi_pad_wrapper.
module tb_qspi_pad_wrapper;
    localparam [11:0] A_CTRL       = 12'h000;
    localparam [11:0] A_CLK_DIV    = 12'h008;
    localparam [11:0] A_IRQ_EN     = 12'h010;
    localparam [11:0] A_IRQ_STATUS = 12'h014;
    localparam [11:0] A_LUT_BASE   = 12'h020;
    localparam [11:0] A_CMD_TRIG   = 12'h100;
    localparam [11:0] A_CMD_ADDR   = 12'h104;
    localparam [11:0] A_CMD_LEN    = 12'h108;
    localparam [11:0] A_TX_DATA    = 12'h110;
    localparam [11:0] A_RX_DATA    = 12'h114;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    reg psel = 0, penable = 0, pwrite = 0;
    reg [11:0] paddr = 0;
    reg [3:0] pstrb = 0;
    reg [31:0] pwdata = 0;
    wire [31:0] prdata;
    wire pready, pslverr, spi_sclk, active, irq;
    wire [3:0] spi_cs_n;
    tri [3:0] spi_io;
    reg [7:0] read_byte = 8'hA5;
    integer guard, write_groups;
    reg [31:0] write_capture;
    reg [31:0] rd_value;

    qspi_pad_wrapper dut (
        .clk(clk), .rst_n(rst_n), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_io(spi_io),
        .active(active), .irq(irq)
    );

    // Drive two nibbles MSB-first for the x4 read data phase.
    wire flash_read_active = !spi_cs_n[0] && dut.u_cmd.state == 3'd5 &&
                             !dut.u_cmd.data_write &&
                             dut.u_cmd.phase_lane_r == 3'd4;
    wire [3:0] flash_read_drive = (dut.u_cmd.phase_bits_left == 7'd8) ?
                                  read_byte[7:4] : read_byte[3:0];
    assign spi_io = flash_read_active ? flash_read_drive : 4'bz;

    always @(posedge spi_sclk) begin
        if (!spi_cs_n[0] && dut.u_cmd.state == 3'd5 &&
            dut.u_cmd.data_write && dut.u_cmd.spi_io_oe == 4'hf) begin
            write_capture = {write_capture[27:0], spi_io};
            write_groups = write_groups + 1;
        end
    end

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED qspi_pad_wrapper");
            $finish;
        end
    endtask

    task automatic apb_write(input [11:0] address, input [31:0] data);
        begin
            @(negedge clk); psel = 1; penable = 0; pwrite = 1;
            paddr = address; pwdata = data; pstrb = 4'hf;
            @(negedge clk); penable = 1; @(posedge clk);
            if (!pready || pslverr) fail("APB write failed");
            @(negedge clk); psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task automatic apb_read(input [11:0] address, output [31:0] data);
        begin
            @(negedge clk); psel = 1; penable = 0; pwrite = 0;
            paddr = address; pstrb = 0; @(negedge clk); penable = 1;
            #1 data = prdata; @(posedge clk);
            if (!pready || pslverr) fail("APB read failed");
            @(negedge clk); psel = 0; penable = 0;
        end
    endtask

    task automatic wait_done;
        begin
            guard = 0;
            while (guard < 3000) begin
                if (irq) guard = 3000;
                else begin @(posedge clk); guard = guard + 1; end
            end
            if (!irq) fail("QSPI pad command timed out");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        apb_write(A_CLK_DIV, 0);
        apb_write(A_IRQ_EN, 1);
        apb_write(A_CTRL, 1);

        // x4 read: command-only LUT plus four-lane one-byte data phase.
        apb_write(A_LUT_BASE, (2 << 22) | 32'h05);
        apb_write(A_CMD_LEN, 1);
        apb_write(A_CMD_TRIG, 0);
        wait_done();
        apb_read(A_RX_DATA, rd_value);
        if (rd_value[7:0] !== read_byte) begin
            $display("DEBUG: x4 read got=%h expected=%h io=%h drive=%h oe=%h state=%0d bits=%0d",
                     rd_value[7:0], read_byte, spi_io, flash_read_drive,
                     dut.u_cmd.spi_io_oe, dut.u_cmd.state,
                     dut.u_cmd.phase_bits_left);
            fail("x4 read data mismatch");
        end
        apb_write(A_IRQ_STATUS, 1);

        // x4 write: command/address remain x1, data phase is four lanes.
        write_groups = 0;
        write_capture = 0;
        apb_write(A_LUT_BASE + 12'h4,
                  (2 << 22) | (1 << 17) | (1 << 8) | 32'h32);
        apb_write(A_CMD_ADDR, 32'h0012_3456);
        apb_write(A_CMD_LEN, 4);
        apb_write(A_TX_DATA, 32'hA1B2_C3D4);
        apb_write(A_CMD_TRIG, 1);
        wait_done();
        if (write_groups !== 8 || write_capture !== 32'hA1B2_C3D4)
            fail("x4 pad write direction/data mismatch");
        apb_write(A_IRQ_STATUS, 1);

        if (spi_io !== 4'bz)
            fail("quad pads did not return to high impedance");
        if (active || spi_cs_n[0] !== 1'b1)
            fail("CS/active contract mismatch");
        $display("REGRESSION_TEST_SUCCESS qspi_pad_wrapper");
        $finish;
    end
endmodule
