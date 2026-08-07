`ifdef SVA_ENABLE
module apb_protocol_props (
    input logic        clk,
    input logic        rst_n,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [11:0] paddr,
    input logic [31:0] pwdata,
    input logic        pready,
    input logic        pslverr
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    property p_setup_to_access;
        psel && !penable |=> psel && penable;
    endproperty
    APB_SETUP_ACCESS: assert property (p_setup_to_access)
        else $error("SVA_FAIL APB: setup phase did not enter access phase");

    property p_wait_stable;
        psel && penable && !pready |=> psel && penable &&
            $stable(pwrite) && $stable(paddr) && $stable(pwdata);
    endproperty
    APB_WAIT_STABLE: assert property (p_wait_stable)
        else $error("SVA_FAIL APB: transfer controls changed while waiting");

    property p_error_on_completion;
        pslverr |-> psel && penable && pready;
    endproperty
    APB_ERROR_COMPLETION: assert property (p_error_on_completion)
        else $error("SVA_FAIL APB: PSLVERR asserted outside completion");

    cover property (psel && !penable ##1 psel && penable && pready);
    cover property (psel && penable && !pready ##1 psel && penable && pready);
    cover property (psel && penable && pready && pslverr);
endmodule
`endif
