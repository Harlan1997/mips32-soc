`timescale 1ns/1ps
module tb_dcache_attr;
  reg clk=0; always #5 clk=~clk; reg rst_n=0; reg cpu_req=0,cpu_we=0,cpu_uncacheable=0; reg [31:0] cpu_addr=0,cpu_wdata=0; reg [3:0] cpu_be=4'hf; wire [31:0] cpu_rdata; wire cpu_addr_ok,cpu_data_ok,cpu_bus_error,cpu_cache_error;
  wire [3:0] awid,arid; wire [31:0] awaddr,araddr,wdata; wire [7:0] awlen,arlen; wire [2:0] awsize,arsize; wire [1:0] awburst,arburst,awlock,arlock; wire [3:0] awcache,arcache,wstrb; wire [2:0] awprot,arprot; wire awvalid,wvalid,wlast,arvalid; reg awready=1,wready=1,bvalid=0,arready=1,rvalid=0,rlast=1; reg [3:0] bid=0,rid=0; reg [1:0] bresp=0,rresp=0; reg [31:0] rdata=32'hA55A_9014; wire bready,rready; wire [31:0] cache_tag_rdata; reg cache_op_valid=0; reg [4:0] cache_op=0; reg [31:0] cache_op_addr=0,cache_tag_wdata=0; wire cache_op_ready,cache_op_done,cache_op_error; integer errors=0, ar_count=0;
  dcache #(.ENABLE_LEGACY_ADDR_HEURISTIC(1'b0)) dut(.*);
  always @(posedge clk) begin
    if(arvalid&&arready) begin ar_count=ar_count+1; if(araddr!==32'h40009014||arlen!==0||arcache!==0) errors=errors+1; rvalid<=1; end else rvalid<=0;
  end
  initial begin
    repeat(2) @(posedge clk); rst_n=1; @(negedge clk); cpu_addr=32'h40009014; cpu_uncacheable=1; cpu_req=1;
    while(!cpu_addr_ok) @(posedge clk); @(negedge clk); cpu_req=0; while(!cpu_data_ok) @(posedge clk);
    if(ar_count!=1 || cpu_rdata!==32'hA55A_9014) errors=errors+1;
    if(errors==0) $display("REGRESSION_TEST_SUCCESS dcache_attr"); else $display("REGRESSION_TEST_FAILED dcache_attr errors=%0d",errors); $finish;
  end
endmodule
