`ifdef SVA_ENABLE
bind reset_sync reset_sync_props #(.STAGES(STAGES)) u_reset_sync_props (
    .clk       (clk),
    .rst_pre_n (rst_pre_n),
    .rst_n     (rst_n)
);
`endif
