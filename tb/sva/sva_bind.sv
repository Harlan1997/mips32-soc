// =============================================================================
// SVA Bind Directives
// Author:    Antigravity — Phase F
// Purpose:
//   Attaches SVA property modules to DUT instances without modifying RTL.
//   Include this file into a verif compile unit with -DSVA_ENABLE to activate.
//   Signoff scripts currently do NOT include this file — SVA is opt-in.
// =============================================================================

`ifdef SVA_ENABLE

// Example bind: attach axi4_protocol_props to every axi slave interface in
// the SoC. Real binds must know the exact hierarchical path — this file
// serves as a template; expand per subsystem as they gain SVA coverage.

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

// Additional binds for dcache/icache when their state signals are exposed:
//   bind dcache dcache_state_props u_dcache_props (...);

`endif
