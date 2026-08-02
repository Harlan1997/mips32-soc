`timescale 1ns/1ps

module tb_qspi_shared_pin_arbiter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg cmd_req = 1'b0, cmd_active = 1'b0;
    reg cmd_sclk = 1'b0, cmd_cs_n = 1'b1, cmd_mosi = 1'b0;
    reg mem_req = 1'b0, mem_active = 1'b0;
    reg mem_sclk = 1'b0, mem_cs_n = 1'b1, mem_mosi = 1'b0;
    wire cmd_grant, mem_grant;
    wire spi_sclk, spi_cs_n, spi_mosi, busy, conflict;

    qspi_shared_pin_arbiter dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_req(cmd_req), .cmd_active(cmd_active),
        .cmd_sclk(cmd_sclk), .cmd_cs_n(cmd_cs_n), .cmd_mosi(cmd_mosi),
        .mem_req(mem_req), .mem_active(mem_active),
        .mem_sclk(mem_sclk), .mem_cs_n(mem_cs_n), .mem_mosi(mem_mosi),
        .cmd_grant(cmd_grant), .mem_grant(mem_grant),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .busy(busy), .conflict(conflict)
    );

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED qspi_shared_pin_arbiter");
            $finish;
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        if (busy || cmd_grant || mem_grant || spi_cs_n !== 1'b1)
            fail("arbiter did not reset to idle");

        // Memory acquires the idle bus and remains owner while active.
        mem_req = 1'b1;
        mem_sclk = 1'b1; mem_cs_n = 1'b0; mem_mosi = 1'b1;
        tick();
        if (!mem_grant || cmd_grant || spi_sclk !== 1'b1 ||
            spi_cs_n !== 1'b0 || spi_mosi !== 1'b1)
            fail("memory owner was not granted");

        mem_active = 1'b1;
        cmd_req = 1'b1;
        cmd_sclk = 1'b0; cmd_cs_n = 1'b0; cmd_mosi = 1'b0;
        #1;
        if (!conflict || !mem_grant || cmd_grant || spi_mosi !== 1'b1)
            fail("active memory owner was preempted by command request");

        // Release memory; the held command request becomes owner next edge.
        mem_active = 1'b0;
        mem_req = 1'b0;
        tick();
        if (!cmd_grant || mem_grant || !busy || spi_cs_n !== 1'b0)
            fail("command did not acquire after memory release");

        cmd_active = 1'b1;
        #1;
        if (!cmd_grant || conflict || spi_mosi !== 1'b0)
            fail("command owner pins or conflict indication mismatch");

        // No preemption: a new memory request waits for command completion.
        mem_req = 1'b1;
        #1;
        if (!conflict || !cmd_grant || mem_grant)
            fail("memory request preempted active command");
        cmd_active = 1'b0;
        cmd_req = 1'b0;
        tick();
        if (!mem_grant || cmd_grant)
            fail("memory did not acquire after command release");

        mem_req = 1'b0;
        mem_active = 1'b0;
        tick();
        if (busy || cmd_grant || mem_grant || spi_cs_n !== 1'b1 ||
            spi_sclk !== 1'b0)
            fail("arbiter did not release pins to idle");

        // When idle, simultaneous claims resolve deterministically to command.
        cmd_req = 1'b1;
        mem_req = 1'b1;
        tick();
        if (!cmd_grant || mem_grant || !conflict)
            fail("command priority was not deterministic");
        cmd_req = 1'b0;
        mem_req = 1'b0;
        tick();

        $display("REGRESSION_TEST_SUCCESS qspi_shared_pin_arbiter");
        $finish;
    end
endmodule
