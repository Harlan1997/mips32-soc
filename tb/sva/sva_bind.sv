// =============================================================================
// SVA Bind Directives
// Author:    Antigravity — Phase F
// Purpose:
//   Attaches SVA property modules to DUT instances without modifying RTL.
//   Include this file into a verif compile unit with -DSVA_ENABLE to activate.
//   Signoff scripts currently do NOT include this file — SVA is opt-in.
// =============================================================================

`ifdef SVA_ENABLE

bind axi_sram axi4_protocol_props #(
    .ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)
) u_sram_axi_props (
    .clk     (clk),
    .rst_n   (rst_n),
    .awvalid (s_awvalid), .awready(s_awready),
    .awid    (s_awid),    .awaddr (s_awaddr),
    .awlen   (s_awlen),   .awsize (s_awsize),  .awburst(s_awburst),
    .wvalid  (s_wvalid),  .wready (s_wready),
    .wdata   (s_wdata),   .wlast  (s_wlast),
    .bvalid  (s_bvalid),  .bready (s_bready),
    .bid     (s_bid),     .bresp  (s_bresp),
    .arvalid (s_arvalid), .arready(s_arready),
    .arid    (s_arid),    .araddr (s_araddr),  .arlen  (s_arlen),
    .rvalid  (s_rvalid),  .rready (s_rready),
    .rid     (s_rid),     .rdata  (s_rdata),   .rresp  (s_rresp),
    .rlast   (s_rlast)
);

bind apb_vic apb_protocol_props u_vic_apb_props (
    .clk     (clk),
    .rst_n   (rst_n),
    .psel    (psel),
    .penable (penable),
    .pwrite  (pwrite),
    .paddr   (paddr),
    .pwdata  (pwdata),
    .pready  (pready),
    .pslverr (pslverr)
);

bind l1_cache_nb_cpu_axi l1_maintenance_props u_l1_maintenance_props (
    .clk                       (clk),
    .rst_n                     (rst_n),
    .cache_op_valid            (cache_op_valid),
    .maintenance_issue         (maintenance_issue),
    .l1_bridge_active          (l1_bridge_active),
    .l1_response_valid         (n_rsp_valid),
    .l1_active                 (l1_active),
    .l1_outstanding            (l1_outstanding),
    .legacy_cache_op_valid     (u_legacy_dcache.cache_op_valid),
    .l1_cache_maint_invalidate (u_l1.cache_maint_invalidate)
);

bind l1_cache_nb l1_resource_props u_l1_resource_props (
    .clk             (clk),
    .rst_n           (rst_n),
    .rsp_count       (rsp_count),
    .mshr_occupancy  (mshr_occupancy),
    .wb_occupancy    (wb_occupancy)
);

bind reset_sync reset_sync_props #(.STAGES(STAGES)) u_reset_sync_props (
    .clk       (clk),
    .rst_pre_n (rst_pre_n),
    .rst_n     (rst_n)
);

`endif
