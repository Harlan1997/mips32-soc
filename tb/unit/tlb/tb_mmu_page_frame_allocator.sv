`timescale 1ns/1ps
module tb_mmu_page_frame_allocator;
  reg clk=0,rst_n=0,alloc_req=0,release_req=0;
  reg [31:0] release_page=0; reg [7:0] release_generation=0;
  wire alloc_valid,alloc_fail,release_valid,release_reject;
  wire [31:0] alloc_page; wire [7:0] alloc_generation;
  mmu_page_frame_allocator #(.SLOTS(4),.PAGE_BASE(32'h6000)) dut(.*);
  always #5 clk=~clk;
  task fail; input [127:0] msg; begin
    $display("ERROR: %0s",msg);
    $display("REGRESSION_TEST_FAILED mmu_page_frame_allocator"); $finish;
  end endtask
  reg [31:0] pages[0:3]; reg [7:0] gens[0:3]; integer n;
  initial begin
    repeat(2) @(posedge clk); rst_n=1;
    for(n=0;n<4;n=n+1) begin
      @(negedge clk); alloc_req=1; @(posedge clk); #1;
      if(!alloc_valid || alloc_page !== (32'h6000 + n*32'h1000)) fail("page allocation");
      pages[n]=alloc_page; gens[n]=alloc_generation;
      @(negedge clk); alloc_req=0;
    end
    @(negedge clk); alloc_req=1; @(posedge clk); #1;
    if(!alloc_fail) fail("page pool exhaustion");
    @(negedge clk); alloc_req=0;
    @(negedge clk); release_req=1; release_page=pages[1]; release_generation=gens[1]+1; @(posedge clk); #1;
    if(!release_reject) fail("stale page release accepted");
    @(negedge clk); release_generation=gens[1]; @(posedge clk); #1;
    if(!release_valid) fail("valid page release rejected");
    @(negedge clk); release_req=0; alloc_req=1; @(posedge clk); #1;
    if(!alloc_valid || alloc_page !== pages[1] || alloc_generation !== gens[1]+1)
      fail("page generation reuse");
    @(negedge clk); release_page=pages[1]; release_generation=gens[1]+1; release_req=1; alloc_req=1;
    @(posedge clk); #1;
    if(!release_valid || !alloc_valid || alloc_page !== pages[1] ||
       alloc_generation !== gens[1]+2) fail("atomic page release+alloc");
    $display("REGRESSION_TEST_SUCCESS mmu_page_frame_allocator"); $finish;
  end
endmodule
