module mmu_ipi_shootdown #(parameter TIMEOUT_CYCLES=16) (
 input wire clk, input wire rst_n,
 input wire send_valid, input wire send_target, input wire [7:0] send_generation,
 input wire [7:0] send_asid, input wire [19:0] send_vpn, input wire [1:0] send_scope,
 input wire target_present, input wire ack_valid, input wire ack_target,
 input wire [7:0] ack_generation,
 output reg busy, output reg pending, output reg invalidate_valid,
 output reg invalidate_target, output reg [7:0] invalidate_generation,
 output reg [7:0] invalidate_asid, output reg [19:0] invalidate_vpn,
 output reg [1:0] invalidate_scope, output reg done, output reg timeout,
 output reg rejected, output reg stale_ack
);
 localparam integer CW=(TIMEOUT_CYCLES<=1)?1:$clog2(TIMEOUT_CYCLES+1);
 reg [CW-1:0] count; reg issued;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   busy<=0; pending<=0; invalidate_valid<=0; invalidate_target<=0;
   invalidate_generation<=0; invalidate_asid<=0; invalidate_vpn<=0;
   invalidate_scope<=0; done<=0; timeout<=0; rejected<=0; stale_ack<=0;
   count<=0; issued<=0;
  end else begin
   invalidate_valid<=0; done<=0; timeout<=0; rejected<=0; stale_ack<=0;
   if(!busy) begin
    pending<=0;
    if(send_valid) begin
     invalidate_target<=send_target; invalidate_generation<=send_generation;
     invalidate_asid<=send_asid; invalidate_vpn<=send_vpn;
     invalidate_scope<=send_scope; count<=0; issued<=0;
     if(target_present) begin busy<=1; pending<=1; end
     else begin busy<=0; timeout<=1; end
    end
   end else begin
    pending<=1;
    if(send_valid) rejected<=1;
    if(!issued) begin invalidate_valid<=1; issued<=1; end
    if(ack_valid && (ack_target!=invalidate_target || ack_generation!=invalidate_generation))
      stale_ack<=1;
    if(ack_valid && ack_target==invalidate_target && ack_generation==invalidate_generation) begin
     busy<=0; pending<=0; done<=1; count<=0;
    end else if(!target_present || count>=TIMEOUT_CYCLES-1) begin
     busy<=0; pending<=0; timeout<=1; count<=0;
    end else count<=count+1'b1;
   end
  end
 end
endmodule
