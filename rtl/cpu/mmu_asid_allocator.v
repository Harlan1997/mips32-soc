// Deterministic frontend ASID lease allocator.
// ASID 0 is reserved; slots 1..SLOTS are recycled only with a matching
// generation token. This is a contract model, not an OS page-table walker.
module mmu_asid_allocator #(parameter SLOTS=4) (
 input wire clk,input wire rst_n,
 input wire alloc_req, output reg alloc_valid, output reg alloc_fail,
 output reg [7:0] alloc_asid, output reg [7:0] alloc_generation,
 input wire release_req,input wire [7:0] release_asid,input wire [7:0] release_generation,
 output reg release_valid, output reg release_reject);
 reg [SLOTS:0] used;
 reg [7:0] generation [0:SLOTS];
 integer i; reg found;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   used <= {(SLOTS+1){1'b0}}; used[0] <= 1'b1;
   alloc_valid<=0;alloc_fail<=0;alloc_asid<=0;alloc_generation<=0;release_valid<=0;release_reject<=0;
   for(i=0;i<=SLOTS;i=i+1) generation[i]<=0;
  end else begin
   alloc_valid<=0;alloc_fail<=0;release_valid<=0;release_reject<=0;
   if(release_req) begin
    if(release_asid!=0 && release_asid<=SLOTS && used[release_asid] && generation[release_asid]===release_generation) begin
     used[release_asid]<=0; generation[release_asid]<=generation[release_asid]+1'b1; release_valid<=1;
    end else release_reject<=1;
   end
   if(alloc_req) begin
    found=0;
    for(i=1;i<=SLOTS;i=i+1) begin
     if(!used[i] && !found) begin
      used[i]<=1; alloc_asid<=i[7:0]; alloc_generation<=generation[i]; alloc_valid<=1; found=1;
     end
    end
    if(!found) alloc_fail<=1;
   end
  end
 end
endmodule
