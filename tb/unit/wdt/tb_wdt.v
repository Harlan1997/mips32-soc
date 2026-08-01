`timescale 1ns/1ps

module tb_wdt;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg psel = 1'b0;
    reg penable = 1'b0;
    reg pwrite = 1'b0;
    reg [4:0] paddr = 5'd0;
    reg [31:0] pwdata = 32'd0;
    wire [31:0] prdata;
    wire pready;
    wire pslverr;
    wire wdt_reset;
    integer errors = 0;
    integer reset_pulses = 0;

    always #5 clk = ~clk;

    apb_wdt dut (
        .clk(clk), .rst_n(rst_n), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr), .wdt_reset(wdt_reset)
    );

    always @(posedge clk) begin
        if (wdt_reset)
            reset_pulses = reset_pulses + 1;
    end

    task apb_write;
        input [4:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            paddr = addr;
            pwdata = data;
            pwrite = 1'b1;
            psel = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            @(posedge clk);
            #1;
            if (!pready || pslverr) begin
                $display("FAIL: APB write addr=%h data=%h", addr, data);
                errors = errors + 1;
            end
            @(negedge clk);
            psel = 1'b0;
            penable = 1'b0;
            pwrite = 1'b0;
        end
    endtask

    task apb_read;
        input [4:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            paddr = addr;
            pwrite = 1'b0;
            psel = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            @(posedge clk);
            #1;
            if (!pready || pslverr || prdata !== expected) begin
                $display("FAIL: APB read addr=%h got=%h expected=%h", addr, prdata, expected);
                errors = errors + 1;
            end
            @(negedge clk);
            psel = 1'b0;
            penable = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        apb_read(5'h00, 32'h0);
        apb_read(5'h04, 32'hffff_ffff);
        apb_read(5'h10, 32'h0);

        // A short armed interval must produce exactly one reset pulse and a
        // sticky status bit, while disabling the watchdog after expiry.
        apb_write(5'h04, 32'd3);
        apb_write(5'h00, 32'h1);
        wait (wdt_reset === 1'b1);
        @(posedge clk);
        #1;
        if (wdt_reset !== 1'b0) begin
            $display("FAIL: wdt_reset must be a one-cycle pulse");
            errors = errors + 1;
        end
        repeat (2) @(posedge clk);
        if (reset_pulses != 1) begin
            $display("FAIL: reset pulse count=%0d expected=1", reset_pulses);
            errors = errors + 1;
        end
        apb_read(5'h00, 32'h0);
        apb_read(5'h10, 32'h1);
        apb_write(5'h10, 32'h1);
        apb_read(5'h10, 32'h0);

        // Petting reloads the counter and prevents an early expiry.
        apb_write(5'h04, 32'd4);
        apb_write(5'h00, 32'h1);
        @(posedge clk);
        apb_write(5'h0c, 32'h1acc_e551);
        repeat (2) @(posedge clk);
        if (reset_pulses != 1 || wdt_reset !== 1'b0) begin
            $display("FAIL: valid kick caused an early reset");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS wdt");
        else
            $display("REGRESSION_TEST_FAILED wdt errors=%0d", errors);
        $finish;
    end
endmodule
