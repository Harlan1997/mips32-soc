`timescale 1ns/1ps
module tb_page_table_tlb_refill;
  reg clk=0,rst_n=0,miss_valid,mem_ready,mem_error,tlb_wr_ready; reg [31:0] miss_va,ptbr,mem_rdata; reg [1:0] miss_access; reg miss_user; reg [7:0] miss_asid;
  wire miss_ready,mem_valid,walk_resp_valid,walk_fault_valid,tlb_wr_valid; wire [31:0] mem_addr,walk_pa; wire [2:0] walk_fault_code; wire [18:0] tlb_wr_vpn2; wire [7:0] tlb_wr_asid; wire [15:0] tlb_wr_mask; wire [31:0] tlb_wr_entrylo0,tlb_wr_entrylo1;
  reg [31:0] mem[0:4095]; integer errors=0;
  mips_page_table_tlb_refill dut(.*);
  always #5 clk=~clk;
  always @(*) mem_rdata=mem[mem_addr[13:2]];
  task run_walk; begin @(negedge clk);miss_valid=1;@(posedge clk);while(!miss_ready)@(posedge clk);@(negedge clk);miss_valid=0;while(!tlb_wr_valid&&!walk_fault_valid)@(posedge clk);end endtask
  initial begin
    ptbr=32'h1000;miss_va=32'h0000_0123;miss_asid=8'h2;miss_access=2'd1;miss_user=1;miss_valid=0;mem_ready=1;mem_error=0;tlb_wr_ready=0;
    mem[1024]=32'h0000_2003;mem[2048]=32'h0000_300f;#23 rst_n=1;run_walk;
    if(!tlb_wr_valid||tlb_wr_vpn2!==19'd0||tlb_wr_asid!==8'h2||tlb_wr_entrylo0[29:6]!==24'h000003)errors=errors+1;
    if(tlb_wr_entrylo1[1] !== 1'b0) errors=errors+1;
    @(negedge clk);tlb_wr_ready=1;repeat(2)@(posedge clk);@(negedge clk);tlb_wr_ready=0;@(posedge clk);if(tlb_wr_valid)errors=errors+1;
    /* An odd 4KB leaf must occupy EntryLo1 only; EntryLo0 must not alias it. */
    mem[2049]=32'h0000_500f; miss_va=32'h0000_1123; run_walk;
    if(!tlb_wr_valid || tlb_wr_entrylo0[1]!==1'b0 ||
       !tlb_wr_entrylo1[1] || tlb_wr_entrylo1[29:6]!==24'h000005) errors=errors+1;
    @(negedge clk);tlb_wr_ready=1;repeat(2)@(posedge clk);@(negedge clk);tlb_wr_ready=0;@(posedge clk);
    miss_va=32'h0000_0123;
    /* D-side store permission is carried through the refill wrapper. */
    mem[2048]=32'h0000_300b; miss_access=2'd2; run_walk;
    if(!tlb_wr_valid || !tlb_wr_entrylo0[6] || tlb_wr_entrylo0[2:0]!==3'b110) errors=errors+1;
    @(negedge clk);tlb_wr_ready=1;repeat(2)@(posedge clk);@(negedge clk);tlb_wr_ready=0;@(posedge clk);
    /* A user store without W must fault and must not produce a TLB write. */
    mem[2048]=32'h0000_3009; miss_access=2'd2; run_walk;
    if(!walk_fault_valid || walk_fault_code!==3'd2 || tlb_wr_valid) errors=errors+1;
    if(errors==0)$display("REGRESSION_TEST_SUCCESS page_table_tlb_refill");else $display("REGRESSION_TEST_FAILED page_table_tlb_refill errors=%0d",errors);$finish;
  end
endmodule
