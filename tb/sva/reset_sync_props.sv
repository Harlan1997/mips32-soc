`ifdef SVA_ENABLE
module reset_sync_props #(parameter STAGES = 3) (
    input logic clk,
    input logic rst_pre_n,
    input logic rst_n
);
    default clocking cb @(posedge clk); endclocking

    property p_asserted_low;
        !rst_pre_n |-> !rst_n;
    endproperty
    RESET_ASSERTED_LOW: assert property (p_asserted_low)
        else $error("SVA_FAIL RESET: synchronized reset remained high");

    property p_sync_release;
        // Nonblocking assignments become observable to SVA on the following
        // sampling edge; include the release edge in the low window.
        $rose(rst_pre_n) |-> !rst_n[*STAGES] ##1 rst_n;
    endproperty
    RESET_SYNC_RELEASE: assert property (p_sync_release)
        else $error("SVA_FAIL RESET: reset deassertion was not synchronized");

    cover property ($fell(rst_pre_n) ##[1:STAGES+2] $rose(rst_n));
endmodule
`endif
