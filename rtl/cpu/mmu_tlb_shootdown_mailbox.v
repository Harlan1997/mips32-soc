module mmu_tlb_shootdown_mailbox #(parameter TIMEOUT_CYCLES=16) (
 input wire clk,input wire rst_n,input wire req_valid,input wire [7:0] req_asid,
 input wire [19:0] req_vpn,input wire [1:0] req_scope,input wire target_present,
 input wire target_ack,output reg busy,output reg invalidate_valid,
 output reg [7:0] invalidate_asid,output reg [19:0] invalidate_vpn,
 output reg [1:0] invalidate_scope,output reg done,output reg timeout,output reg rejected);
 localparam integer CW=(TIMEOUT_CYCLES<=1)?1:$clog2(TIMEOUT_CYCLES+1);
 reg [CW-1:0] count; reg issued;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin busy<=0;invalidate_valid<=0;invalidate_asid<=0;invalidate_vpn<=0;invalidate_scope<=0;done<=0;timeout<=0;rejected<=0;count<=0;issued<=0; end
  else begin
   invalidate_valid<=0; done<=0; timeout<=0; rejected<=0;
   if(!busy) begin if(req_valid) begin invalidate_asid<=req_asid;invalidate_vpn<=req_vpn;invalidate_scope<=req_scope;count<=0;issued<=0; if(!target_present) begin busy<=0;timeout<=1; end else busy<=1; end end
   else begin
    if(req_valid) rejected<=1;
    if(!issued) begin invalidate_valid<=1; issued<=1; end
    if(target_present && target_ack) begin busy<=0;done<=1;count<=0; end
    else if(!target_present || count>=TIMEOUT_CYCLES-1) begin busy<=0;timeout<=1;count<=0; end
    else count<=count+1'b1;
   end
  end
 end
endmodule
