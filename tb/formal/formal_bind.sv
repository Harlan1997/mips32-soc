// Real-DUT bindings for the solver-facing property scaffolds. This file is
// intentionally separate from the simulation SVA bind and is enabled only by
// a formal harness.
`ifdef FORMAL_ENABLE
`ifdef FORMAL_BIND_DCACHE
bind dcache dcache_invariant_props #(
    .STATE_WIDTH(5), .REFILL_BOUND(4096)
) u_formal_dcache_props (
    .clk          (clk),
    .rst_n        (rst_n),
    .state        (state),
    .refill_start (state == 5'd5),
    .refill_done  ((state == 5'd7) || (state == 5'd12))
);
`endif

`ifdef FORMAL_BIND_TLB
bind mips_tlb tlb_invariant_props #(
    .TLB_ENTRIES(TLB_ENTRIES)
) u_formal_tlb_props (
    .clk               (clk),
    .rst_n              (rst_n),
    .lookup0_hit_vec   (lookup0_hit_vec),
    .lookup1_hit_vec   (lookup1_hit_vec),
    .lookup0_main_multi_hit (lookup0_multi_hit_r),
    .lookup1_main_multi_hit (lookup1_multi_hit_r)
);
`endif

`ifdef FORMAL_BIND_VIC
bind apb_vic interrupt_priority_props u_formal_interrupt_props (
    .clk            (clk),
    .rst_n          (rst_n),
    .pending        (pending),
    .selected_valid (irq),
    .selected_source(vec_id[4:0])
);
`endif

`ifdef FORMAL_BIND_FABRIC
bind soc_fabric arb_fairness_props u_formal_arbiter_props (
    .clk               (clk),
    .rst_n             (rst_n),
    .m0_arvalid       (m0_arvalid),
    .m0_arready       (m0_arready),
    .m1_arvalid       (m1_arvalid),
    .downstream_arready(s0_arready)
);
`endif
`endif
