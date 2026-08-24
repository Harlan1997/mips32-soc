`timescale 1ns/1ps
module tb_mmu_ipi_shootdown_pressure;
  reg clk = 0, rst_n = 0;
  reg send_valid = 0, send_target = 0, target_present = 1;
  reg ack_valid = 0, ack_target = 0;
  reg [7:0] send_generation = 0, send_asid = 0, ack_generation = 0;
  reg [19:0] send_vpn = 0;
  reg [1:0] send_scope = 0;
  wire busy, pending, invalidate_valid, invalidate_target;
  wire done, timeout, rejected, stale_ack;
  wire [7:0] invalidate_generation, invalidate_asid;
  wire [19:0] invalidate_vpn;
  wire [1:0] invalidate_scope;
  integer errors = 0;
  integer n;

  always #5 clk = ~clk;

  mmu_ipi_shootdown #(.TIMEOUT_CYCLES(8)) dut (.*);

  task fail;
    input [127:0] message;
    begin
      $display("FAIL: %0s", message);
      errors = errors + 1;
    end
  endtask

  task issue_and_ack;
    input [7:0] generation;
    input [7:0] asid_value;
    input [19:0] vpn_value;
    begin
      @(negedge clk);
      send_generation = generation;
      send_asid = asid_value;
      send_vpn = vpn_value;
      send_scope = 2'd1;
      send_target = 1'b1;
      send_valid = 1'b1;
      @(posedge clk);
      #1 send_valid = 1'b0;
      if (!busy || !pending) fail("pressure request not accepted");
      @(posedge clk);
      #1;
      if (!invalidate_valid || invalidate_generation != generation ||
          invalidate_asid != asid_value || invalidate_vpn != vpn_value)
        fail("pressure invalidate payload");
      @(negedge clk);
      ack_target = 1'b1;
      ack_generation = generation;
      ack_valid = 1'b1;
      @(posedge clk);
      #1;
      if (!done || busy || pending) fail("pressure valid ack not completed");
      @(negedge clk);
      ack_valid = 1'b0;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    // Repeated context invalidations model a scheduler/process pressure run.
    for (n = 0; n < 32; n = n + 1)
      issue_and_ack(8'h20 + n[7:0], 8'h40 + n[7:0], 20'h10000 + n * 20'h37);

    // A wrong generation must be observable and must not complete the request.
    @(negedge clk);
    send_generation = 8'hc1; send_asid = 8'h5a; send_vpn = 20'h2abcd;
    send_target = 1'b1; send_valid = 1'b1;
    @(posedge clk); #1 send_valid = 1'b0;
    @(posedge clk); #1;
    @(negedge clk);
    ack_target = 1'b1; ack_generation = 8'hc0; ack_valid = 1'b1;
    @(posedge clk); #1;
    if (!stale_ack || !busy) fail("stale generation was accepted");
    ack_generation = 8'hc1;
    @(posedge clk); #1;
    if (!done || busy) fail("corrected generation did not complete");
    @(negedge clk); ack_valid = 1'b0;

    // A request while one is pending is rejected deterministically.
    @(negedge clk);
    send_generation = 8'he1; send_asid = 8'h61; send_vpn = 20'h30000;
    send_target = 1'b1; send_valid = 1'b1;
    @(posedge clk); #1 send_valid = 1'b0;
    @(negedge clk); send_generation = 8'he2; send_valid = 1'b1;
    @(posedge clk); #1;
    if (!rejected || !busy) fail("busy request was not rejected");
    @(negedge clk); send_valid = 1'b0; ack_target = 1'b1;
    ack_generation = 8'he1; ack_valid = 1'b1;
    @(posedge clk); #1;
    if (!done) fail("pressure cleanup ack failed");
    @(negedge clk); ack_valid = 1'b0;

    // No target must not leave the sender permanently busy.
    @(negedge clk); target_present = 1'b0; send_generation = 8'hf0;
    send_asid = 8'h70; send_vpn = 20'h3f000; send_valid = 1'b1;
    @(posedge clk); #1 send_valid = 1'b0;
    if (!timeout || busy) fail("missing target did not timeout");

    if (errors == 0)
      $display("REGRESSION_TEST_SUCCESS mmu_ipi_shootdown_pressure requests=35");
    else
      $display("REGRESSION_TEST_FAILED mmu_ipi_shootdown_pressure errors=%0d", errors);
    $finish;
  end
endmodule
