`timescale 1ns/1ps

// QSPI APB/x1 command slice connected to the vendor-neutral serial NOR model.
module tb_qspi_flash_behavioral;
    localparam [11:0] A_CTRL       = 12'h020;
    localparam [11:0] A_STATUS     = 12'h024;
    localparam [11:0] A_CLK_DIV    = 12'h028;
    localparam [11:0] A_IRQ_EN     = 12'h030;
    localparam [11:0] A_IRQ_STATUS = 12'h034;
    localparam [11:0] A_LUT_BASE   = 12'h040;
    localparam [11:0] A_CMD_TRIG   = 12'h120;
    localparam [11:0] A_CMD_ADDR   = 12'h124;
    localparam [11:0] A_CMD_LEN    = 12'h128;
    localparam [11:0] A_TX_DATA    = 12'h130;
    localparam [11:0] A_RX_DATA    = 12'h134;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    reg [31:0] paddr = 0, pwdata = 0;
    reg [3:0] pstrb = 0;
    wire [31:0] prdata;
    wire pready, pslverr;
    wire spi_sclk, spi_cs_n, spi_mosi, qspi_active, qspi_irq;
    wire spi_miso;
    reg [31:0] rd_value;
    integer errors = 0;
    integer guard;

    qspi_apb_integration dut (
        .clk(clk), .rst_n(rst_n), .controller_present(1'b1),
        .xip_timeout_sticky(1'b0), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .active(qspi_active), .irq(qspi_irq)
    );

    spi_flash_behavioral #(.MEM_BYTES(65536)) flash (
        .clk(clk), .rst_n(rst_n), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED qspi_flash_behavioral");
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
            if (!pready || pslverr)
                fail("APB write was not accepted");
            @(negedge clk);
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        end
    endtask

    task automatic apb_read(input [11:0] address, output [31:0] data);
        begin
            @(negedge clk);
            psel = 1'b1; penable = 1'b0; pwrite = 1'b0;
            paddr = address; pwdata = 0; pstrb = 0;
            @(negedge clk);
            penable = 1'b1;
            #1 data = prdata;
            @(posedge clk);
            if (!pready || pslverr)
                fail("APB read was not accepted");
            @(negedge clk);
            psel = 1'b0; penable = 1'b0;
        end
    endtask

    task automatic wait_done;
        begin
            guard = 0;
            while (guard < 4000) begin
                apb_read(A_STATUS, rd_value);
                if (!rd_value[0] && rd_value[3])
                    guard = 4000;
                else
                    guard = guard + 1;
            end
            if (guard != 4000)
                fail("QSPI command did not complete");
            apb_read(A_STATUS, rd_value);
            if (rd_value[0] || !rd_value[3] || rd_value[4])
                fail("QSPI command completed with bad status");
        end
    endtask

    task automatic drain_word(input [31:0] expected);
        integer n;
        reg [31:0] got;
        begin
            got = 0;
            for (n = 0; n < 4; n = n + 1) begin
                apb_read(A_RX_DATA, rd_value);
                got = {got[23:0], rd_value[7:0]};
            end
            if (got !== expected) begin
                $display("ERROR: RX got %h expected %h", got, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        apb_write(A_CLK_DIV, 0);
        apb_write(A_IRQ_EN, 1);
        apb_write(A_CTRL, 1);

        // Seed a deterministic read location without an external image file.
        flash.mem[16'h0010] = 8'hDE;
        flash.mem[16'h0011] = 8'hAD;
        flash.mem[16'h0012] = 8'hBE;
        flash.mem[16'h0013] = 8'hEF;
        apb_write(A_LUT_BASE, 32'h0000_0103);
        apb_write(A_CMD_ADDR, 32'h0000_0010);
        apb_write(A_CMD_LEN, 4);
        apb_write(A_CMD_TRIG, 0);
        wait_done();
        drain_word(32'hDEAD_BEEF);
        apb_write(A_IRQ_STATUS, 1);

        // Write enable is command-only and retains WEL across CS boundaries.
        apb_write(A_LUT_BASE + 12'h4, 32'h0000_0006);
        apb_write(A_CMD_LEN, 0);
        apb_write(A_CMD_TRIG, 1);
        wait_done();
        apb_write(A_IRQ_STATUS, 1);

        // Read status back through the same RX path; WEL is bit1.
        apb_write(A_LUT_BASE + 12'hc, 32'h0000_0005);
        apb_write(A_CMD_LEN, 1);
        apb_write(A_CMD_TRIG, 3);
        wait_done();
        apb_read(A_RX_DATA, rd_value);
        if (rd_value[7:0] !== 8'h02) begin
            $display("ERROR: status after WREN got %h expected 02", rd_value[7:0]);
            errors = errors + 1;
        end
        apb_write(A_IRQ_STATUS, 1);

        // Page program: 0x02 + 24-bit address + four x1 data bytes.
        apb_write(A_LUT_BASE + 12'h8, 32'h0002_0102);
        apb_write(A_CMD_ADDR, 32'h0000_0020);
        apb_write(A_CMD_LEN, 4);
        apb_write(A_TX_DATA, 32'hCAFE_BABE);
        apb_write(A_CMD_TRIG, 2);
        wait_done();
        apb_write(A_IRQ_STATUS, 1);

        // Read back the programmed contents through the same command path.
        apb_write(A_LUT_BASE, 32'h0000_0103);
        apb_write(A_CMD_ADDR, 32'h0000_0020);
        apb_write(A_CMD_LEN, 4);
        apb_write(A_CMD_TRIG, 0);
        wait_done();
        drain_word(32'hCAFE_BABE);
        apb_write(A_IRQ_STATUS, 1);

        // Sector erase is a second command-only transaction.  Re-issue WREN
        // because the NOR model clears WEL after page program.
        apb_write(A_CMD_LEN, 0);
        apb_write(A_CMD_TRIG, 1);
        wait_done();
        apb_write(A_IRQ_STATUS, 1);
        apb_write(A_LUT_BASE + 12'h10, 32'h0000_0120);
        apb_write(A_CMD_ADDR, 32'h0000_0020);
        apb_write(A_CMD_LEN, 0);
        apb_write(A_CMD_TRIG, 4);
        wait_done();
        apb_write(A_IRQ_STATUS, 1);

        apb_write(A_LUT_BASE, 32'h0000_0103);
        apb_write(A_CMD_ADDR, 32'h0000_0020);
        apb_write(A_CMD_LEN, 4);
        apb_write(A_CMD_TRIG, 0);
        wait_done();
        drain_word(32'hFFFF_FFFF);

        if (errors != 0)
            fail("QSPI flash behavioral checks failed");
        $display("REGRESSION_TEST_SUCCESS qspi_flash_behavioral");
        $finish;
    end
endmodule
