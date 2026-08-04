`timescale 1ns/1ps
module tb_apb_mmu_ipi_status;
  reg clk=0, rst_n=0, psel=0, penable=0, pwrite=0, target_present=1;
  reg [5:0] paddr=0; reg [31:0] pwdata=0;
  reg ack_valid=0, ack_target=0; reg [7:0] ack_generation=0;
  wire [31:0] prdata; wire pready, pslverr;
  wire invalidate_valid, invalidate_target; wire [7:0] invalidate_generation, invalidate_asid;
  wire [19:0] invalidate_vpn; wire [1:0] invalidate_scope;
  apb_mmu_ipi_status #(.TIMEOUT_CYCLES(4)) dut (.*);
  always #5 clk = ~clk;
  task fail; input [127:0] m; begin $display("ERROR: %0s",m); $display("REGRESSION_TEST_FAILED apb_mmu_ipi_status"); $finish; end endtask
  task apb_write; input [5:0] a; input [31:0] d; begin
    @(negedge clk); paddr=a; pwdata=d; pwrite=1; psel=1; penable=0;
    @(negedge clk); penable=1; @(posedge clk); #1; psel=0; penable=0; pwrite=0;
  end endtask
  task apb_read; input [5:0] a; output [31:0] d; begin
    @(negedge clk); paddr=a; pwrite=0; psel=1; penable=0;
    @(negedge clk); penable=1; @(posedge clk); #1; d=prdata; psel=0; penable=0;
  end endtask
  reg [31:0] rd;
  initial begin
    repeat (2) @(posedge clk); rst_n=1;
    apb_write(6'h20,32'h0000_0701); apb_write(6'h24,32'h0000_0012);
    apb_write(6'h28,32'h0003_4567); apb_write(6'h2c,32'h1); apb_write(6'h30,32'h1);
    @(posedge clk); #1;
    if (!invalidate_valid || !invalidate_target || invalidate_generation!=8'h07 ||
        invalidate_asid!=8'h12 || invalidate_vpn!=20'h34567 || invalidate_scope!=2'd1)
      fail("invalidate payload");
    @(negedge clk); ack_target=1; ack_generation=8'h07; ack_valid=1;
    @(posedge clk); #1; ack_valid=0;
    apb_read(6'h34,rd); if (rd[0] || !rd[2] || rd[3]) fail("done status");
    apb_write(6'h38,32'h0000_0004); apb_read(6'h34,rd); if (rd[2]) fail("clear status");
    target_present=0; apb_write(6'h30,32'h1); apb_read(6'h34,rd); if (!rd[3]) fail("target timeout status");
    $display("REGRESSION_TEST_SUCCESS apb_mmu_ipi_status"); $finish;
  end
endmodule
