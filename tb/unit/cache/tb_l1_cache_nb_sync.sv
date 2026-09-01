`timescale 1ns/1ps
module tb_l1_cache_nb_sync;
 reg clk=0, rst_n=0, cpu_valid=0, cpu_we=0;
 reg [3:0] cpu_id=0, cpu_be=4'hf;
 reg [31:0] cpu_addr=0, cpu_wdata=0;
 reg cache_maint_invalidate=0;
 reg [4:0] cache_maint_op=0;
 reg [31:0] cache_maint_addr=0, cache_tag_wdata=0;
 wire [31:0] cache_tag_rdata;
 wire cache_maint_ready, cache_maint_done, cache_maint_error;
 wire cpu_ready, rsp_valid, rsp_error;
 wire [3:0] rsp_id; wire [31:0] rsp_rdata; reg rsp_ready=1;
 wire mem_req_valid, mem_req_we; wire [31:0] mem_req_addr;
 wire [255:0] mem_req_wdata;
 reg mem_req_ready=1, mem_rsp_valid=0, mem_rsp_error=0;
 reg [31:0] mem_rsp_addr=0; reg [255:0] mem_rsp_data=0;
 wire [3:0] mshr_occupancy, wb_occupancy;
 // This unit test exercises the standalone maintenance contract.  Keep the
 // optional coherency sideband explicitly inactive and observe notifications
 // so wildcard connection remains complete as the DUT interface evolves.
 reg coh_snoop_valid=0;
 reg [31:0] coh_snoop_addr=0;
 wire coh_store_valid;
 wire [31:0] coh_store_addr;
 integer errors=0, cycles;
 always #5 clk=~clk;

 l1_cache_nb dut(.*);

 task issue_read(input [31:0] addr);
   begin
     @(negedge clk); cpu_addr=addr; cpu_we=0; cpu_valid=1;
     while (!cpu_ready) @(negedge clk);
     @(negedge clk); cpu_valid=0;
   end
 endtask

 task return_line(input [31:0] addr, input [31:0] word);
   begin
     @(negedge clk); mem_rsp_addr=addr; mem_rsp_data=0;
     mem_rsp_data[(addr[4:2])*32 +: 32]=word; mem_rsp_valid=1;
     @(negedge clk); mem_rsp_valid=0;
   end
 endtask

 initial begin
   repeat (2) @(posedge clk); rst_n=1;
   issue_read(32'h00001300);
   @(negedge clk); cache_maint_op=5'b11110; cache_maint_addr=0;
   cache_maint_invalidate=1; #1;
   if (cache_maint_ready || cache_maint_done) begin
     $display("FAIL SYNC accepted with outstanding MSHR"); errors=errors+1;
   end
   return_line(32'h00001300,32'h13000001);
   for (cycles=0; cycles<8 && !cache_maint_done; cycles=cycles+1)
     @(negedge clk);
   if (!cache_maint_done || cache_maint_error) begin
     $display("FAIL SYNC did not complete after drain done=%b err=%b",
              cache_maint_done, cache_maint_error); errors=errors+1;
   end
   cache_maint_invalidate=0;
   if (errors == 0)
     $display("REGRESSION_TEST_SUCCESS l1nb_sync");
   else
     $display("REGRESSION_TEST_FAIL l1nb_sync errors=%0d", errors);
   $finish;
 end
endmodule
