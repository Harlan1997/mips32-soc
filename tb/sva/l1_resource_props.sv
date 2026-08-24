`ifdef SVA_ENABLE
module l1_resource_props (
    input logic        clk,
    input logic        rst_n,
    input logic [31:0] rsp_count,
    input logic [31:0] mshr_occupancy,
    input logic [31:0] wb_occupancy
);
    default clocking cb @(posedge clk); endclocking

    // The current opt-in CPU contract is two MSHRs and four writeback/FIFO
    // entries. These are architectural resource limits, not performance goals.
    property p_rsp_fifo_bound;
        rsp_count <= 4;
    endproperty
    L1_RSP_FIFO_BOUND: assert property (p_rsp_fifo_bound)
        else $error("SVA_FAIL L1 response FIFO count exceeded depth");

    property p_mshr_bound;
        mshr_occupancy <= 2;
    endproperty
    L1_MSHR_BOUND: assert property (p_mshr_bound)
        else $error("SVA_FAIL L1 MSHR occupancy exceeded depth");

    property p_wb_bound;
        wb_occupancy <= 4;
    endproperty
    L1_WB_BOUND: assert property (p_wb_bound)
        else $error("SVA_FAIL L1 writeback occupancy exceeded depth");

    property p_reset_clears_resources;
        !rst_n |-> (rsp_count == 0 && mshr_occupancy == 0 && wb_occupancy == 0);
    endproperty
    L1_RESET_RESOURCE_FLUSH: assert property (p_reset_clears_resources)
        else $error("SVA_FAIL L1 reset did not clear resource occupancy");

    cover property (rst_n && (rsp_count != 0));
endmodule
`endif
