// =============================================================================
// File Name: reset_sync.v
// Design:    AASD (Async-Assert / Sync-Deassert) Reset Synchronizer
// Author:    Antigravity — Phase E
// Description:
//   Async assert (negedge rst_pre_n immediately pulls rst_n low).
//   Sync deassert (STAGES flops of dst_clk before rst_n rises).
//   One instance per clock domain. See docs/block_specs/clock_reset_spec.md
//   §3.2 for architecture context.
// =============================================================================

module reset_sync #(
    parameter STAGES = 3
) (
    input  wire clk,
    input  wire rst_pre_n,
    output wire rst_n
);

    reg [STAGES-1:0] sync_r;

    always @(posedge clk or negedge rst_pre_n) begin
        if (!rst_pre_n) begin
            sync_r <= {STAGES{1'b0}};
        end else begin
            sync_r <= {sync_r[STAGES-2:0], 1'b1};
        end
    end

    assign rst_n = sync_r[STAGES-1];

endmodule
