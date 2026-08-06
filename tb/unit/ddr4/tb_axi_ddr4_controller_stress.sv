`timescale 1ns/1ps
`include "soc_config.vh"

module tb_axi_ddr4_controller_stress;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [3:0] awid, arid;
    reg [31:0] awaddr, araddr, wdata;
    reg [7:0] awlen, arlen;
    reg [2:0] awsize, arsize;
    reg [1:0] awburst, arburst;
    reg awvalid, arvalid, wvalid, wlast, bready, rready, refresh_req;
    reg [3:0] wstrb;
    wire awready, arready, wready, bvalid, rvalid, rlast;
    wire [3:0] bid, rid;
    wire [31:0] rdata;
    wire [1:0] bresp, rresp;
    wire controller_present, init_done, training_done, refresh_busy, fatal_error;
    wire [15:0] error_code;
    wire phy_cmd_valid;
    wire [3:0] phy_cmd;
    wire [31:0] phy_addr, phy_wdata;
    wire [3:0] phy_wstrb;
    wire last_row_hit, last_row_miss;

    integer errors = 0;
    integer timeout;
    integer beat;
    integer cmd_count = 0;
    integer refresh_count = 0;
    reg hold_b = 1'b0;
    reg [3:0] hold_bid;
    reg [1:0] hold_bresp;
    reg hold_r = 1'b0;
    reg [3:0] hold_rid;
    reg [31:0] hold_rdata;
    reg [1:0] hold_rresp;
    reg hold_rlast;

    axi_ddr4_controller #(
        .MEM_DEPTH_WORDS(512),
        .INIT_CYCLES(2),
        .REFRESH_INTERVAL_CYCLES(6),
        .REFRESH_CYCLES(2),
        .COMMAND_LATENCY(1),
        .ENABLE_ECC(1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(awid), .s_awaddr(awaddr), .s_awlen(awlen), .s_awsize(awsize),
        .s_awburst(awburst), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wlast(wlast), .s_wvalid(wvalid),
        .s_wready(wready), .s_bid(bid), .s_bresp(bresp), .s_bvalid(bvalid),
        .s_bready(bready), .s_arid(arid), .s_araddr(araddr), .s_arlen(arlen),
        .s_arsize(arsize), .s_arburst(arburst), .s_arvalid(arvalid),
        .s_arready(arready), .s_rid(rid), .s_rdata(rdata), .s_rresp(rresp),
        .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready),
        .refresh_req(refresh_req), .controller_present(controller_present),
        .init_done(init_done), .training_done(training_done),
        .refresh_busy(refresh_busy), .fatal_error(fatal_error),
        .error_code(error_code), .phy_cmd_valid(phy_cmd_valid),
        .phy_cmd(phy_cmd), .phy_addr(phy_addr), .phy_wdata(phy_wdata),
        .phy_wstrb(phy_wstrb), .last_row_hit(last_row_hit),
        .last_row_miss(last_row_miss)
    );

    task check;
        input condition;
        input [1023:0] label;
        begin
            if (!condition) begin
                $display("FAIL: %0s", label);
                errors = errors + 1;
            end else $display("PASS: %0s", label);
        end
    endtask

    // Protocol checker: command pulses are one-cycle events, AXI responses
    // remain stable under backpressure, and refresh blocks new acceptance.
    always @(posedge clk) begin
        if (!rst_n) begin
            hold_b <= 1'b0;
            hold_r <= 1'b0;
        end else begin
            if (phy_cmd_valid) begin
                check((phy_cmd >= 4'h1) && (phy_cmd <= 4'h5), "command code is legal");
                check(phy_cmd != 4'h0, "command pulse is not NOP");
                cmd_count = cmd_count + 1;
                if (phy_cmd == 4'h5) refresh_count = refresh_count + 1;
            end
            if (refresh_busy)
                check(!awready && !arready, "refresh blocks AXI acceptance");

            if (bvalid && !bready) begin
                if (hold_b)
                    check(bid == hold_bid && bresp == hold_bresp, "B channel holds under backpressure");
                else begin
                    hold_bid = bid;
                    hold_bresp = bresp;
                end
                hold_b <= 1'b1;
            end else hold_b <= 1'b0;

            if (rvalid && !rready) begin
                if (hold_r)
                    check(rid == hold_rid && rdata == hold_rdata &&
                          rresp == hold_rresp && rlast == hold_rlast,
                          "R channel holds under backpressure");
                else begin
                    hold_rid = rid;
                    hold_rdata = rdata;
                    hold_rresp = rresp;
                    hold_rlast = rlast;
                end
                hold_r <= 1'b1;
            end else hold_r <= 1'b0;
        end
    end

    task write_burst16;
        input [31:0] addr;
        integer i;
        begin
            @(negedge clk);
            awid = 4'h1; awaddr = addr; awlen = 8'd15; awsize = 3'd2;
            awburst = 2'b01; awvalid = 1'b1;
            while (!awready) @(negedge clk);
            @(posedge clk); @(negedge clk); awvalid = 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                wdata = 32'hA500_0000 + i;
                wstrb = 4'hf; wlast = (i == 15); wvalid = 1'b1;
                while (!wready) @(negedge clk);
                @(posedge clk); @(negedge clk); wvalid = 1'b0;
            end
            timeout = 0; bready = 1'b0;
            while (!bvalid && timeout < 200) begin @(posedge clk); timeout = timeout + 1; end
            check(bvalid && bresp == 2'b00, "16-beat write completes OKAY");
            repeat (3) @(posedge clk);
            check(bvalid, "B response remains pending during stall");
            bready = 1'b1;
            @(posedge clk); @(negedge clk); bready = 1'b0;
        end
    endtask

    task read_burst16;
        input [31:0] addr;
        integer i;
        begin
            @(negedge clk);
            arid = 4'h2; araddr = addr; arlen = 8'd15; arsize = 3'd2;
            arburst = 2'b01; arvalid = 1'b1; rready = 1'b0;
            while (!arready) @(negedge clk);
            @(posedge clk); @(negedge clk); arvalid = 1'b0;
            timeout = 0;
            while (!rvalid && timeout < 200) begin @(posedge clk); timeout = timeout + 1; end
            check(rvalid && rresp == 2'b00, "R response arrives before release");
            repeat (2) @(posedge clk);
            check(rvalid && rdata == 32'hA500_0000 && !rlast, "first R beat holds under stall");
            rready = 1'b1;
            for (i = 0; i < 16; i = i + 1) begin
                while (!rvalid) @(posedge clk);
                check(rresp == 2'b00, "burst R response is OKAY");
                check(rdata == (32'hA500_0000 + i), "burst R data matches");
                check(rlast == (i == 15), "burst RLAST is correctly placed");
                @(posedge clk);
            end
            rready = 1'b0;
        end
    endtask

    initial begin
        awid = 0; arid = 0; awaddr = 0; araddr = 0; awlen = 0; arlen = 0;
        awsize = 0; arsize = 0; awburst = 0; arburst = 0; awvalid = 0;
        arvalid = 0; wvalid = 0; wlast = 0; bready = 0; rready = 0;
        wdata = 0; wstrb = 0; refresh_req = 0;
        repeat (2) @(posedge clk); rst_n = 1'b1;
        timeout = 0;
        while (!init_done && timeout < 50) begin @(posedge clk); timeout = timeout + 1; end
        check(controller_present && init_done && training_done, "stress controller initializes");

        write_burst16(`SOC_DDR_BASE + 32'h400);
        read_burst16(`SOC_DDR_BASE + 32'h400);

        // Let the programmed interval expire so the controller issues an
        // automatic refresh while idle before the explicit refresh below.
        repeat (12) @(posedge clk);

        // Explicit refresh must also block both channels and recover cleanly.
        @(negedge clk); refresh_req = 1'b1;
        @(posedge clk); @(negedge clk);
        check(refresh_busy && !awready && !arready, "explicit refresh applies backpressure");
        refresh_req = 1'b0;
        timeout = 0;
        while (refresh_busy && timeout < 50) begin @(posedge clk); timeout = timeout + 1; end
        check(!refresh_busy && awready && arready, "explicit refresh recovers AXI");
        check(refresh_count >= 2, "automatic and explicit refresh commands observed");
        check(cmd_count >= 4, "stress command stream observed");
        check(!fatal_error && error_code == 16'd0, "stress completes without fatal error");
        if (errors == 0) $display("REGRESSION_TEST_SUCCESS axi_ddr4_controller_stress");
        else $display("REGRESSION_TEST_FAILED axi_ddr4_controller_stress errors=%0d", errors);
        $finish;
    end
endmodule
