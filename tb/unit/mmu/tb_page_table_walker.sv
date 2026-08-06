`timescale 1ns/1ps
module tb_page_table_walker;
  reg clk=0,rst_n=0,req_valid,user_mode,mem_ready,mem_error;
  reg [31:0] ptbr,va,mem_rdata; reg [1:0] access;
  wire req_ready,mem_valid,resp_valid,fault_valid; wire [31:0] mem_addr,pa,leaf_pte; wire [2:0] fault_code;
  reg [31:0] mem[0:4095]; integer errors=0;
  mips_page_table_walker dut(.*);
  always #5 clk=~clk;
  always @(*) begin mem_rdata=mem[mem_addr[13:2]]; end
  task walk(input [31:0] v,input [1:0] a,input u); begin
    @(negedge clk); va=v;access=a;user_mode=u;req_valid=1;@(posedge clk);while(!req_ready)@(posedge clk);@(negedge clk);req_valid=0;while(!resp_valid)@(posedge clk);end endtask
  initial begin
    ptbr=32'h0000_1000;req_valid=0;user_mode=0;mem_ready=1;mem_error=0;access=0;va=0;
    mem[1024]=32'h0000_2003; mem[2048]=32'h0000_300F;
    #23 rst_n=1; walk(32'h0000_0123,2'd1,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_300B; walk(32'h0000_0123,2'd2,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_3009; walk(32'h0000_0123,2'd2,1'b1);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[2048]=32'h0000_3003; walk(32'h0000_0123,2'd1,1'b0);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_3001; walk(32'h0000_0123,2'd2,1'b0);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[2048]=32'h0000_3001; walk(32'h0000_0123,2'd1,1'b0);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[1024]=32'd0; walk(32'h0000_0123,2'd1,1'b0);
    if(!fault_valid||fault_code!==3'd1) errors=errors+1;
    if(errors==0)$display("REGRESSION_TEST_SUCCESS page_table_walker");
    else $display("REGRESSION_TEST_FAILED page_table_walker errors=%0d",errors);
    $finish;
  end
endmodule
