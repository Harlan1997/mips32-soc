`timescale 1ns/1ps

module tb_micro_tlb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg flush = 1'b0;
    reg [31:0] i_va = 0, d_va = 0;
    reg [7:0] i_asid = 0, d_asid = 0;
    reg i_main_hit = 0, i_main_multi_hit = 0;
    reg d_main_hit = 0, d_main_multi_hit = 0;
    reg [15:0] i_main_mask = 0, d_main_mask = 0;
    reg [18:0] i_main_vpn2 = 0, d_main_vpn2 = 0;
    reg i_main_g = 0, d_main_g = 0;
    reg [31:0] i_main_lo0 = 0, i_main_lo1 = 0;
    reg [31:0] d_main_lo0 = 0, d_main_lo1 = 0;
    wire i_hit, i_multi_hit, i_v, i_d, d_hit, d_multi_hit, d_v, d_d;
    wire [2:0] i_c, d_c;
    wire [19:0] i_pfn, d_pfn;
    integer errors = 0;

    always #5 clk = ~clk;

    mips_micro_tlb dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .i_va(i_va), .i_asid(i_asid), .i_main_hit(i_main_hit),
        .i_main_multi_hit(i_main_multi_hit), .i_main_mask(i_main_mask),
        .i_main_vpn2(i_main_vpn2), .i_main_g(i_main_g),
        .i_main_lo0(i_main_lo0), .i_main_lo1(i_main_lo1),
        .d_va(d_va), .d_asid(d_asid), .d_main_hit(d_main_hit),
        .d_main_multi_hit(d_main_multi_hit), .d_main_mask(d_main_mask),
        .d_main_vpn2(d_main_vpn2), .d_main_g(d_main_g),
        .d_main_lo0(d_main_lo0), .d_main_lo1(d_main_lo1),
        .i_hit(i_hit), .i_multi_hit(i_multi_hit), .i_v(i_v), .i_d(i_d),
        .i_c(i_c), .i_pfn(i_pfn), .d_hit(d_hit), .d_multi_hit(d_multi_hit),
        .d_v(d_v), .d_d(d_d), .d_c(d_c), .d_pfn(d_pfn)
    );

    function [31:0] make_lo;
        input [19:0] pfn;
        input [2:0] cache_attr;
        input valid;
        input dirty;
        input global_bit;
        begin
            make_lo = {6'b0, pfn, cache_attr, dirty, valid, global_bit};
        end
    endfunction

    task check;
        input [255:0] name;
        input condition;
        begin
            if (condition) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    task fill_i;
        input [31:0] va;
        input [19:0] pfn;
        begin
            i_va = va;
            i_asid = 8'h11;
            i_main_vpn2 = va[31:13];
            i_main_lo0 = make_lo(pfn, 3'b011, 1'b1, 1'b1, 1'b0);
            i_main_lo1 = make_lo(pfn + 20'd1, 3'b011, 1'b1, 1'b1, 1'b0);
            i_main_hit = 1'b1;
            @(posedge clk); #1;
            i_main_hit = 1'b0;
        end
    endtask

    task fill_i_mask;
        input [31:0] va;
        input [19:0] pfn;
        input [15:0] mask;
        input valid_bit;
        begin
            i_va = va; i_asid = 8'h31; i_main_vpn2 = va[31:13];
            i_main_mask = mask;
            i_main_lo0 = make_lo(pfn, 3'b011, valid_bit, 1'b1, 1'b0);
            i_main_lo1 = make_lo(pfn + 20'd1, 3'b011, valid_bit, 1'b1, 1'b0);
            i_main_hit = 1'b1;
            @(posedge clk); #1; i_main_hit = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        i_va = 32'h0001_2004;
        i_asid = 8'h11;
        #1;
        check("reset starts empty", !i_hit && !d_hit);

        fill_i(32'h0001_2004, 20'h12000);
        #1;
        check("I-side refill becomes a hit", i_hit && i_v && i_d &&
              i_pfn == 20'h12000);

        d_va = 32'h0002_0008;
        d_asid = 8'h22;
        d_main_vpn2 = d_va[31:13];
        d_main_lo0 = make_lo(20'h22000, 3'b010, 1'b1, 1'b0, 1'b1);
        d_main_lo1 = make_lo(20'h22001, 3'b010, 1'b1, 1'b0, 1'b1);
        d_main_hit = 1'b1;
        @(posedge clk); #1;
        d_main_hit = 1'b0;
        check("D-side refill becomes a hit", d_hit && d_v && !d_d &&
              d_c == 3'b010 && d_pfn == 20'h22000);

        i_va = 32'h0001_2008;
        i_asid = 8'h12;
        #1;
        check("ASID isolates cached translation", !i_hit);

        // Four entries are filled, then the fifth replaces the round-robin
        // victim. The original entry must no longer hit.
        fill_i(32'h0002_0000, 20'h20000);
        fill_i(32'h0003_0000, 20'h30000);
        fill_i(32'h0004_0000, 20'h40000);
        fill_i(32'h0005_0000, 20'h50000);
        fill_i(32'h0006_0000, 20'h60000);
        i_va = 32'h0001_2004;
        i_asid = 8'h11;
        #1;
        check("round-robin eviction removes oldest entry", !i_hit);

        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        i_va = 32'h0006_0000;
        #1;
        check("architectural flush invalidates I micro-TLB", !i_hit);
        d_va = 32'h0002_0008;
        d_asid = 8'h22;
        #1;
        check("architectural flush invalidates D micro-TLB", !d_hit);

        // PageMask encodings cover 4KB, 16KB, 64KB and 256KB even/odd pairs.
        // The larger-page offset is folded into PFN by the micro-TLB.
        flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        fill_i_mask(32'h0000_2004, 20'h31000, 16'h0000, 1'b1);
        check("4KB page translation", i_hit && i_pfn == 20'h31000);
        flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        fill_i_mask(32'h0000_3004, 20'h32000, 16'h0003, 1'b1);
        check("16KB page translation", i_hit && i_pfn == 20'h32003);
        flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        fill_i_mask(32'h0000_f004, 20'h33000, 16'h000f, 1'b1);
        check("64KB page translation", i_hit && i_pfn == 20'h3300f);
        flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        fill_i_mask(32'h0003_f004, 20'h34000, 16'h003f, 1'b1);
        check("256KB page translation", i_hit && i_pfn == 20'h3403f);
        flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        fill_i_mask(32'h0006_0004, 20'h35000, 16'h0000, 1'b0);
        check("invalid permission is preserved", i_hit && !i_v);

        if (errors == 0) $display("REGRESSION_TEST_SUCCESS micro_tlb");
        else $display("REGRESSION_TEST_FAILED micro_tlb errors=%0d", errors);
        $finish;
    end
endmodule
