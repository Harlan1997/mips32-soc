`ifdef VIC_PRIORITY_CHECKER_ENABLE
bind apb_vic vic_priority_checker #(.NUM_SOURCES(NUM_SOURCES))
    u_vic_priority_checker (
        .clk(clk), .rst_n(rst_n), .pending(pending), .active(active_r), .prio(prio_r),
        .irq(irq), .vec_id(vec_id), .vec_prio(vec_prio)
    );
`endif
