`timescale 1ns/1ps
module tb_l1_cache_nb;
 reg clk=0,rst_n=0,cpu_valid=0,cpu_we=0; reg [3:0] cpu_id=0,cpu_be=4'hf;
 reg [31:0] cpu_addr=0,cpu_wdata=0; reg cache_maint_invalidate=0; wire cpu_ready,rsp_valid,rsp_error;
 wire [3:0] rsp_id; wire [31:0] rsp_rdata; reg rsp_ready=1;
 wire mem_req_valid,mem_req_we; wire [31:0] mem_req_addr; wire [255:0] mem_req_wdata;
 reg mem_req_ready=1,mem_rsp_valid=0,mem_rsp_error=0; reg [31:0] mem_rsp_addr=0; reg [255:0] mem_rsp_data=0;
 wire [3:0] mshr_occupancy,wb_occupancy; integer errors=0;
 always #5 clk=~clk;
 l1_cache_nb dut(.*);
 task issue_read(input [3:0] id,input [31:0] addr);
  begin @(negedge clk); cpu_id=id;cpu_addr=addr;cpu_we=0;cpu_valid=1;
   while(!cpu_ready) @(negedge clk); @(negedge clk);cpu_valid=0; end
 endtask
 task return_line(input [31:0] addr,input [31:0] word);
  begin @(negedge clk);mem_rsp_addr=addr;mem_rsp_data=0;mem_rsp_data[(addr[4:2])*32 +: 32]=word;mem_rsp_valid=1;
   @(negedge clk);mem_rsp_valid=0; end
 endtask
 initial begin
  repeat(2) @(posedge clk);rst_n=1;
  // Two requests to the same line must merge into one refill while retaining
  // both IDs and returning two responses.
  issue_read(4'ha,32'h00000040); issue_read(4'hb,32'h00000044);
  #1;if(!(dut.mvalid[0] ^ dut.mvalid[1])) begin $display("FAIL merged mshr slots=%b%b",dut.mvalid[1],dut.mvalid[0]);errors=errors+1;end
  return_line(32'h00000040,32'haaaa0001);#1;
  if(!rsp_valid||rsp_id!=4'ha||rsp_rdata!=32'haaaa0001) begin $display("FAIL rsp a id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end
  @(negedge clk);rsp_ready=1;
  #1;
  if(!rsp_valid||rsp_id!=4'hb) begin $display("FAIL secondary rsp id=%h",rsp_id);errors=errors+1;end
  @(negedge clk);
  // Distinct lines still occupy independent MSHRs and may complete OOO.
  issue_read(4'hc,32'h000000c0); issue_read(4'hd,32'h00000100);
  #1;if(!(dut.mvalid[0] && dut.mvalid[1])) begin $display("FAIL distinct mshr slots=%b%b",dut.mvalid[1],dut.mvalid[0]);errors=errors+1;end
  return_line(32'h00000100,32'hdddd0001);#1;
  if(!rsp_valid||rsp_id!=4'hd||rsp_rdata!=32'hdddd0001) begin $display("FAIL rsp d id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end
  @(negedge clk);rsp_ready=1;
  return_line(32'h000000c0,32'hcccc0001);#1;
  if(!rsp_valid||rsp_id!=4'hc||rsp_rdata!=32'hcccc0001) begin $display("FAIL rsp c id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end
  if(errors==0)$display("REGRESSION_TEST_SUCCESS l1nb mshr=2 wb=4");else $display("REGRESSION_TEST_FAILED l1nb errors=%0d",errors);$finish;
 end
endmodule
