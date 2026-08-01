`timescale 1ns/1ps

// Exercises an actual read-channel timeout with a passive downstream slave.
// No internal force is used: the model controls only legal AXI READY/VALID
// signals at the guard's downstream interface.
module tb_axi_read_timeout_guard;
    reg clk;
    reg rst_n;

    reg [3:0] s_arid;
    reg [31:0] s_araddr;
    reg [7:0] s_arlen;
    reg [2:0] s_arsize;
    reg [1:0] s_arburst;
    reg [1:0] s_arlock;
    reg [3:0] s_arcache;
    reg [2:0] s_arprot;
    reg s_arvalid;
    wire s_arready;
    wire [3:0] s_rid;
    wire [31:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    reg s_rready;

    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire [1:0] m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire m_arvalid;
    reg m_arready;
    reg [3:0] m_rid;
    reg [31:0] m_rdata;
    reg [1:0] m_rresp;
    reg m_rlast;
    reg m_rvalid;
    wire m_rready;
    wire timeout_sticky;

    integer cycles;
    reg backend_ar_seen;

    axi_read_timeout_guard #(
        .TIMEOUT_CYCLES (4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arlock(s_arlock),
        .s_arcache(s_arcache), .s_arprot(s_arprot), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata),
        .s_rresp(s_rresp), .s_rlast(s_rlast), .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arlock(m_arlock),
        .m_arcache(m_arcache), .m_arprot(m_arprot), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata),
        .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rvalid(m_rvalid),
        .m_rready(m_rready), .timeout_sticky(timeout_sticky)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            backend_ar_seen <= 1'b0;
        end else if (m_arvalid && m_arready) begin
            backend_ar_seen <= 1'b1;
        end
    end

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED axi_read_timeout_guard");
            $finish;
        end
    endtask

    task issue_read;
        input [3:0] id;
        input [31:0] addr;
        begin
            @(negedge clk);
            s_arid = id;
            s_araddr = addr;
            s_arlen = 8'd0;
            s_arsize = 3'd2;
            s_arburst = 2'b01;
            s_arvalid = 1'b1;
            do @(posedge clk); while (!(s_arvalid && s_arready));
            @(negedge clk);
            s_arvalid = 1'b0;
        end
    endtask

    task expect_response;
        input [3:0] expected_id;
        input [1:0] expected_resp;
        input [31:0] expected_data;
        integer wait_cycles;
        reg found;
        begin
            wait_cycles = 0;
            found = 1'b0;
            while (!found && wait_cycles < 32) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (s_rvalid && s_rready) begin
                    if (s_rid !== expected_id)
                        fail("response ID changed");
                    if (s_rresp !== expected_resp)
                        fail("response code mismatch");
                    if (!s_rlast)
                        fail("single-beat response omitted RLAST");
                    if (expected_resp == 2'b00 && s_rdata !== expected_data)
                        fail("forwarded response data mismatch");
                    found = 1'b1;
                end
            end
            if (!found)
                fail("timeout response was not returned");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        s_arid = 4'd0;
        s_araddr = 32'd0;
        s_arlen = 8'd0;
        s_arsize = 3'd2;
        s_arburst = 2'b01;
        s_arlock = 2'd0;
        s_arcache = 4'd0;
        s_arprot = 3'd0;
        s_arvalid = 1'b0;
        s_rready = 1'b1;
        m_arready = 1'b0;
        m_rid = 4'd0;
        m_rdata = 32'd0;
        m_rresp = 2'b00;
        m_rlast = 1'b0;
        m_rvalid = 1'b0;
        backend_ar_seen = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // A slave that never accepts AR must return a bounded SLVERR and not
        // leave an orphaned downstream transaction.
        issue_read(4'h1, 32'h1000_0000);
        expect_response(4'h1, 2'b10, 32'd0);
        if (!timeout_sticky)
            fail("AR timeout did not set the sticky status");

        // A slave can accept AR then fail to deliver a response. The guard
        // reports the error, drains the late valid beat, and accepts a new read.
        m_arready = 1'b1;
        backend_ar_seen = 1'b0;
        issue_read(4'h2, 32'h1000_0004);
        while (!backend_ar_seen) @(posedge clk);
        @(negedge clk);
        m_arready = 1'b0;
        expect_response(4'h2, 2'b10, 32'd0);

        @(negedge clk);
        m_rid = 4'h2;
        m_rdata = 32'hDEAD_BEEF;
        m_rresp = 2'b00;
        m_rlast = 1'b1;
        m_rvalid = 1'b1;
        do @(posedge clk); while (!(m_rvalid && m_rready));
        @(negedge clk);
        m_rvalid = 1'b0;
        m_rlast = 1'b0;

        m_arready = 1'b1;
        backend_ar_seen = 1'b0;
        issue_read(4'h3, 32'h1000_0008);
        while (!backend_ar_seen) @(posedge clk);
        @(negedge clk);
        m_rid = 4'h3;
        m_rdata = 32'h1234_5678;
        m_rresp = 2'b00;
        m_rlast = 1'b1;
        m_rvalid = 1'b1;
        expect_response(4'h3, 2'b00, 32'h1234_5678);
        @(negedge clk);
        m_rvalid = 1'b0;
        m_rlast = 1'b0;

        $display("REGRESSION_TEST_SUCCESS axi_read_timeout_guard");
        $finish;
    end

    initial begin
        cycles = 0;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 500)
                fail("testbench watchdog expired");
        end
    end
endmodule
