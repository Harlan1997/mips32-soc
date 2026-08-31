`timescale 1ns/1ps
module tb_tlb_asid_allocator;
 reg clk=0,rst_n=0,alloc_req=0,release_req=0; reg [7:0] release_asid=0,release_generation=0;
 wire alloc_valid,alloc_fail,release_valid,release_reject; wire [7:0] alloc_asid,alloc_generation;
 mmu_asid_allocator dut(.clk(clk),.rst_n(rst_n),.alloc_req(alloc_req),.alloc_valid(alloc_valid),.alloc_fail(alloc_fail),.alloc_asid(alloc_asid),.alloc_generation(alloc_generation),.release_req(release_req),.release_asid(release_asid),.release_generation(release_generation),.release_valid(release_valid),.release_reject(release_reject));
 always #5 clk=~clk;
 task fail; input [127:0] m; begin $display("ERROR: %0s",m);$display("REGRESSION_TEST_FAILED tlb_asid_allocator");$finish;end endtask
 reg [7:0] a1,a2,a3,a4,g1;
 initial begin
  repeat(2)@(posedge clk);rst_n=1;
  @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_valid||alloc_asid!=1)fail("first allocation");a1=alloc_asid;g1=alloc_generation;@(negedge clk);alloc_req=0;
  repeat(3) begin @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_valid)fail("pool allocation");@(negedge clk);alloc_req=0; end
  @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_fail)fail("pool exhaustion");@(negedge clk);alloc_req=0;
  @(negedge clk);release_req=1;release_asid=a1;release_generation=g1+1;@(posedge clk);#1;if(!release_reject)fail("stale release accepted");@(negedge clk);release_req=0;
  @(negedge clk);release_req=1;release_generation=g1;@(posedge clk);#1;if(!release_valid)fail("valid release rejected");@(negedge clk);release_req=0;
  @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_valid||alloc_asid!=a1||alloc_generation!=g1+1)fail("generation did not advance");
  @(negedge clk);release_req=1;release_asid=a1;release_generation=g1+1;alloc_req=1;@(posedge clk);#1;
  if(!release_valid||!alloc_valid||alloc_asid!=a1||alloc_generation!=g1+2)fail("atomic release+alloc");
  $display("REGRESSION_TEST_SUCCESS tlb_asid_allocator");$finish;
 end
endmodule
