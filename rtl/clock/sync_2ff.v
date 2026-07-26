// =============================================================================
// File Name: sync_2ff.v
// Design:    Single-Bit Level Synchronizer (2FF)
// Author:    Antigravity — Phase E
// Description:
//   Synchronizes a single-bit signal from src clock domain into dst clock
//   domain. Input src_data MUST be a register output in the src domain
//   (never combinational). See docs/block_specs/clock_reset_spec.md §4.1.
//   async_reg attribute pragma hints to synth/PnR that back-to-back flops
//   must remain adjacent (Xilinx/synth-tool specific but harmless elsewhere).
// =============================================================================

module sync_2ff #(
    parameter STAGES = 2
) (
    input  wire dst_clk,
    input  wire dst_rst_n,
    input  wire src_data,
    output wire dst_data
);

    (* async_reg = "true" *) reg [STAGES-1:0] sync_r;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_r <= {STAGES{1'b0}};
        end else begin
            sync_r <= {sync_r[STAGES-2:0], src_data};
        end
    end

    assign dst_data = sync_r[STAGES-1];

endmodule
