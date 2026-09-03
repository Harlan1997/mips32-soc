// APB-visible MMU context contract.  The allocators are intentionally bounded
// (four dynamic leases) for the current frontend/behavioral scope.
module apb_mmu_context_status #(parameter TIMEOUT_CYCLES=16)(
 input wire clk,input wire rst_n,input wire psel,input wire penable,input wire pwrite,
 input wire [7:0] paddr,input wire [31:0] pwdata,output reg [31:0] prdata,
 output wire pready,output wire pslverr,
 output wire invalidate_valid, output wire [7:0] invalidate_asid,
 output wire [18:0] invalidate_vpn, output wire [1:0] invalidate_scope);
 reg [7:0] asid_r,generation_r; reg [19:0] vpn_r; reg [1:0] scope_r; reg [3:0] event_r; reg [5:1] sd_status_r;
 wire wr = psel & penable & pwrite;
 wire rd = psel & penable & ~pwrite;
 wire alloc_req = wr && (paddr[4:2] == 3'b101) && pwdata[0];
 wire release_req = wr && (paddr[4:2] == 3'b110) && pwdata[31];
 wire alloc_valid, alloc_fail, release_valid, release_reject;
 wire [7:0] alloc_asid, alloc_generation;
 wire [7:0] release_asid = pwdata[7:0];
 wire [7:0] release_generation = pwdata[15:8];
 wire root_alloc_req = wr && (paddr[5:2] == 4'd10) && pwdata[0];
 wire root_release_req = wr && (paddr[5:2] == 4'd12) && pwdata[31];
 wire context_alloc_req = wr && (paddr[5:2] == 4'd15) && pwdata[0];
 wire context_release_req = wr && (paddr[5:2] == 4'd15) && pwdata[31];
 reg [31:0] root_release_root_r;
 reg [31:0] root_r;
 reg [7:0] root_generation_r;
 reg [3:0] root_event_r;
 reg [31:0] page_release_page_r;
 reg [31:0] page_r;
 reg [7:0] page_generation_r;
 reg [3:0] page_event_r;
 wire root_alloc_valid, root_alloc_fail, root_release_valid, root_release_reject;
 wire [31:0] root_alloc_root;
 wire [7:0] root_alloc_generation;
 wire context_alloc_valid, context_alloc_fail, context_release_valid, context_release_reject;
 wire [31:0] context_alloc_root;
 wire [7:0] context_alloc_asid, context_alloc_generation;
 wire sd_busy, sd_invalidate_valid, sd_done, sd_timeout, sd_rejected;
 wire [7:0] sd_invalidate_asid;
 wire [19:0] sd_invalidate_vpn;
 wire [1:0] sd_invalidate_scope;
 wire shootdown_req = wr && (paddr[5:2] == 4'd7) && pwdata[0];
 reg [7:0] shootdown_generation_r;
 wire shootdown_ack_write = wr && (paddr[5:2] == 4'd8) && pwdata[0];
 wire shootdown_ack = shootdown_ack_write &&
                      (pwdata[15:8] == shootdown_generation_r);
 wire shootdown_stale_ack = shootdown_ack_write && sd_busy &&
                            (pwdata[15:8] != shootdown_generation_r);
 wire page_alloc_req = wr && (paddr[7:2] == 6'h10) && pwdata[0];
 wire page_release_req = wr && (paddr[7:2] == 6'h12) && pwdata[31];
 wire page_alloc_valid, page_alloc_fail, page_release_valid, page_release_reject;
 wire [31:0] page_alloc_page;
 wire [7:0] page_alloc_generation;

 // The CPU-visible APB path needs room for an uncached read/ack round trip.
 // Keep the standalone mailbox default short, but use a 64-cycle integration
 // window so a legal software acknowledgment is not lost in bridge latency.
 mmu_tlb_shootdown_mailbox #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_shootdown (
   .clk(clk), .rst_n(rst_n), .req_valid(shootdown_req), .req_asid(asid_r),
   .req_vpn(vpn_r), .req_scope(scope_r), .target_present(1'b1),
   .target_ack(shootdown_ack), .busy(sd_busy),
   .invalidate_valid(sd_invalidate_valid), .invalidate_asid(sd_invalidate_asid),
   .invalidate_vpn(sd_invalidate_vpn), .invalidate_scope(sd_invalidate_scope),
   .done(sd_done), .timeout(sd_timeout), .rejected(sd_rejected));

 mmu_asid_allocator #(.SLOTS(4)) u_allocator (
   .clk(clk), .rst_n(rst_n), .alloc_req(alloc_req), .alloc_valid(alloc_valid),
   .alloc_fail(alloc_fail), .alloc_asid(alloc_asid),
   .alloc_generation(alloc_generation), .release_req(release_req),
   .release_asid(release_asid), .release_generation(release_generation),
   .release_valid(release_valid), .release_reject(release_reject));

 mmu_page_table_allocator #(.SLOTS(4)) u_root_allocator (
   .clk(clk), .rst_n(rst_n), .alloc_req(root_alloc_req),
   .alloc_valid(root_alloc_valid), .alloc_fail(root_alloc_fail),
   .alloc_root(root_alloc_root), .alloc_generation(root_alloc_generation),
   .release_req(root_release_req), .release_root(root_release_root_r),
   .release_generation(pwdata[7:0]), .release_valid(root_release_valid),
   .release_reject(root_release_reject));

 mmu_page_frame_allocator #(.SLOTS(16), .PAGE_BASE(32'h0000_6000),
                            .PAGE_STRIDE(32'h0000_1000)) u_page_allocator (
   .clk(clk), .rst_n(rst_n), .alloc_req(page_alloc_req),
   .alloc_valid(page_alloc_valid), .alloc_fail(page_alloc_fail),
   .alloc_page(page_alloc_page), .alloc_generation(page_alloc_generation),
   .release_req(page_release_req), .release_page(page_release_page_r),
   .release_generation(pwdata[7:0]), .release_valid(page_release_valid),
   .release_reject(page_release_reject));

 mmu_context_allocator #(.SLOTS(4)) u_context_allocator (
   .clk(clk), .rst_n(rst_n), .alloc_req(context_alloc_req),
   .alloc_valid(context_alloc_valid), .alloc_fail(context_alloc_fail),
   .alloc_root(context_alloc_root), .alloc_asid(context_alloc_asid),
   .alloc_generation(context_alloc_generation),
   .release_req(context_release_req), .release_root(root_release_root_r),
   .release_asid(pwdata[7:0]), .release_generation(pwdata[15:8]),
   .release_valid(context_release_valid), .release_reject(context_release_reject));

 assign pready = 1'b1;
 assign pslverr = 1'b0;
 assign invalidate_valid = sd_invalidate_valid;
 assign invalidate_asid = sd_invalidate_asid;
 // APB contract carries a 20-bit page number (VA[31:12]); the TLB sideband
 // consumes VPN2 (VA[31:13]).
 assign invalidate_vpn = sd_invalidate_vpn[19:1];
 assign invalidate_scope = sd_invalidate_scope;

 always @(posedge clk or negedge rst_n) begin
   if (!rst_n) begin
     asid_r <= 0; generation_r <= 0; vpn_r <= 0; scope_r <= 0; event_r <= 0; sd_status_r <= 0;
     root_release_root_r <= 0; root_r <= 0; root_generation_r <= 0; root_event_r <= 0;
     page_release_page_r <= 0; page_r <= 0; page_generation_r <= 0; page_event_r <= 0;
     shootdown_generation_r <= 0;
   end else begin
     if (alloc_valid) begin
       asid_r <= alloc_asid;
       generation_r <= alloc_generation;
       event_r[0] <= 1'b1;
     end
     if (alloc_fail) event_r[1] <= 1'b1;
     if (release_valid) event_r[2] <= 1'b1;
     if (release_reject) event_r[3] <= 1'b1;
     if (root_alloc_valid) begin
       root_r <= root_alloc_root;
       root_generation_r <= root_alloc_generation;
       root_event_r[0] <= 1'b1;
     end
     if (root_alloc_fail) root_event_r[1] <= 1'b1;
     if (root_release_valid) root_event_r[2] <= 1'b1;
     if (root_release_reject) root_event_r[3] <= 1'b1;
     if (page_alloc_valid) begin
       page_r <= page_alloc_page;
       page_generation_r <= page_alloc_generation;
       page_event_r[0] <= 1'b1;
     end
     if (page_alloc_fail) page_event_r[1] <= 1'b1;
     if (page_release_valid) page_event_r[2] <= 1'b1;
     if (page_release_reject) page_event_r[3] <= 1'b1;
     if (context_alloc_valid) begin
       asid_r <= context_alloc_asid;
       generation_r <= context_alloc_generation;
       root_r <= context_alloc_root;
       root_generation_r <= context_alloc_generation;
       event_r[0] <= 1'b1;
       root_event_r[0] <= 1'b1;
     end
     if (context_alloc_fail) begin
       event_r[1] <= 1'b1;
       root_event_r[1] <= 1'b1;
     end
     if (context_release_valid) begin
       event_r[2] <= 1'b1;
       root_event_r[2] <= 1'b1;
     end
     if (context_release_reject) begin
       event_r[3] <= 1'b1;
       root_event_r[3] <= 1'b1;
     end
     if (shootdown_req) sd_status_r <= 0;
     if (sd_invalidate_valid) sd_status_r[1] <= 1'b1;
     if (sd_done) sd_status_r[2] <= 1'b1;
     if (sd_timeout) sd_status_r[3] <= 1'b1;
     if (sd_rejected) sd_status_r[4] <= 1'b1;
     if (shootdown_stale_ack) sd_status_r[5] <= 1'b1;
     if (shootdown_req) shootdown_generation_r <= generation_r;
     if (wr) case (paddr[4:2])
       4'd0: begin asid_r <= pwdata[7:0]; generation_r <= pwdata[15:8]; end
       4'd1: vpn_r <= pwdata[19:0];
       4'd2: scope_r <= pwdata[1:0];
       4'd3: event_r <= event_r | pwdata[3:0];
       4'd4: event_r <= event_r & ~pwdata[3:0];
       default: ; // 0x14 allocate and 0x18 release are command-only
     endcase
     if (wr && (paddr[5:2] == 4'd11))
       root_release_root_r <= pwdata;
     if (wr && (paddr[5:2] == 4'd13))
       root_event_r <= root_event_r | pwdata[3:0];
     if (wr && (paddr[5:2] == 4'd14))
       root_event_r <= root_event_r & ~pwdata[3:0];
     if (wr && (paddr[7:2] == 6'h11))
       page_release_page_r <= pwdata;
     if (wr && (paddr[7:2] == 6'h14))
       page_event_r <= page_event_r & ~pwdata[3:0];
   end
 end

 always @(*) begin
   prdata = 32'b0;
   if (rd) case (paddr[7:2])
     4'd0: prdata = {16'h0, generation_r, asid_r};
     4'd1: prdata = {12'h0, vpn_r};
     4'd2: prdata = {30'h0, scope_r};
     4'd3: prdata = {28'h0, event_r};
     4'd9: prdata = {26'h0, sd_status_r[5], sd_status_r[4], sd_status_r[3], sd_status_r[2],
                     sd_status_r[1], sd_busy};
     4'd10: prdata = root_r;
     4'd11: prdata = {24'h0, root_generation_r};
     4'd13: prdata = {28'h0, root_event_r};
     6'h10: prdata = page_r;
     6'h11: prdata = {24'h0, page_generation_r};
     6'h13: prdata = {28'h0, page_event_r};
     default: prdata = 32'b0;
   endcase
 end
endmodule
