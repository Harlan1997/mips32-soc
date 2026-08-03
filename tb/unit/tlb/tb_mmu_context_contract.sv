`timescale 1ns/1ps
module tb_mmu_context_contract;
 reg clk=0,rst_n=0,alloc_req=0,release_req=0,sd_req=0,target_present=1,target_ack=0;
 reg [7:0] release_asid=0,release_generation=0; reg [19:0] vpn=20'h22000;
 wire alloc_valid,alloc_fail,release_valid,release_reject; wire [7:0] asid,generation;
 wire sd_busy,inv_valid,sd_done,sd_timeout,sd_rejected; wire [7:0] inv_asid; wire [19:0] inv_vpn; wire [1:0] inv_scope;
 mmu_asid_allocator alloc(.clk(clk),.rst_n(rst_n),.alloc_req(alloc_req),.alloc_valid(alloc_valid),.alloc_fail(alloc_fail),.alloc_asid(asid),.alloc_generation(generation),.release_req(release_req),.release_asid(release_asid),.release_generation(release_generation),.release_valid(release_valid),.release_reject(release_reject));
 mmu_tlb_shootdown_mailbox #(.TIMEOUT_CYCLES(4)) sd(.clk(clk),.rst_n(rst_n),.req_valid(sd_req),.req_asid(asid),.req_vpn(vpn),.req_scope(2'd1),.target_present(target_present),.target_ack(target_ack),.busy(sd_busy),.invalidate_valid(inv_valid),.invalidate_asid(inv_asid),.invalidate_vpn(inv_vpn),.invalidate_scope(inv_scope),.done(sd_done),.timeout(sd_timeout),.rejected(sd_rejected));
 always #5 clk=~clk;
 task fail; input [127:0] m; begin $display("ERROR: %0s",m);$display("REGRESSION_TEST_FAILED mmu_context_contract");$finish;end endtask
 initial begin
  repeat(2)@(posedge clk);rst_n=1;
  @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_valid)fail("initial context allocation");@(negedge clk);alloc_req=0;
  @(negedge clk);sd_req=1;@(posedge clk);@(negedge clk);sd_req=0;@(posedge clk);#1;if(!inv_valid||inv_asid!==asid||inv_vpn!==vpn)fail("context shootdown payload");
  @(negedge clk);target_ack=1;@(posedge clk);#1;if(!sd_done)fail("context shootdown completion");@(negedge clk);target_ack=0;
  release_asid=asid;release_generation=generation+1;@(negedge clk);release_req=1;@(posedge clk);#1;if(!release_reject)fail("stale context release accepted");@(negedge clk);release_generation=generation;@(posedge clk);#1;if(!release_valid)fail("context release failed");release_req=0;
  @(negedge clk);alloc_req=1;@(posedge clk);#1;if(!alloc_valid||generation==0)fail("generation reuse");
  $display("REGRESSION_TEST_SUCCESS mmu_context_contract");$finish;
 end
endmodule
