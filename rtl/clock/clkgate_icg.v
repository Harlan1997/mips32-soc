// =============================================================================
// File Name: clkgate_icg.v
// Design:    Integrated Clock Gating (behavioral, latch-based)
// Author:    Antigravity — Phase E
// Description:
//   Latch-based clock gate; synthesis tool substitutes technology ICG cell
//   (e.g. CLKGATETST_X1). test_en OR gate allows DFT scan bypass.
//   Enable MUST come from a registered source or be pipeline-registered
//   to guarantee no glitches. See docs/block_specs/clock_reset_spec.md §5.
// =============================================================================

module clkgate_icg (
    input  wire clk_in,
    input  wire enable,
    input  wire test_en,
    output wire clk_out
);

    reg latch;

    always @(*) begin
        if (~clk_in) latch = enable | test_en;
    end

    assign clk_out = clk_in & latch;

endmodule
