`timescale 1ns/1ps
`include "soc_config.vh"

module tb_axi_ddr4_controller;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [3:0] awid, arid;
    reg [31:0] awaddr, araddr;
    reg [7:0] awlen, arlen;
    reg [2:0] awsize, arsize;
    reg [1:0] awburst, arburst;
    reg awvalid, wvalid, wlast, bready, arvalid, rready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire awready, wready, bvalid, arready, rvalid, rlast;
    wire [3:0] bid, rid;
    wire [31:0] rdata;
    wire [1:0] bresp, rresp;
    reg refresh_req;
    wire controller_present, init_done, training_done, refresh_busy, fatal_error;
    wire [15:0] error_code;
    wire phy_cmd_valid, last_row_hit, last_row_miss;
    wire [3:0] phy_cmd;
    wire [31:0] phy_addr, phy_wdata;
    wire [3:0] phy_wstrb;
    integer errors;
    integer timeout;
    integer cmd_count;
    integer row_miss_cmd_start;
    reg [3:0] cmd_log [0:63];

    axi_ddr4_controller #(
        .MEM_DEPTH_WORDS(256),
        .INIT_CYCLES(3),
        .COMMAND_LATENCY(2),
        .REFRESH_INTERVAL_CYCLES(0),
        .REFRESH_CYCLES(3)
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

    always @(posedge clk) begin
        if (phy_cmd_valid) begin
            cmd_log[cmd_count] = phy_cmd;
            cmd_count = cmd_count + 1;
            $display("DDR4_CMD cmd=%h addr=%h", phy_cmd, phy_addr);
        end
    end

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

    task write_beat;
        input [31:0] addr;
        input [31:0] data;
        input [7:0] len;
        input [1:0] expected;
        begin
            @(negedge clk);
            awid = 4'h3; awaddr = addr; awlen = len; awsize = 3'd2;
            awburst = 2'b01; awvalid = 1'b1;
            while (!awready) @(negedge clk);
            @(posedge clk); @(negedge clk); awvalid = 1'b0;
            wdata = data; wstrb = 4'hf; wlast = 1'b1; wvalid = 1'b1;
            while (!wready) @(negedge clk);
            @(posedge clk); @(negedge clk); wvalid = 1'b0; wlast = 1'b0;
            bready = 1'b1; timeout = 0;
            while (!bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
            check(bvalid, "write response arrives");
            check(bresp == expected, "write response classification");
            @(posedge clk); @(negedge clk); bready = 1'b0;
        end
    endtask

    task write_burst4;
        input [31:0] addr;
        input [31:0] d0;
        input [31:0] d1;
        input [31:0] d2;
        input [31:0] d3;
        input [1:0] expected;
        integer beat;
        reg [31:0] data;
        begin
            @(negedge clk);
            awid = 4'h5; awaddr = addr; awlen = 3; awsize = 3'd2;
            awburst = 2'b01; awvalid = 1'b1;
            while (!awready) @(negedge clk);
            @(posedge clk); @(negedge clk); awvalid = 1'b0;
            for (beat = 0; beat < 4; beat = beat + 1) begin
                case (beat)
                    0: data = d0;
                    1: data = d1;
                    2: data = d2;
                    default: data = d3;
                endcase
                wdata = data; wstrb = 4'hf; wlast = (beat == 3); wvalid = 1'b1;
                while (!wready) @(negedge clk);
                @(posedge clk); @(negedge clk); wvalid = 1'b0;
            end
            bready = 1'b1; timeout = 0;
            while (!bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
            check(bvalid, "burst write response arrives");
            check(bresp == expected, "burst write response classification");
            @(posedge clk); @(negedge clk); bready = 1'b0;
        end
    endtask

    task read_burst4;
        input [31:0] addr;
        input [31:0] d0;
        input [31:0] d1;
        input [31:0] d2;
        input [31:0] d3;
        integer beat;
        begin
            @(negedge clk);
            arid = 4'h6; araddr = addr; arlen = 3; arsize = 3'd2;
            arburst = 2'b01; arvalid = 1'b1; rready = 1'b1;
            while (!arready) @(negedge clk);
            @(posedge clk); @(negedge clk); arvalid = 1'b0;
            beat = 0; timeout = 0;
            while (beat < 4 && timeout < 200) begin
                @(posedge clk);
                if (rvalid && rready) begin
                    case (beat)
                        0: check(rdata == d0, "burst read beat 0");
                        1: check(rdata == d1, "burst read beat 1");
                        2: check(rdata == d2, "burst read beat 2");
                        default: check(rdata == d3, "burst read beat 3");
                    endcase
                    check(rresp == 2'b00, "burst read response is OKAY");
                    check(rlast == (beat == 3), "burst RLAST placement");
                    beat = beat + 1;
                end
                timeout = timeout + 1;
            end
            check(beat == 4, "burst read beat count");
            @(negedge clk); rready = 1'b0;
        end
    endtask

    task read_burst;
        input [31:0] addr;
        input [7:0] len;
        input [1:0] expected;
        input [31:0] first_expected;
        integer beats;
        begin
            @(negedge clk);
            arid = 4'h4; araddr = addr; arlen = len; arsize = 3'd2;
            arburst = 2'b01; arvalid = 1'b1; rready = 1'b1;
            while (!arready) @(negedge clk);
            @(posedge clk); @(negedge clk); arvalid = 1'b0;
            beats = 0; timeout = 0;
            while (!rlast && timeout < 200) begin
                @(posedge clk);
                if (rvalid && rready) begin
                    if (beats == 0) check(rdata == first_expected, "read data matches");
                    check(rresp == expected, "read response classification");
                    beats = beats + 1;
                end
                timeout = timeout + 1;
            end
            check(beats == (len + 1), "read beat count and RLAST");
            @(negedge clk); rready = 1'b0;
        end
    endtask

    initial begin
        errors = 0; cmd_count = 0; awid = 0; arid = 0; awaddr = 0; araddr = 0;
        awlen = 0; arlen = 0; awsize = 0; arsize = 0; awburst = 0; arburst = 0;
        awvalid = 0; wvalid = 0; wlast = 0; bready = 0; arvalid = 0; rready = 0;
        wdata = 0; wstrb = 0; refresh_req = 0;
        repeat (2) @(posedge clk); rst_n = 1'b1;
        timeout = 0;
        while (!init_done && timeout < 50) begin @(posedge clk); timeout = timeout + 1; end
        check(controller_present && init_done && training_done, "controller initialization completes");

        write_beat(`SOC_DDR_BASE + 32'h100, 32'hCAFE_4401, 0, 2'b00);
        check(last_row_miss, "first access opens a row with ACT");
        read_burst(`SOC_DDR_BASE + 32'h100, 0, 2'b00, 32'hCAFE_4401);
        check(last_row_hit, "same bank/row is a row hit");

        write_burst4(`SOC_DDR_BASE + 32'h120,
                     32'h1000_0001, 32'h1000_0002,
                     32'h1000_0003, 32'h1000_0004, 2'b00);
        read_burst4(`SOC_DDR_BASE + 32'h120,
                    32'h1000_0001, 32'h1000_0002,
                    32'h1000_0003, 32'h1000_0004);
        check(last_row_hit, "burst read remains a row hit");

        // Move to another row in the same bank and require PRE/ACT ordering.
        row_miss_cmd_start = cmd_count;
        write_beat(`SOC_DDR_BASE + 32'h1100, 32'h2000_0001, 0, 2'b00);
        check(last_row_miss, "different row requires precharge and activate");
        check(cmd_log[row_miss_cmd_start] == 4'h4, "row miss emits PRE first");
        check(cmd_log[row_miss_cmd_start + 1] == 4'h1, "row miss emits ACT after PRE");
        check(cmd_log[row_miss_cmd_start + 2] == 4'h3, "row miss emits WRITE after ACT");

        // A valid burst with an early WLAST is rejected and must not commit
        // the partial write to the backing store.
        write_beat(`SOC_DDR_BASE + 32'h200, 32'hBAD0_0001, 1, 2'b10);
        read_burst(`SOC_DDR_BASE + 32'h200, 0, 2'b00, 32'd0);

        // Reset while an AW has been accepted but before W data arrives.
        @(negedge clk);
        awid = 4'h7; awaddr = `SOC_DDR_BASE + 32'h240; awlen = 0;
        awsize = 3'd2; awburst = 2'b01; awvalid = 1'b1;
        while (!awready) @(negedge clk);
        @(posedge clk); @(negedge clk); awvalid = 1'b0;
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        timeout = 0;
        while (!init_done && timeout < 50) begin @(posedge clk); timeout = timeout + 1; end
        check(init_done && !bvalid && !rvalid, "reset flushes incomplete AXI transaction");
        read_burst(`SOC_DDR_BASE + 32'h240, 0, 2'b00, 32'd0);

        // A burst crossing a 4KB boundary is rejected without touching memory.
        write_beat(`SOC_DDR_BASE + 32'h0FFC, 32'hDEAD_0001, 1, 2'b11);
        read_burst(`SOC_DDR_BASE + 32'h0FFC, 1, 2'b11, 32'd0);

        // An address outside the DDR window is DECERR, not wrapped storage.
        write_beat(32'h1000_0000, 32'hDEAD_0002, 0, 2'b11);
        read_burst(32'h1000_0000, 0, 2'b11, 32'd0);

        while (!awready) @(negedge clk);
        @(negedge clk); refresh_req = 1'b1;
        @(posedge clk); @(negedge clk);
        check(refresh_busy && !awready && !arready, "refresh applies AXI backpressure");
        refresh_req = 1'b0;
        repeat (4) @(posedge clk);
        check(!refresh_busy && awready, "refresh completes and AXI recovers");
        check(cmd_count >= 8, "command pulses expose controller sequencing");

        $display("DDR4 controller protocol gate: %0d error(s)", errors);
        if (errors == 0) $display("REGRESSION_TEST_SUCCESS axi_ddr4_controller");
        $finish;
    end
endmodule
