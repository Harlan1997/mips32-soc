// Ownership boundary between the hardware page-table walker and mips_tlb.
// The arbiter accepts one miss at a time and holds the TLB write request until
// the CP0/TLB side grants it. The normal CP0 TLBWI/TLBWR path remains the other
// owner and must be arbitrated externally with this request.
module mips_page_table_tlb_refill (
    input wire clk, input wire rst_n,
    input wire miss_valid, output wire miss_ready,
    input wire [31:0] miss_va, input wire [31:0] ptbr,
    input wire [1:0] miss_access, input wire miss_user,
    output wire mem_valid, output wire [31:0] mem_addr,
    input wire mem_ready, input wire [31:0] mem_rdata, input wire mem_error,
    output wire walk_resp_valid, output wire walk_fault_valid,
    output wire [2:0] walk_fault_code, output wire [31:0] walk_pa,
    output wire tlb_wr_valid, input wire tlb_wr_ready,
    output wire [18:0] tlb_wr_vpn2, output wire [7:0] tlb_wr_asid,
    input wire [7:0] miss_asid,
    output wire [15:0] tlb_wr_mask,
    output wire [31:0] tlb_wr_entrylo0, output wire [31:0] tlb_wr_entrylo1
);
    wire req_ready, resp_valid, fault_valid;
    wire [31:0] pa, leaf_pte;
    wire [2:0] fault_code;
    reg refill_pending;
    reg resp_seen;
    reg grant_seen;
    reg [31:0] va_q;
    reg [7:0] asid_q;

    mips_page_table_walker u_walker (
        .clk(clk), .rst_n(rst_n), .req_valid(miss_valid && miss_ready),
        .req_ready(req_ready), .ptbr(ptbr), .va(miss_va), .access(miss_access),
        .user_mode(miss_user), .mem_valid(mem_valid), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_error(mem_error),
        .resp_valid(resp_valid), .pa(pa), .fault_valid(fault_valid),
        .fault_code(fault_code), .leaf_pte(leaf_pte)
    );

    assign miss_ready = req_ready && !refill_pending;
    assign walk_resp_valid = resp_valid;
    assign walk_fault_valid = resp_valid && fault_valid;
    assign walk_fault_code = fault_code;
    assign walk_pa = pa;
    assign tlb_wr_valid = refill_pending && !grant_seen;
    assign tlb_wr_vpn2 = va_q[31:13];
    assign tlb_wr_asid = asid_q;
    assign tlb_wr_mask = 16'h0000;
    // MIPS EntryLo: PFN[29:6], C=3, D follows PTE.W, V follows PTE.V,
    // global remains software-owned and is zero for hardware refills.  The
    // walker resolves one 4KB leaf, so leave the other half invalid instead
    // of aliasing both halves to the same physical page.
    wire [31:0] entrylo = {2'b0, 4'b0, leaf_pte[31:12], 3'b011,
                           leaf_pte[1], leaf_pte[0], 1'b0};
    assign tlb_wr_entrylo0 = va_q[12] ? 32'd0 : entrylo;
    assign tlb_wr_entrylo1 = va_q[12] ? entrylo : 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin refill_pending <= 1'b0; resp_seen <= 1'b0; grant_seen <= 1'b0; va_q <= 0; asid_q <= 0; end
        else begin
            if (miss_valid && miss_ready) begin va_q <= miss_va; asid_q <= miss_asid; end
            if (!resp_valid) resp_seen <= 1'b0;
            if (!resp_valid && !refill_pending) grant_seen <= 1'b0;
            if (resp_valid && !fault_valid && !refill_pending && !tlb_wr_ready && !resp_seen) begin
                refill_pending <= 1'b1;
                resp_seen <= 1'b1;
            end
            if (refill_pending && tlb_wr_ready) begin
                refill_pending <= 1'b0;
                grant_seen <= 1'b1;
            end
        end
    end
endmodule
