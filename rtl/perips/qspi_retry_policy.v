// Vendor-neutral bounded retry policy for QSPI boot/transport errors.
module qspi_retry_policy #(parameter MAX_RETRIES=1) (
 input wire clk,input wire rst_n,input wire start,
 input wire error_valid,input wire [15:0] error_class,input wire [15:0] error_code,
 output reg retry_request,output reg terminal_error,output reg busy,
 output reg [1:0] retry_count);
 wire retryable = (error_class==16'h0001 && error_code==16'h0001) ||
                  (error_class==16'h0004 && error_code==16'h0001);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin retry_request<=0;terminal_error<=0;busy<=0;retry_count<=0; end
  else begin
   retry_request<=0;terminal_error<=0;
   if(start) begin busy<=1;retry_count<=0; end
   if(busy && error_valid) begin
    if(retryable && retry_count<MAX_RETRIES) begin retry_request<=1;retry_count<=retry_count+1'b1; end
    else begin terminal_error<=1;busy<=0; end
   end
  end
 end
endmodule
