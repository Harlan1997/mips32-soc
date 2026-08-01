`timescale 1ns/1ps

module tb_ddr4_phy_behavioral;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg init_start, inject_init_fail, inject_training_fail, inject_fatal;
    reg refresh_req, cmd_valid, rd_ready;
    reg [3:0] cmd;
    reg [31:0] cmd_addr, cmd_wdata;
    reg [3:0] cmd_wstrb;
    wire cmd_ready, rd_valid, rd_error, init_done, training_done;
    wire refresh_busy, fatal_error;
    wire [31:0] rd_data;
    wire [15:0] rd_error_code, error_code;

    integer errors;
    integer timeout;

    ddr4_phy_behavioral #(
        .MEM_DEPTH_WORDS(64),
        .INIT_CYCLES(3),
        .TRAIN_CYCLES(3),
        .REFRESH_CYCLES(3)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .init_start(init_start),
        .inject_init_fail(inject_init_fail),
        .inject_training_fail(inject_training_fail),
        .inject_fatal(inject_fatal),
        .refresh_req(refresh_req),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd(cmd),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb),
        .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
        .rd_error(rd_error), .rd_error_code(rd_error_code),
        .init_done(init_done), .training_done(training_done),
        .refresh_busy(refresh_busy), .fatal_error(fatal_error),
        .error_code(error_code)
    );

    task check;
        input condition;
        input [1023:0] label;
        begin
            if (!condition) begin
                $display("FAIL: %0s", label);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task wait_ready;
        begin
            timeout = 0;
            while (!cmd_ready && !fatal_error && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(cmd_ready, "PHY reaches command-ready after init/training");
        end
    endtask

    task write_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            cmd_valid = 1'b1;
            cmd = 4'h2;
            cmd_addr = addr;
            cmd_wdata = data;
            cmd_wstrb = 4'hf;
            while (!cmd_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    task read_word;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            cmd_valid = 1'b1;
            cmd = 4'h1;
            cmd_addr = addr;
            cmd_wdata = 32'd0;
            cmd_wstrb = 4'h0;
            while (!cmd_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
            rd_ready = 1'b1;
            timeout = 0;
            while (!rd_valid && timeout < 50) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(rd_valid, "read response valid");
            check(!rd_error, "read response has no error");
            check(rd_data === expected, "read data matches abstract PHY memory");
            @(posedge clk);
            @(negedge clk);
            rd_ready = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        init_start = 1'b0;
        inject_init_fail = 1'b0;
        inject_training_fail = 1'b0;
        inject_fatal = 1'b0;
        refresh_req = 1'b0;
        cmd_valid = 1'b0;
        cmd = 4'h0;
        cmd_addr = 32'd0;
        cmd_wdata = 32'd0;
        cmd_wstrb = 4'h0;
        rd_ready = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        init_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        init_start = 1'b0;
        wait_ready();
        check(init_done && training_done, "init_done and training_done asserted");

        write_word(32'h0000_0010, 32'hCAFE_4401);
        read_word(32'h0000_0010, 32'hCAFE_4401);

        @(negedge clk);
        refresh_req = 1'b1;
        @(posedge clk);
        @(negedge clk);
        refresh_req = 1'b0;
        check(refresh_busy, "refresh request enters refresh busy");
        check(!cmd_ready, "refresh applies command backpressure");
        repeat (4) @(posedge clk);
        check(!refresh_busy && cmd_ready, "refresh completes and command service recovers");

        inject_fatal = 1'b1;
        @(posedge clk);
        @(negedge clk);
        inject_fatal = 1'b0;
        check(fatal_error && error_code == 16'h0004, "fatal error is sticky and classified");
        check(!cmd_ready, "fatal state blocks PHY commands");

        // Reset and inject a training failure.
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        inject_training_fail = 1'b1;
        @(negedge clk);
        init_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        init_start = 1'b0;
        repeat (7) @(posedge clk);
        check(fatal_error && error_code == 16'h0002, "training failure is classified");

        // Reinitialize and classify an invalid command.
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        inject_training_fail = 1'b0;
        @(negedge clk);
        init_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        init_start = 1'b0;
        wait_ready();
        @(negedge clk);
        cmd_valid = 1'b1;
        cmd = 4'hf;
        cmd_addr = 32'h0000_0000;
        @(posedge clk);
        @(negedge clk);
        cmd_valid = 1'b0;
        check(fatal_error && error_code == 16'h0003, "invalid command is classified");

        // Reset and inject an init failure.
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        inject_init_fail = 1'b1;
        @(negedge clk);
        init_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        init_start = 1'b0;
        repeat (5) @(posedge clk);
        check(fatal_error && error_code == 16'h0001, "init failure is classified");

        $display("DDR4 PHY behavioral gate: %0d error(s)", errors);
        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS ddr4_phy_behavioral");
        $finish;
    end
endmodule
