`timescale 1ns/1ps
module tb_mmu_ipi_shootdown;
 reg clk=0,rst_n=0,send_valid=0,send_target=0,target_present=0,ack_valid=0,ack_target=0;
 reg [7:0] send_generation=0,send_asid=0,ack_generation=0; reg [19:0] send_vpn=0; reg [1:0] send_scope=0;
 wire busy,pending,invalidate_valid,invalidate_target,done,timeout,rejected,stale_ack;
 wire [7:0] invalidate_generation,invalidate_asid; wire [19:0] invalidate_vpn; wire [1:0] invalidate_scope;
 mmu_ipi_shootdown #(.TIMEOUT_CYCLES(4)) dut(.*);
 always #5 clk=~clk;
 task fail; input [127:0] m; begin $display("ERROR: %0s",m); $display("REGRESSION_TEST_FAILED mmu_ipi_shootdown"); $finish; end endtask
 initial begin
  repeat(2) @(posedge clk); rst_n=1; target_present=1;
  @(negedge clk); send_target=1; send_generation=8'h07; send_asid=8'h12; send_vpn=20'h34567; send_scope=2'd1; send_valid=1;
  @(posedge clk); #1; send_valid=0; if(!busy||!pending) fail("send did not become pending");
  @(posedge clk); #1; if(!invalidate_valid||invalidate_target!=1'b1||invalidate_generation!=8'h07||invalidate_vpn!=20'h34567) fail("payload");
  @(negedge clk); send_generation=8'h08; send_valid=1; @(posedge clk); #1; if(!rejected||!busy) fail("busy send not rejected"); send_valid=0;
  @(negedge clk); ack_valid=1; ack_target=0; ack_generation=8'h06; @(posedge clk); #1; if(!stale_ack||!busy) fail("stale ack accepted");
  @(negedge clk); ack_target=1; ack_generation=8'h07; @(posedge clk); #1; if(!done||busy||pending) fail("valid ack"); ack_valid=0;
  @(negedge clk); rst_n=0; @(posedge clk); rst_n=1; target_present=0; send_generation=8'h09; send_valid=1;
  @(posedge clk); #1; send_valid=0; if(!timeout||busy) fail("no-target timeout");
  $display("REGRESSION_TEST_SUCCESS mmu_ipi_shootdown"); $finish;
 end
endmodule
