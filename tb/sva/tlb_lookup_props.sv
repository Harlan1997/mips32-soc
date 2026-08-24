`ifdef SVA_ENABLE
// TLB lookup safety properties for the current main-TLB contract. This is
// simulation assertion evidence; it is not a formal proof.
module tlb_lookup_props #(
    parameter TLB_ENTRIES = 64
) (
    input logic                   clk,
    input logic                   rst_n,
    input logic [TLB_ENTRIES-1:0] lookup0_hit_vec,
    input logic [TLB_ENTRIES-1:0] lookup1_hit_vec,
    input logic                   lookup0_multi_hit,
    input logic                   lookup1_multi_hit
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    // The encoder may report multi-hit only when at least two entries match.
    MAIN_TLB_I_MULTI_HIT_KNOWN: assert property (
        lookup0_multi_hit |-> ($countones(lookup0_hit_vec) >= 2)
    ) else $error("SVA_FAIL TLB: I multi-hit count mismatch");

    MAIN_TLB_D_MULTI_HIT_KNOWN: assert property (
        lookup1_multi_hit |-> ($countones(lookup1_hit_vec) >= 2)
    ) else $error("SVA_FAIL TLB: D multi-hit count mismatch");
endmodule
`endif
