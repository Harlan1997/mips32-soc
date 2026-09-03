`ifdef SVA_ENABLE
// Safety properties for the 32-source VIC output contract.  The priority
// checker covers arbitration selection; these assertions cover the externally
// visible validity relationship between irq, pending, and VEC_ID.
module vic_contract_props #(
    parameter integer NUM_SOURCES = 32
) (
    input logic                     clk,
    input logic                     rst_n,
    input logic [NUM_SOURCES-1:0]   pending,
    input logic                     irq,
    input logic [7:0]               vec_id
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    VIC_IRQ_HAS_VALID_ID: assert property (
        irq |-> (vec_id < NUM_SOURCES)
    ) else $error("SVA_FAIL VIC: irq asserted with out-of-range VEC_ID");

    VIC_IRQ_ID_IS_PENDING: assert property (
        irq |-> pending[vec_id]
    ) else $error("SVA_FAIL VIC: irq asserted for a non-pending source");

    VIC_NO_PENDING_NO_IRQ: assert property (
        (pending == '0) |-> (!irq && (vec_id == 8'hff))
    ) else $error("SVA_FAIL VIC: no-pending state has irq or VEC_ID");

    cover property (irq && (vec_id == 8'd0));
    cover property (irq && (vec_id == 8'd31));
endmodule
`endif
