// =============================================================================
// File Name : mips_tlb.v
// Module    : mips_tlb
// Design    : MIPS32 R2 TLB data array (Phase B.3.b baseline)
// Standard  : Verilog-2001 (synthesizable)
// Reset     : posedge clk / negedge rst_n
//
// Phase B.3.b scope:
//   - 64-entry fully-associative TLB (parameterized).
//   - Per-entry storage: {VPN2, ASID, PageMask.Mask, G, EntryLo0, EntryLo1,
//     valid}.
//   - Three synchronous access ports:
//       * write   port: TLBWI / TLBWR from CP0 (index provided by caller)
//       * read    port: TLBR  → returns entry fields for CP0 write-back
//       * probe   port: TLBP  → returns {hit, hit_index} for CP0 Index write
//   - Probe honours per-entry PageMask so future page sizes work correctly.
//
// Address translation lookup port (for I-cache / D-cache / MEM stage) is
// deferred to Phase B.3.c; only CP0-visible ops are implemented here.
// =============================================================================

`include "soc_config.vh"

module mips_tlb #(
    parameter TLB_ENTRIES = `SOC_CP0_TLB_ENTRIES,
    parameter INDEX_BITS  = `SOC_CP0_TLB_INDEX_BITS
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write port (TLBWI / TLBWR)
    input  wire                  wr_en,
    input  wire [INDEX_BITS-1:0] wr_index,
    input  wire [18:0]           wr_vpn2,      // EntryHi[31:13]
    input  wire [7:0]            wr_asid,      // EntryHi[7:0]
    input  wire [15:0]           wr_mask,      // PageMask[28:13]
    input  wire [31:0]           wr_entrylo0,  // full 32-bit EntryLo0
    input  wire [31:0]           wr_entrylo1,  // full 32-bit EntryLo1

    // Optional invalidate sideband: scope 0=page, 1=ASID, 2=all dynamic.
    // Entries below inv_wired_floor are preserved by the TLB itself.
    input  wire                  inv_en,
    input  wire [18:0]           inv_vpn2,
    input  wire [7:0]            inv_asid,
    input  wire [1:0]            inv_scope,
    input  wire [INDEX_BITS-1:0] inv_wired_floor,

    // Architectural context changes invalidate translations that may have
    // been cached below the main TLB.  This is separate from inv_en so an
    // ASID/PageMask MTC0 or a scheduler context restore cannot leave stale
    // micro-TLB state behind.
    input  wire                   context_flush,

    // Read port (TLBR): combinational
    input  wire [INDEX_BITS-1:0] rd_index,
    output wire [18:0]           rd_vpn2,
    output wire [7:0]            rd_asid,
    output wire [15:0]           rd_mask,
    output wire [31:0]           rd_entrylo0,
    output wire [31:0]           rd_entrylo1,

    // Probe port (TLBP): combinational
    input  wire [18:0]           probe_vpn2,
    input  wire [7:0]            probe_asid,
    output wire                  probe_hit,
    output wire [INDEX_BITS-1:0] probe_index,
    output wire                  probe_multi_hit,

    // Address-translation lookup ports (Phase B.3.c). Combinational.
    // Two ports (I-fetch + D-load/store) let both pipeline sides translate in
    // the same cycle. Callers (mips_mmu) supply the full VA and gate the port
    // to only useg/kseg2/kseg3 accesses; kseg0/kseg1 direct-map does not touch
    // the TLB. Sub-page selection is derived from the matching entry's
    // PageMask, so larger MIPS even/odd page pairs select the correct
    // EntryLo half.
    input  wire [31:0]           lookup0_va,
    input  wire [7:0]            lookup0_asid,
    output wire                  lookup0_hit,
    output wire                  lookup0_v,
    output wire                  lookup0_d,
    output wire [2:0]            lookup0_c,
    output wire [19:0]           lookup0_pfn,
    output wire                  lookup0_multi_hit,

    input  wire [31:0]           lookup1_va,
    input  wire [7:0]            lookup1_asid,
    output wire                  lookup1_hit,
    output wire                  lookup1_v,
    output wire                  lookup1_d,
    output wire [2:0]            lookup1_c,
    output wire [19:0]           lookup1_pfn,
    output wire                  lookup1_multi_hit,
    output wire                  inv_applied
);

    // -------------------------------------------------------------------------
    // Storage arrays
    // -------------------------------------------------------------------------
    reg [18:0] tlb_vpn2      [0:TLB_ENTRIES-1];
    reg [7:0]  tlb_asid      [0:TLB_ENTRIES-1];
    reg [15:0] tlb_mask      [0:TLB_ENTRIES-1];  // PageMask.Mask field
    reg        tlb_g         [0:TLB_ENTRIES-1];  // combined G = Lo0.G & Lo1.G
    reg [31:0] tlb_entrylo0  [0:TLB_ENTRIES-1];
    reg [31:0] tlb_entrylo1  [0:TLB_ENTRIES-1];
    reg        tlb_valid     [0:TLB_ENTRIES-1];  // TLBWI/TLBWR mark valid; reset clears

    // -------------------------------------------------------------------------
    // Read (TLBR): asynchronous — combinational read from the storage array.
    // The G field returns the OR-back into both Lo0/Lo1 based on the stored
    // combined G bit so software round-trips work (writing G=1 in both Lo0/Lo1
    // then TLBR reads back G=1 in both).
    // -------------------------------------------------------------------------
    assign rd_vpn2     = tlb_vpn2[rd_index];
    assign rd_asid     = tlb_asid[rd_index];
    assign rd_mask     = tlb_mask[rd_index];
    // Splice combined G back into bit [0] of each EntryLo readback so caller
    // reconstruction is round-trip clean.
    assign rd_entrylo0 = { tlb_entrylo0[rd_index][31:1], tlb_g[rd_index] };
    assign rd_entrylo1 = { tlb_entrylo1[rd_index][31:1], tlb_g[rd_index] };

    // -------------------------------------------------------------------------
    // Probe (TLBP): fully-associative match — combinational.
    // For each entry, ignore VPN2 bits that fall under the entry's PageMask.
    // Match ASID unless entry is global (G=1).
    // On multiple hits, return the smallest index (parallel priority encoder).
    // -------------------------------------------------------------------------
    wire [TLB_ENTRIES-1:0] hit_vec;
    genvar gi;
    generate
        for (gi = 0; gi < TLB_ENTRIES; gi = gi + 1) begin : g_probe
            // Compare mask: bit N of tlb_mask ignores VPN2 bit N (VA bit 13+N).
            // Upper 3 bits of VPN2 (bits [18:16], corresponding to VA[31:29])
            // are always compared regardless of PageMask.
            wire [18:0] cmp_mask = { 3'b111, ~tlb_mask[gi] };
            wire vpn2_match = tlb_valid[gi] &&
                              (((tlb_vpn2[gi] ^ probe_vpn2) & cmp_mask) == 19'b0);
            wire asid_match = tlb_g[gi] || (tlb_asid[gi] == probe_asid);
            assign hit_vec[gi] = vpn2_match && asid_match;
        end
    endgenerate

    // Priority-encode smallest-index hit
    reg [INDEX_BITS-1:0] probe_index_r;
    reg                  probe_hit_r;
    reg                  probe_multi_hit_r;
    integer j;
    always @(*) begin
        probe_hit_r   = 1'b0;
        probe_index_r = {INDEX_BITS{1'b0}};
        probe_multi_hit_r = 1'b0;
        for (j = TLB_ENTRIES - 1; j >= 0; j = j - 1) begin
            if (hit_vec[j]) begin
                if (probe_hit_r &&
                    ((tlb_vpn2[j] != tlb_vpn2[probe_index_r]) ||
                     (tlb_asid[j] != tlb_asid[probe_index_r]) ||
                     (tlb_mask[j] != tlb_mask[probe_index_r]) ||
                     (tlb_entrylo0[j] != tlb_entrylo0[probe_index_r]) ||
                     (tlb_entrylo1[j] != tlb_entrylo1[probe_index_r])))
                    probe_multi_hit_r = 1'b1;
                probe_hit_r   = 1'b1;
                probe_index_r = j[INDEX_BITS-1:0];
            end
        end
    end
    assign probe_hit   = probe_hit_r;
    assign probe_index = probe_index_r;
    assign probe_multi_hit = probe_multi_hit_r;

    // -------------------------------------------------------------------------
    // Lookup ports (Phase B.3.c): combinational address translation.
    // Two parallel ports (0 = I-side, 1 = D-side) share the same TLB storage.
    // Each uses the probe match rule and additionally selects even/odd sub-page
    // via the matching entry's PageMask to expose V/D/C/PFN.
    // -------------------------------------------------------------------------

    // MIPS PageMask encodings are contiguous low-one fields.  The even/odd
    // selector is the VA bit immediately above the masked page-offset range.
    // Keep the supported architectural encodings explicit; an invalid mask
    // falls back to the 4 KiB contract rather than creating an X-dependent
    // variable index.
    function [5:0] page_odd_bit_index;
        input [15:0] mask;
        begin
            case (mask)
                16'h0000: page_odd_bit_index = 6'd12;
                16'h0003: page_odd_bit_index = 6'd14;
                16'h000f: page_odd_bit_index = 6'd16;
                16'h003f: page_odd_bit_index = 6'd18;
                16'h00ff: page_odd_bit_index = 6'd20;
                16'h03ff: page_odd_bit_index = 6'd22;
                16'h0fff: page_odd_bit_index = 6'd24;
                16'h3fff: page_odd_bit_index = 6'd26;
                default:  page_odd_bit_index = 6'd12;
            endcase
        end
    endfunction

    // The MMU consumes a conventional {PFN, VA[11:0]} address. For a larger
    // page, fold the additional page-offset bits (VA[13:12], VA[15:12], ...)
    // into the low PFN bits so that the existing interface still produces the
    // complete physical address without losing the offset above bit 11.
    function [19:0] effective_pfn;
        input [19:0] pfn;
        input [31:0] va;
        input [15:0] mask;
        begin
            effective_pfn = pfn;
            case (mask)
                16'h0003: effective_pfn = {pfn[19:2], va[13:12]};
                16'h000f: effective_pfn = {pfn[19:4], va[15:12]};
                16'h003f: effective_pfn = {pfn[19:6], va[17:12]};
                16'h00ff: effective_pfn = {pfn[19:8], va[19:12]};
                16'h03ff: effective_pfn = {pfn[19:10], va[21:12]};
                16'h0fff: effective_pfn = {pfn[19:12], va[23:12]};
                16'h3fff: effective_pfn = {pfn[19:14], va[25:12]};
                default:  effective_pfn = pfn;
            endcase
        end
    endfunction

    // Port 0 (I-side)
    wire [18:0] lookup0_vpn2 = lookup0_va[31:13];
    wire [TLB_ENTRIES-1:0] lookup0_hit_vec;
    generate
        for (gi = 0; gi < TLB_ENTRIES; gi = gi + 1) begin : g_lookup0
            wire [18:0] cmp0_mask = { 3'b111, ~tlb_mask[gi] };
            wire vpn2_match0 = tlb_valid[gi] &&
                               (((tlb_vpn2[gi] ^ lookup0_vpn2) & cmp0_mask) == 19'b0);
            wire asid_match0 = tlb_g[gi] || (tlb_asid[gi] == lookup0_asid);
            assign lookup0_hit_vec[gi] = vpn2_match0 && asid_match0;
        end
    endgenerate
    reg [INDEX_BITS-1:0] lookup0_hit_index_r;
    reg                  lookup0_hit_r;
    reg                  lookup0_multi_hit_r;
    integer m0;
    always @(*) begin
        lookup0_hit_r       = 1'b0;
        lookup0_hit_index_r = {INDEX_BITS{1'b0}};
        lookup0_multi_hit_r = 1'b0;
        for (m0 = TLB_ENTRIES - 1; m0 >= 0; m0 = m0 - 1) begin
            if (lookup0_hit_vec[m0]) begin
                if (lookup0_hit_r &&
                    ((tlb_vpn2[m0] != tlb_vpn2[lookup0_hit_index_r]) ||
                     (tlb_asid[m0] != tlb_asid[lookup0_hit_index_r]) ||
                     (tlb_mask[m0] != tlb_mask[lookup0_hit_index_r]) ||
                     (tlb_entrylo0[m0] != tlb_entrylo0[lookup0_hit_index_r]) ||
                     (tlb_entrylo1[m0] != tlb_entrylo1[lookup0_hit_index_r])))
                    lookup0_multi_hit_r = 1'b1;
                lookup0_hit_r       = 1'b1;
                lookup0_hit_index_r = m0[INDEX_BITS-1:0];
            end
        end
    end
    wire micro_i_hit, micro_i_multi, micro_i_v, micro_i_d;
    wire [2:0] micro_i_c;
    wire [19:0] micro_i_pfn;
    wire micro_d_hit, micro_d_multi, micro_d_v, micro_d_d;
    wire [2:0] micro_d_c;
    wire [19:0] micro_d_pfn;

    assign lookup0_hit = (`SOC_MICRO_TLB_ENABLE) ?
                         (micro_i_hit | lookup0_hit_r) : lookup0_hit_r;
    assign lookup0_multi_hit = (`SOC_MICRO_TLB_ENABLE && micro_i_hit) ?
                               micro_i_multi : lookup0_multi_hit_r;
    wire [5:0] lookup0_odd_bit = page_odd_bit_index(tlb_mask[lookup0_hit_index_r]);
    wire        lookup0_odd = lookup0_va[lookup0_odd_bit];
    wire [31:0] sel_lo0 = lookup0_odd ? tlb_entrylo1[lookup0_hit_index_r]
                                      : tlb_entrylo0[lookup0_hit_index_r];
    assign lookup0_v   = (`SOC_MICRO_TLB_ENABLE && micro_i_hit) ? micro_i_v : sel_lo0[1];
    assign lookup0_d   = (`SOC_MICRO_TLB_ENABLE && micro_i_hit) ? micro_i_d : sel_lo0[2];
    assign lookup0_c   = (`SOC_MICRO_TLB_ENABLE && micro_i_hit) ? micro_i_c : sel_lo0[5:3];
    assign lookup0_pfn = (`SOC_MICRO_TLB_ENABLE && micro_i_hit) ? micro_i_pfn :
                         effective_pfn(sel_lo0[25:6], lookup0_va,
                                       tlb_mask[lookup0_hit_index_r]);

    // Port 1 (D-side)
    wire [18:0] lookup1_vpn2 = lookup1_va[31:13];
    wire [TLB_ENTRIES-1:0] lookup1_hit_vec;
    generate
        for (gi = 0; gi < TLB_ENTRIES; gi = gi + 1) begin : g_lookup1
            wire [18:0] cmp1_mask = { 3'b111, ~tlb_mask[gi] };
            wire vpn2_match1 = tlb_valid[gi] &&
                               (((tlb_vpn2[gi] ^ lookup1_vpn2) & cmp1_mask) == 19'b0);
            wire asid_match1 = tlb_g[gi] || (tlb_asid[gi] == lookup1_asid);
            assign lookup1_hit_vec[gi] = vpn2_match1 && asid_match1;
        end
    endgenerate
    reg [INDEX_BITS-1:0] lookup1_hit_index_r;
    reg                  lookup1_hit_r;
    reg                  lookup1_multi_hit_r;
    integer m1;
    always @(*) begin
        lookup1_hit_r       = 1'b0;
        lookup1_hit_index_r = {INDEX_BITS{1'b0}};
        lookup1_multi_hit_r = 1'b0;
        for (m1 = TLB_ENTRIES - 1; m1 >= 0; m1 = m1 - 1) begin
            if (lookup1_hit_vec[m1]) begin
                if (lookup1_hit_r &&
                    ((tlb_vpn2[m1] != tlb_vpn2[lookup1_hit_index_r]) ||
                     (tlb_asid[m1] != tlb_asid[lookup1_hit_index_r]) ||
                     (tlb_mask[m1] != tlb_mask[lookup1_hit_index_r]) ||
                     (tlb_entrylo0[m1] != tlb_entrylo0[lookup1_hit_index_r]) ||
                     (tlb_entrylo1[m1] != tlb_entrylo1[lookup1_hit_index_r])))
                    lookup1_multi_hit_r = 1'b1;
                lookup1_hit_r       = 1'b1;
                lookup1_hit_index_r = m1[INDEX_BITS-1:0];
            end
        end
    end
    assign lookup1_hit = (`SOC_MICRO_TLB_ENABLE) ?
                         (micro_d_hit | lookup1_hit_r) : lookup1_hit_r;
    assign lookup1_multi_hit = (`SOC_MICRO_TLB_ENABLE && micro_d_hit) ?
                               micro_d_multi : lookup1_multi_hit_r;
    wire [5:0] lookup1_odd_bit = page_odd_bit_index(tlb_mask[lookup1_hit_index_r]);
    wire        lookup1_odd = lookup1_va[lookup1_odd_bit];
    wire [31:0] sel_lo1 = lookup1_odd ? tlb_entrylo1[lookup1_hit_index_r]
                                      : tlb_entrylo0[lookup1_hit_index_r];
    assign lookup1_v   = (`SOC_MICRO_TLB_ENABLE && micro_d_hit) ? micro_d_v : sel_lo1[1];
    assign lookup1_d   = (`SOC_MICRO_TLB_ENABLE && micro_d_hit) ? micro_d_d : sel_lo1[2];
    assign lookup1_c   = (`SOC_MICRO_TLB_ENABLE && micro_d_hit) ? micro_d_c : sel_lo1[5:3];
    assign lookup1_pfn = (`SOC_MICRO_TLB_ENABLE && micro_d_hit) ? micro_d_pfn :
                         effective_pfn(sel_lo1[25:6], lookup1_va,
                                       tlb_mask[lookup1_hit_index_r]);

    // Optional I/D micro-TLB.  The main array remains the source of truth;
    // this block only caches successful lookups and is flushed by every
    // architectural write/invalidate operation.  Keeping the mux here makes
    // SOC_MICRO_TLB_ENABLE=0 behavior identical to the original path.
    wire micro_flush = wr_en | inv_en | context_flush;
    mips_micro_tlb #(.ENTRIES(4), .INDEX_BITS(2)) u_micro_tlb (
        .clk(clk), .rst_n(rst_n), .flush(micro_flush),
        .i_va(lookup0_va), .i_asid(lookup0_asid),
        .i_main_hit(lookup0_hit_r), .i_main_multi_hit(lookup0_multi_hit_r),
        .i_main_mask(tlb_mask[lookup0_hit_index_r]),
        .i_main_vpn2(tlb_vpn2[lookup0_hit_index_r]), .i_main_g(tlb_g[lookup0_hit_index_r]),
        .i_main_lo0(tlb_entrylo0[lookup0_hit_index_r]),
        .i_main_lo1(tlb_entrylo1[lookup0_hit_index_r]),
        .d_va(lookup1_va), .d_asid(lookup1_asid),
        .d_main_hit(lookup1_hit_r), .d_main_multi_hit(lookup1_multi_hit_r),
        .d_main_mask(tlb_mask[lookup1_hit_index_r]),
        .d_main_vpn2(tlb_vpn2[lookup1_hit_index_r]), .d_main_g(tlb_g[lookup1_hit_index_r]),
        .d_main_lo0(tlb_entrylo0[lookup1_hit_index_r]),
        .d_main_lo1(tlb_entrylo1[lookup1_hit_index_r]),
        .i_hit(micro_i_hit), .i_multi_hit(micro_i_multi), .i_v(micro_i_v),
        .i_d(micro_i_d), .i_c(micro_i_c), .i_pfn(micro_i_pfn),
        .d_hit(micro_d_hit), .d_multi_hit(micro_d_multi), .d_v(micro_d_v),
        .d_d(micro_d_d), .d_c(micro_d_c), .d_pfn(micro_d_pfn)
    );

    // -------------------------------------------------------------------------
    // Write (TLBWI / TLBWR): synchronous, one entry per cycle.
    // Reset clears the valid array only; data arrays are left X for area but
    // will be overwritten before any lookup can see them (guarded by valid).
    // -------------------------------------------------------------------------
    integer k;
    reg inv_match;
    // This is the synchronous commit qualification.  The caller samples it
    // on the same edge that executes the invalidate branch; TLB writes have
    // priority and therefore cannot be acknowledged as invalidates.
    assign inv_applied = inv_en && !wr_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < TLB_ENTRIES; k = k + 1) begin
                tlb_valid[k] <= 1'b0;
            end
        end else begin
            if (wr_en) begin
            tlb_vpn2    [wr_index] <= wr_vpn2;
            tlb_asid    [wr_index] <= wr_asid;
            tlb_mask    [wr_index] <= wr_mask;
            tlb_entrylo0[wr_index] <= wr_entrylo0;
            tlb_entrylo1[wr_index] <= wr_entrylo1;
            tlb_g       [wr_index] <= wr_entrylo0[0] & wr_entrylo1[0];
            // TLBWI installs a matching slot even when both EntryLo.V bits are
            // clear.  The slot must still report hit=1/v=0 so the MMU can
            // distinguish a matching Invalid entry from a refill miss.  The
            // explicit invalidate port clears tlb_valid and removes the slot
            // from matching altogether.
            tlb_valid   [wr_index] <= 1'b1;
            end else if (inv_en) begin
            for (k = 0; k < TLB_ENTRIES; k = k + 1) begin
                inv_match = 1'b0;
                if (k >= inv_wired_floor) begin
                    case (inv_scope)
                      2'd0: inv_match = tlb_valid[k] &&
                                         (tlb_vpn2[k] == inv_vpn2) &&
                                         (tlb_g[k] || (tlb_asid[k] == inv_asid));
                      2'd1: inv_match = tlb_valid[k] &&
                                         (tlb_g[k] || (tlb_asid[k] == inv_asid));
                      2'd2: inv_match = tlb_valid[k];
                      default: inv_match = 1'b0;
                    endcase
                end
                if (inv_match) tlb_valid[k] <= 1'b0;
            end
            end
        end
    end

endmodule
