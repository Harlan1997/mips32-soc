`timescale 1ns/1ps
module tb_axi2apb_bridge;
  reg clk=0; always #5 clk=~clk; reg rst_n=0;
  reg [3:0] awid=4'h3; reg [31:0] awaddr=32'h40009014; reg [7:0] awlen=0; reg [2:0] awsize=2; reg [1:0] awburst=1,awlock=0; reg [3:0] awcache=0; reg [2:0] awprot=0; reg awvalid=0;
  reg [31:0] wdata=32'h1; reg [3:0] wstrb=4'hf; reg wlast=1; reg wvalid=0; reg bready=0;
  reg [3:0] arid=0; reg [31:0] araddr=0; reg [7:0] arlen=0; reg [2:0] arsize=2; reg [1:0] arburst=1,arlock=0; reg [3:0] arcache=0; reg [2:0] arprot=0; reg arvalid=0; reg rready=0;
  wire s_awready,s_wready,s_bvalid,s_arready,s_rvalid,s_rlast; wire [3:0] s_bid,s_rid; wire [1:0] s_bresp,s_rresp; wire [31:0] s_rdata; reg pready=0; reg [31:0] prdata=0; reg pslverr=0; wire [31:0] paddr,pwdata; wire psel,penable,pwrite; wire [3:0] pstrb;
  wire [3:0] s_awid=awid; wire [31:0] s_awaddr=awaddr; wire [7:0] s_awlen=awlen; wire [2:0] s_awsize=awsize; wire [1:0] s_awburst=awburst,s_awlock=awlock; wire [3:0] s_awcache=awcache; wire [2:0] s_awprot=awprot; wire s_awvalid=awvalid;
  wire [31:0] s_wdata=wdata; wire [3:0] s_wstrb=wstrb; wire s_wlast=wlast,s_wvalid=wvalid,s_bready=bready;
  wire [3:0] s_arid=arid; wire [31:0] s_araddr=araddr; wire [7:0] s_arlen=arlen; wire [2:0] s_arsize=arsize; wire [1:0] s_arburst=arburst,s_arlock=arlock; wire [3:0] s_arcache=arcache; wire [2:0] s_arprot=arprot; wire s_arvalid=arvalid,s_rready=rready;
  integer errors=0, setup_count=0, enable_count=0;
  axi2apb_bridge dut(.*);
  always @(posedge clk) begin
    if (psel && !penable) begin setup_count=setup_count+1; if(!pwrite||paddr!==awaddr||pwdata!==wdata) errors=errors+1; end
    if (psel && penable) begin enable_count=enable_count+1; if(!pwrite||paddr!==awaddr||pwdata!==wdata) errors=errors+1; pready<=1; end else pready<=0;
  end
  initial begin
    repeat(2) @(posedge clk); rst_n=1;
    @(negedge clk); awvalid=1; wvalid=1; bready=1;
    @(posedge clk); while(!s_awready || !s_wready) @(posedge clk);
    @(negedge clk); awvalid=0; wvalid=0;
    repeat(5) @(posedge clk);
    if(setup_count!=1 || enable_count<1 || s_bresp!==0) errors=errors+1;
    if(errors==0) $display("REGRESSION_TEST_SUCCESS axi2apb_write_timing"); else $display("REGRESSION_TEST_FAILED axi2apb_write_timing errors=%0d setup=%0d enable=%0d",errors,setup_count,enable_count);
    $finish;
  end
endmodule
