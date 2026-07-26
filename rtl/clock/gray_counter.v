// =============================================================================
// File Name: gray_counter.v
// Design:    N-bit Binary Counter with Gray-code Output
// Author:    Antigravity — Phase E
// Description:
//   Increment on `incr`. Exposes both binary (`bin`) for local logic and
//   gray-encoded value (`gray`) for cross-domain comparison. Gray property:
//   only one bit changes per increment → 2FF sync sees at most 1 metastable
//   bit → correct decode after 1-2 cycles. See spec §4.4.
// =============================================================================

module gray_counter #(
    parameter WIDTH = 4
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             incr,
    output reg  [WIDTH-1:0] bin,
    output wire [WIDTH-1:0] gray
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      bin <= {WIDTH{1'b0}};
        else if (incr)   bin <= bin + 1'b1;
    end

    assign gray = bin ^ (bin >> 1);

endmodule
