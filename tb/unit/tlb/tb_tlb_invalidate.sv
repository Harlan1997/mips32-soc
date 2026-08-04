`timescale 1ns/1ps
module tb_tlb_invalidate;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, wr_en=0, inv_en=0; reg [5:0] wr_index=0; reg [18:0] wr_vpn2=0, inv_vpn2=0; reg [7:0] wr_asid=0, inv_asid=0; reg [15:0] wr_mask=0; reg [31:0] wr_lo0=0,wr_lo1=0; reg [1:0] inv_scope=0; reg [5:0] inv_wired_floor=2;
  wire [18:0] rd_vpn2; wire [7:0] rd_asid; wire [15:0] rd_mask; wire [31:0] rd_lo0,rd_lo1; wire probe_hit; wire [5:0] probe_index;
  reg [31:0] lookup_va=0; reg [7:0] lookup_asid=0; wire lookup_hit,lookup_v; wire [2:0] lookup_c; wire lookup_d; wire [19:0] lookup_pfn;
  mips_tlb dut(.clk(clk),.rst_n(rst_n),.wr_en(wr_en),.wr_index(wr_index),.wr_vpn2(wr_vpn2),.wr_asid(wr_asid),.wr_mask(wr_mask),.wr_entrylo0(wr_lo0),.wr_entrylo1(wr_lo1),.inv_en(inv_en),.inv_vpn2(inv_vpn2),.inv_asid(inv_asid),.inv_scope(inv_scope),.inv_wired_floor(inv_wired_floor),.rd_index(0),.rd_vpn2(rd_vpn2),.rd_asid(rd_asid),.rd_mask(rd_mask),.rd_entrylo0(rd_lo0),.rd_entrylo1(rd_lo1),.probe_vpn2(lookup_va[31:13]),.probe_asid(lookup_asid),.probe_hit(probe_hit),.probe_index(probe_index),.lookup0_va(lookup_va),.lookup0_asid(lookup_asid),.lookup0_hit(lookup_hit),.lookup0_v(lookup_v),.lookup0_d(lookup_d),.lookup0_c(lookup_c),.lookup0_pfn(lookup_pfn),.lookup1_va(0),.lookup1_asid(0),.lookup1_hit(),.lookup1_v(),.lookup1_d(),.lookup1_c(),.lookup1_pfn());
  task write_entry(input [5:0] i,input [18:0] vpn,input [7:0] asid,input global); begin @(negedge clk); wr_index=i;wr_vpn2=vpn;wr_asid=asid;wr_lo0={26'h0,3'b011,1'b1,1'b1,global};wr_lo1={26'h0,3'b011,1'b1,1'b1,global};wr_en=1;@(negedge clk);wr_en=0; end endtask
  task invalidate(input [1:0] s,input [18:0] vpn,input [7:0] asid); begin @(negedge clk);inv_scope=s;inv_vpn2=vpn;inv_asid=asid;inv_en=1;@(negedge clk);inv_en=0; end endtask
  task check(input [31:0] va,input [7:0] asid,input exp,input [127:0] name); begin lookup_va=va;lookup_asid=asid;#1;if(lookup_hit!==exp) begin $display("FAIL %0s hit=%b exp=%b",name,lookup_hit,exp);$finish;end end endtask
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    write_entry(0,19'h54321,8'h7,1); write_entry(2,19'h12345,8'h1,0); write_entry(3,19'h12345,8'h2,0); write_entry(4,19'h23456,8'h1,0); write_entry(5,19'h12345,8'h7,1);
    check({19'h12345,13'h0},8'h1,1,"page before"); check({19'h12345,13'h0},8'h2,1,"asid2 before");
    invalidate(0,19'h12345,8'h1); #1;
    check({19'h12345,13'h0},8'h1,0,"page invalidated"); check({19'h12345,13'h0},8'h3,0,"dynamic global invalidated"); check({19'h12345,13'h0},8'h2,1,"other asid preserved"); check({19'h54321,13'h0},8'h1,1,"wired global preserved");
    invalidate(1,0,8'h2); #1; check({19'h12345,13'h0},8'h2,0,"asid invalidated");
    check({19'h23456,13'h0},8'h1,1,"other page preserved"); invalidate(2,0,0); #1; check({19'h23456,13'h0},8'h1,0,"all dynamic invalidated");
    $display("REGRESSION_TEST_SUCCESS tlb_invalidate"); $finish;
  end
endmodule
