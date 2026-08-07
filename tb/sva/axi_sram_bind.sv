`ifdef SVA_ENABLE
bind axi_sram axi4_protocol_props #(
    .ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)
) u_sram_axi_props (
    .clk(clk), .rst_n(rst_n),
    .awvalid(s_awvalid), .awready(s_awready), .awid(s_awid),
    .awaddr(s_awaddr), .awlen(s_awlen), .awsize(s_awsize),
    .awburst(s_awburst), .wvalid(s_wvalid), .wready(s_wready),
    .wdata(s_wdata), .wlast(s_wlast), .bvalid(s_bvalid),
    .bready(s_bready), .bid(s_bid), .bresp(s_bresp),
    .arvalid(s_arvalid), .arready(s_arready), .arid(s_arid),
    .araddr(s_araddr), .arlen(s_arlen), .rvalid(s_rvalid),
    .rready(s_rready), .rid(s_rid), .rdata(s_rdata),
    .rresp(s_rresp), .rlast(s_rlast)
);
`endif
