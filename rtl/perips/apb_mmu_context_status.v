// APB-visible MMU context contract.  The allocator is intentionally bounded
// (four dynamic leases) for the current frontend/behavioral scope.
module apb_mmu_context_status(
 input wire clk,input wire rst_n,input wire psel,input wire penable,input wire pwrite,
 input wire [4:0] paddr,input wire [31:0] pwdata,output reg [31:0] prdata,
 output wire pready,output wire pslverr);
 reg [7:0] asid_r,generation_r; reg [19:0] vpn_r; reg [1:0] scope_r; reg [3:0] event_r;
 wire wr = psel & penable & pwrite;
 wire rd = psel & penable & ~pwrite;
 wire alloc_req = wr && (paddr[4:2] == 3'b101) && pwdata[0];
 wire release_req = wr && (paddr[4:2] == 3'b110) && pwdata[31];
 wire alloc_valid, alloc_fail, release_valid, release_reject;
 wire [7:0] alloc_asid, alloc_generation;
 wire [7:0] release_asid = pwdata[7:0];
 wire [7:0] release_generation = pwdata[15:8];

 mmu_asid_allocator #(.SLOTS(4)) u_allocator (
   .clk(clk), .rst_n(rst_n), .alloc_req(alloc_req), .alloc_valid(alloc_valid),
   .alloc_fail(alloc_fail), .alloc_asid(alloc_asid),
   .alloc_generation(alloc_generation), .release_req(release_req),
   .release_asid(release_asid), .release_generation(release_generation),
   .release_valid(release_valid), .release_reject(release_reject));

 assign pready = 1'b1;
 assign pslverr = 1'b0;

 always @(posedge clk or negedge rst_n) begin
   if (!rst_n) begin
     asid_r <= 0; generation_r <= 0; vpn_r <= 0; scope_r <= 0; event_r <= 0;
   end else begin
     if (alloc_valid) begin
       asid_r <= alloc_asid;
       generation_r <= alloc_generation;
       event_r[0] <= 1'b1;
     end
     if (alloc_fail) event_r[1] <= 1'b1;
     if (release_valid) event_r[2] <= 1'b1;
     if (release_reject) event_r[3] <= 1'b1;
     if (wr) case (paddr[4:2])
       3'b000: begin asid_r <= pwdata[7:0]; generation_r <= pwdata[15:8]; end
       3'b001: vpn_r <= pwdata[19:0];
       3'b010: scope_r <= pwdata[1:0];
       3'b011: event_r <= event_r | pwdata[3:0];
       3'b100: event_r <= event_r & ~pwdata[3:0];
       default: ; // 0x14 allocate and 0x18 release are command-only
     endcase
   end
 end

 always @(*) begin
   prdata = 32'b0;
   if (rd) case (paddr[4:2])
     3'b000: prdata = {16'h0, generation_r, asid_r};
     3'b001: prdata = {12'h0, vpn_r};
     3'b010: prdata = {30'h0, scope_r};
     3'b011: prdata = {28'h0, event_r};
     default: prdata = 32'b0;
   endcase
 end
endmodule
