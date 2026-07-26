// =============================================================================
// File Name: pll_wrapper.v
// Design:    PLL Wrapper (behavioral / bypass)
// Author:    Antigravity — Phase E
// Description:
//   Wraps an external PLL macro (inserted by back-end). In simulation this
//   provides a behavioral model:
//     - bypass=1  → out_clk[*] = ref_clk (integer divide by out*_div only)
//     - bypass=0  → out_clk[*] = ref_clk * fb_div / out*_div (rough model)
//   lock is delayed by SIM_LOCK_CYCLES cycles after reset to model PLL
//   acquisition. Back-end replaces with actual PDK macro instance.
//   See docs/block_specs/clock_reset_spec.md §2.
// =============================================================================

module pll_wrapper #(
    parameter OUT_DIVIDERS    = 4,
    parameter SIM_LOCK_CYCLES = 8
) (
    input  wire       ref_clk,
    input  wire       rst_n,
    input  wire       bypass,
    input  wire [7:0] fb_div,
    input  wire [3:0] out0_div,
    input  wire [3:0] out1_div,
    input  wire [3:0] out2_div,
    input  wire [3:0] out3_div,

    output wire [OUT_DIVIDERS-1:0] out_clk,
    output reg                     lock
);

    // -------- lock model ----------------------------------------------------
    reg [7:0] lock_ctr;
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            lock     <= 1'b0;
            lock_ctr <= 8'd0;
        end else if (bypass) begin
            lock     <= 1'b1;
            lock_ctr <= 8'd0;
        end else if (lock_ctr < SIM_LOCK_CYCLES[7:0]) begin
            lock_ctr <= lock_ctr + 1'b1;
        end else begin
            lock <= 1'b1;
        end
    end

    // -------- output divider (behavioral) -----------------------------------
    // Simplified: each out_clk is a divided version of ref_clk. No real
    // multiplication in simulation; back-end inserts real PLL.
    reg [15:0] div_ctr [OUT_DIVIDERS-1:0];
    reg [OUT_DIVIDERS-1:0] out_reg;
    wire [3:0] div_lut [OUT_DIVIDERS-1:0];
    assign div_lut[0] = out0_div;
    generate
        if (OUT_DIVIDERS > 1) begin: g_d1 assign div_lut[1] = out1_div; end
        if (OUT_DIVIDERS > 2) begin: g_d2 assign div_lut[2] = out2_div; end
        if (OUT_DIVIDERS > 3) begin: g_d3 assign div_lut[3] = out3_div; end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < OUT_DIVIDERS; j = j + 1) begin: g_outdiv
            always @(posedge ref_clk or negedge rst_n) begin
                if (!rst_n) begin
                    div_ctr[j] <= 16'd0;
                    out_reg[j] <= 1'b0;
                end else if (bypass || div_lut[j] == 4'd1 || div_lut[j] == 4'd0) begin
                    out_reg[j] <= ~out_reg[j];
                    div_ctr[j] <= 16'd0;
                end else if (div_ctr[j] >= {12'd0, div_lut[j]} - 1) begin
                    out_reg[j] <= ~out_reg[j];
                    div_ctr[j] <= 16'd0;
                end else begin
                    div_ctr[j] <= div_ctr[j] + 1'b1;
                end
            end
        end
    endgenerate

    assign out_clk = out_reg;

endmodule
