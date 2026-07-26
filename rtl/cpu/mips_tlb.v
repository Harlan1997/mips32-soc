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
    output wire [INDEX_BITS-1:0] probe_index
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
    integer j;
    always @(*) begin
        probe_hit_r   = 1'b0;
        probe_index_r = {INDEX_BITS{1'b0}};
        for (j = TLB_ENTRIES - 1; j >= 0; j = j - 1) begin
            if (hit_vec[j]) begin
                probe_hit_r   = 1'b1;
                probe_index_r = j[INDEX_BITS-1:0];
            end
        end
    end
    assign probe_hit   = probe_hit_r;
    assign probe_index = probe_index_r;

    // -------------------------------------------------------------------------
    // Write (TLBWI / TLBWR): synchronous, one entry per cycle.
    // Reset clears the valid array only; data arrays are left X for area but
    // will be overwritten before any lookup can see them (guarded by valid).
    // -------------------------------------------------------------------------
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < TLB_ENTRIES; k = k + 1) begin
                tlb_valid[k] <= 1'b0;
            end
        end else if (wr_en) begin
            tlb_vpn2    [wr_index] <= wr_vpn2;
            tlb_asid    [wr_index] <= wr_asid;
            tlb_mask    [wr_index] <= wr_mask;
            tlb_entrylo0[wr_index] <= wr_entrylo0;
            tlb_entrylo1[wr_index] <= wr_entrylo1;
            tlb_g       [wr_index] <= wr_entrylo0[0] & wr_entrylo1[0];
            tlb_valid   [wr_index] <= 1'b1;
        end
    end

endmodule
