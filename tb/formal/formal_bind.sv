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

`ifdef FORMAL_BIND_BPU
bind mips_bpu bpu_invariant_props #(
    .BTB_ENTRIES   (BTB_ENTRIES),
    .BHT_ENTRIES   (BHT_ENTRIES),
    .BTB_IDX_BITS  (BTB_IDX_BITS),
    .BHT_IDX_BITS  (BHT_IDX_BITS),
    .BTB_TAG_BITS  (BTB_TAG_BITS)
) u_formal_bpu_props (
    .clk              (clk),
    .rst_n            (rst_n),
    .resolve_valid    (resolve_valid),
    .resolve_taken    (resolve_taken),
    .resolve_type     (resolve_type),
    .flush_if         (flush_if),
    .update_btb_index (upd_btb_idx),
    .update_bht_index (upd_bht_idx),
    .update_tag       (upd_tag),
    .resolve_target   (resolve_target),
    .btb_valid        (btb_valid),
    .btb_tag          (btb_tag),
    .btb_target       (btb_target),
    .bht_ctr          (bht_ctr)
);
`endif

`ifdef FORMAL_BIND_RESET_SYNC
bind reset_sync reset_sync_invariant_props #(
    .STAGES(STAGES)
) u_formal_reset_sync_props (
    .clk      (clk),
    .rst_pre_n(rst_pre_n),
    .rst_n    (rst_n)
);
`endif

`ifdef FORMAL_BIND_AXI_SRAM
bind axi_sram axi_sram_invariant_props u_formal_axi_sram_props (
    .clk     (clk),
    .rst_n   (rst_n),
    .s_rvalid(s_rvalid),
    .s_rready(s_rready),
    .s_rid   (s_rid),
    .s_rdata (s_rdata),
    .s_rresp (s_rresp),
    .s_rlast (s_rlast),
    .s_bvalid(s_bvalid),
    .s_bready(s_bready),
    .s_bid   (s_bid),
    .s_bresp (s_bresp)
);
`endif
`endif
