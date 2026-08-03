`timescale 1ns/1ps
module tb_qspi_error_taxonomy;
 reg clk=0,rst_n=0,controller_present=1,timeout_sticky=0,error_event=0;
 reg [31:0] error_value=0; reg psel=0,penable=0,pwrite=0; reg [4:0] paddr=0; reg [31:0] pwdata=0;
 wire [31:0] prdata; wire pready,pslverr;
 apb_qspi_status dut(.clk(clk),.rst_n(rst_n),.controller_present(controller_present),.xip_timeout_sticky(timeout_sticky),.error_event(error_event),.error_value(error_value),.psel(psel),.penable(penable),.pwrite(pwrite),.paddr(paddr),.pwdata(pwdata),.prdata(prdata),.pready(pready),.pslverr(pslverr));
 always #5 clk=~clk;
 task read_error; begin @(negedge clk); psel=1;penable=1;pwrite=0;paddr=5'h08; @(posedge clk); #1; @(negedge clk);psel=0;penable=0; end endtask
 task clear_error; begin @(negedge clk);psel=1;penable=1;pwrite=1;paddr=5'h0c;pwdata=1; @(posedge clk); @(negedge clk);psel=0;penable=0;pwrite=0; end endtask
 initial begin
  repeat(2) @(posedge clk); rst_n=1; @(posedge clk);
  error_value=32'h0003_0002; error_event=1; @(posedge clk); error_event=0; read_error;
  if(prdata!==32'h0003_0002) begin $display("REGRESSION_TEST_FAILED qspi_error_taxonomy generic=%h",prdata);$finish;end
  error_value=32'h0006_0001; error_event=1; @(posedge clk); error_event=0; read_error;
  if(prdata!==32'h0003_0002) begin $display("REGRESSION_TEST_FAILED qspi_error_taxonomy overwrite=%h",prdata);$finish;end
  clear_error; read_error;
  if(prdata!==32'h0) begin $display("REGRESSION_TEST_FAILED qspi_error_taxonomy clear=%h",prdata);$finish;end
  $display("REGRESSION_TEST_SUCCESS qspi_error_taxonomy"); $finish;
 end
endmodule
