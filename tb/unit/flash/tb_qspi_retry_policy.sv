`timescale 1ns/1ps
module tb_qspi_retry_policy;
 reg clk=0,rst_n=0,start=0,error_valid=0; reg [15:0] error_class=0,error_code=0;
 wire retry_request,terminal_error,busy; wire [1:0] retry_count;
 qspi_retry_policy dut(.clk(clk),.rst_n(rst_n),.start(start),.error_valid(error_valid),.error_class(error_class),.error_code(error_code),.retry_request(retry_request),.terminal_error(terminal_error),.busy(busy),.retry_count(retry_count));
 always #5 clk=~clk;
 task fail; input [127:0] m; begin $display("ERROR: %0s",m);$display("REGRESSION_TEST_FAILED qspi_retry_policy");$finish;end endtask
 initial begin
  repeat(2)@(posedge clk);rst_n=1;
  @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;error_class=1;error_code=1;error_valid=1;@(posedge clk);#1;if(!retry_request||retry_count!=1) fail("timeout retry");error_valid=0;
  @(negedge clk);error_valid=1;@(posedge clk);#1;if(!terminal_error||busy)fail("retry exhaustion");error_valid=0;
  @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;error_class=3;error_code=2;error_valid=1;@(posedge clk);#1;if(!terminal_error||retry_request)fail("CRC incorrectly retried");
  $display("REGRESSION_TEST_SUCCESS qspi_retry_policy");$finish;
 end
endmodule
