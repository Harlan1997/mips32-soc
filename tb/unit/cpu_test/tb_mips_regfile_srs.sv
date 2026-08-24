`timescale 1ns/1ps

module tb_mips_regfile_srs;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    reg [4:0] raddr1, raddr2, waddr, shadow_raddr, shadow_waddr;
    reg [31:0] wdata, shadow_wdata;
    reg we, shadow_we;
    reg [3:0] current_set, previous_set, shadow_wset;
    wire [31:0] rdata1, rdata2, shadow_rdata;
    reg ctx_save_req, ctx_restore_req;
    reg [1023:0] ctx_restore_data;
    wire ctx_save_done, ctx_restore_done;
    wire [1023:0] ctx_save_data;

    mips_regfile dut (
        .clk(clk), .rst_n(rst_n), .raddr1(raddr1), .rdata1(rdata1),
        .raddr2(raddr2), .rdata2(rdata2), .waddr(waddr), .wdata(wdata), .we(we),
        .current_set(current_set), .previous_set(previous_set),
        .shadow_raddr(shadow_raddr), .shadow_rdata(shadow_rdata),
        .shadow_we(shadow_we), .shadow_wset(shadow_wset),
        .shadow_waddr(shadow_waddr), .shadow_wdata(shadow_wdata),
        .ctx_save_req(ctx_save_req), .ctx_save_done(ctx_save_done),
        .ctx_save_data(ctx_save_data), .ctx_restore_req(ctx_restore_req),
        .ctx_restore_data(ctx_restore_data), .ctx_restore_done(ctx_restore_done));

    integer failures;
    task automatic check;
        input [31:0] actual;
        input [31:0] expected;
        input [127:0] name;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s actual=%08h expected=%08h", name, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        raddr1 = 0; raddr2 = 0; waddr = 0; shadow_raddr = 0; shadow_waddr = 0;
        wdata = 0; shadow_wdata = 0; we = 0; shadow_we = 0;
        current_set = 0; previous_set = 0; shadow_wset = 0;
        ctx_save_req = 0; ctx_restore_req = 0; ctx_restore_data = 0;
        #12 rst_n = 1;
        @(negedge clk); waddr = 5'd9; wdata = 32'h1111_2222; we = 1;
        @(negedge clk); we = 0; raddr1 = 5'd9;
        #1 check(rdata1, 32'h1111_2222, "current bank");
        @(negedge clk); shadow_wset = 4'd3; shadow_waddr = 5'd9;
        shadow_wdata = 32'haaaa_5555; shadow_we = 1;
        @(negedge clk); shadow_we = 0; previous_set = 4'd3;
        shadow_raddr = 5'd9; raddr1 = 5'd9;
        #1 check(rdata1, 32'h1111_2222, "current isolation");
        check(shadow_rdata, 32'haaaa_5555, "previous shadow bank");
        raddr1 = 0; shadow_raddr = 0;
        #1 check(rdata1, 32'd0, "current r0");
        check(shadow_rdata, 32'd0, "shadow r0");
        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_regfile_srs");
        else
            $display("REGRESSION_TEST_FAIL mips_regfile_srs failures=%0d", failures);
        $finish;
    end
endmodule
