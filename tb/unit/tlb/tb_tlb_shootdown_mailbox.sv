`timescale 1ns/1ps
module tb_tlb_shootdown_mailbox;
 reg clk=0,rst_n=0,req_valid=0,target_present=0,target_ack=0; reg [7:0] req_asid=0; reg [19:0] req_vpn=0; reg [1:0] req_scope=0;
 wire busy,invalidate_valid,done,timeout,rejected; wire [7:0] invalidate_asid; wire [19:0] invalidate_vpn; wire [1:0] invalidate_scope;
 mmu_tlb_shootdown_mailbox #(.TIMEOUT_CYCLES(4)) dut(.clk(clk),.rst_n(rst_n),.req_valid(req_valid),.req_asid(req_asid),.req_vpn(req_vpn),.req_scope(req_scope),.target_present(target_present),.target_ack(target_ack),.busy(busy),.invalidate_valid(invalidate_valid),.invalidate_asid(invalidate_asid),.invalidate_vpn(invalidate_vpn),.invalidate_scope(invalidate_scope),.done(done),.timeout(timeout),.rejected(rejected));
 always #5 clk=~clk;
 task fail; input [127:0] m; begin $display("ERROR: %0s",m);$display("REGRESSION_TEST_FAILED tlb_shootdown_mailbox");$finish;end endtask
 initial begin
  repeat(2) @(posedge clk); rst_n=1; target_present=1;
  @(negedge clk);req_asid=2;req_vpn=20'h12345;req_scope=0;req_valid=1;@(posedge clk);@(negedge clk);req_valid=0;
  @(posedge clk);#1;if(!invalidate_valid||invalidate_asid!==2||invalidate_vpn!==20'h12345||invalidate_scope!==0)fail("page invalidate payload");
  @(negedge clk);target_ack=1;@(posedge clk);#1;if(!done||busy)fail("page acknowledgement");
  @(negedge clk);target_ack=0;req_scope=1;req_valid=1;@(posedge clk);@(negedge clk);req_valid=1;@(posedge clk);#1;if(!rejected)fail("busy request rejected");@(negedge clk);req_valid=0;target_ack=1;@(posedge clk);target_ack=0;
  @(negedge clk);rst_n=0;@(posedge clk);rst_n=1;target_present=0;req_scope=2;req_valid=1;@(posedge clk);#1;if(!timeout||busy)fail("no-target timeout");@(negedge clk);req_valid=0;
  $display("REGRESSION_TEST_SUCCESS tlb_shootdown_mailbox");$finish;
 end
endmodule
