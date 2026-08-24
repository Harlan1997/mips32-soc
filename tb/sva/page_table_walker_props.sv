`ifdef SVA_ENABLE
// Protocol-only properties for the bounded two-level page-table walker.
// Translation and permission behavior remain covered by the directed walker
// tests; these assertions constrain the handshake/state contract.
module page_table_walker_props (
    input logic clk,
    input logic rst_n,
    input logic [1:0] state_r,
    input logic req_valid,
    input logic req_ready,
    input logic mem_valid,
    input logic mem_ready,
    input logic resp_valid
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    WALKER_STATE_KNOWN: assert property (!$isunknown(state_r))
        else $error("SVA_FAIL WALKER: state is X/Z");

    // A memory request must remain asserted until the memory side accepts it.
    WALKER_MEM_HOLD: assert property (
        mem_valid && !mem_ready |=> mem_valid
    ) else $error("SVA_FAIL WALKER: mem_valid dropped under backpressure");

    // Every accepted walker request enters its first memory-read phase.
    WALKER_REQ_ISSUES_READ: assert property (
        req_valid && req_ready |=> mem_valid
    ) else $error("SVA_FAIL WALKER: accepted request did not issue memory read");

    // The response is an architectural one-cycle handoff.
    WALKER_RESP_PULSE: assert property (
        resp_valid |=> !resp_valid
    ) else $error("SVA_FAIL WALKER: response valid held more than one cycle");
endmodule
`endif
