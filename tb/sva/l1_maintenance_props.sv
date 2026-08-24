`ifdef SVA_ENABLE
module l1_maintenance_props (
    input logic       clk,
    input logic       rst_n,
    input logic       cache_op_valid,
    input logic       maintenance_issue,
    input logic       l1_bridge_active,
    input logic       l1_response_valid,
    input logic       l1_active,
    input logic [2:0] l1_outstanding,
    input logic       legacy_cache_op_valid,
    input logic       l1_cache_maint_invalidate
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    property p_issue_only_when_l1_idle;
        maintenance_issue |-> !l1_bridge_active && !l1_response_valid &&
                              !l1_active && (l1_outstanding == 0);
    endproperty
    L1_MAINTENANCE_IDLE: assert property (p_issue_only_when_l1_idle)
        else $error("SVA_FAIL L1 maintenance issued with live L1 state");

    property p_raw_maintenance_is_held;
        cache_op_valid && !maintenance_issue |->
            !legacy_cache_op_valid && !l1_cache_maint_invalidate;
    endproperty
    L1_MAINTENANCE_HOLD: assert property (p_raw_maintenance_is_held)
        else $error("SVA_FAIL L1 maintenance bypassed idle guard");

    cover property (maintenance_issue);
endmodule
`endif
