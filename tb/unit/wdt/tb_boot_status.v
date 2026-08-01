`timescale 1ns/1ps

module tb_boot_status;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg wdt_reset = 1'b0;
    reg psel = 1'b0;
    reg penable = 1'b0;
    reg pwrite = 1'b0;
    reg [4:0] paddr = 5'd0;
    reg [31:0] pwdata = 32'd0;
    wire [31:0] prdata;
    wire pready, pslverr;
    integer errors = 0;

    always #5 clk = ~clk;

    apb_boot_status dut (
        .clk(clk), .rst_n(rst_n), .wdt_reset(wdt_reset),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    task apb_write;
        input [4:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            paddr = addr; pwdata = data; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            @(negedge clk);
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        end
    endtask

    task apb_read;
        input [4:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            paddr = addr; pwrite = 1'b0; psel = 1'b1; penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            #1;
            if (!pready || pslverr || prdata !== expected) begin
                $display("FAIL: read offset=%h got=%h expected=%h", addr, prdata, expected);
                errors = errors + 1;
            end
            @(negedge clk);
            psel = 1'b0; penable = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        apb_read(5'h00, 32'h0000_0000);
        apb_read(5'h08, 32'h0000_0001);
        apb_write(5'h00, 32'h0000_0070);
        apb_write(5'h04, 32'hDEAD_B007);
        @(negedge clk);
        wdt_reset = 1'b1;
        @(negedge clk);
        wdt_reset = 1'b0;
        apb_read(5'h00, 32'h0000_0070);
        apb_read(5'h04, 32'hDEAD_B007);
        apb_read(5'h08, 32'h0000_0003);
        apb_write(5'h08, 32'h0000_0002);
        apb_read(5'h08, 32'h0000_0001);
        apb_write(5'h04, 32'h0000_0000);
        apb_read(5'h04, 32'h0000_0000);
        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS boot_status");
        else
            $display("REGRESSION_TEST_FAILED boot_status errors=%0d", errors);
        $finish;
    end
endmodule
