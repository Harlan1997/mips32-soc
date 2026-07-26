// =============================================================================
// File Name: mips_mdu_v2.v
// Design:    Multi-Cycle MDU (Phase B remaining item — scaffold)
// Author:    Antigravity — Phase B.7
// Description:
//   Multi-cycle FSM-based MDU intended to replace the current single-cycle
//   mips_mdu.v. The v1 MDU blocks EX until finished; v2 runs in parallel
//   with the main pipeline and only stalls EX on true HI/LO write-after-
//   write / read-after-write hazards. See docs/block_specs/mdu_spec.md.
//
//   Currently NOT instantiated in mips_cpu — kept alongside v1 so v1 can
//   remain in the DUT while v2 gains block-level verification. Cutover
//   is a separate integration commit.
//
//   Implemented in this pass (functional subset):
//     * FSM: IDLE / MUL_PIPE / DIV_ITER / DONE
//     * MULT / MULTU / DIV / DIVU (radix-2 restoring division)
//     * MFHI / MFLO / MTHI / MTLO passthrough
//     * busy output for EX-stage stall
//
//   Deferred:
//     * MUL rd form (R2), MADD/MADDU/MSUB/MSUBU
//     * Early-exit optimizations (high-16-bit shortcut on MULT, leading-
//       zero shortcut on DIV)
//     * Radix-4 SRT division
// =============================================================================

module mips_mdu_v2 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        issue_valid,
    input  wire [3:0]  op,          // 0=MULT 1=MULTU 2=DIV 3=DIVU
                                    // 4=MFHI 5=MFLO 6=MTHI 7=MTLO
    input  wire [31:0] rs_val,
    input  wire [31:0] rt_val,

    output reg  [31:0] hi_out,
    output reg  [31:0] lo_out,
    output reg         busy,
    output reg         done_pulse
);

    localparam ST_IDLE     = 3'd0;
    localparam ST_MUL_PIPE = 3'd1;
    localparam ST_DIV_ITER = 3'd2;
    localparam ST_DONE     = 3'd3;

    reg [2:0]  state;
    reg [31:0] hi_r, lo_r;
    reg [63:0] mul_prod;
    reg [4:0]  mul_pipe_ctr;

    // Signed helpers
    wire [31:0] rs_abs = rs_val[31] ? -rs_val : rs_val;
    wire [31:0] rt_abs = rt_val[31] ? -rt_val : rt_val;
    wire        neg_quot = rs_val[31] ^ rt_val[31];
    wire        neg_rem  = rs_val[31];

    // Division iteration state
    reg [63:0] div_rem_dividend;   // {rem, remaining dividend}
    reg [31:0] div_divisor;
    reg [5:0]  div_ctr;

    reg is_signed_op;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            hi_r         <= 32'h0;
            lo_r         <= 32'h0;
            mul_prod     <= 64'h0;
            mul_pipe_ctr <= 5'h0;
            div_rem_dividend <= 64'h0;
            div_divisor  <= 32'h0;
            div_ctr      <= 6'h0;
            busy         <= 1'b0;
            done_pulse   <= 1'b0;
            is_signed_op <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (issue_valid) begin
                        case (op)
                            4'd0, 4'd1: begin // MULT / MULTU
                                is_signed_op <= (op == 4'd0);
                                mul_prod <= (op == 4'd0)
                                          ? {{32{rs_abs[31]&&0}}, rs_abs} * {{32{rt_abs[31]&&0}}, rt_abs}
                                          : {32'h0, rs_val} * {32'h0, rt_val};
                                // For signed, apply sign at end
                                mul_pipe_ctr <= 5'd3;  // 3-cycle latency
                                state <= ST_MUL_PIPE;
                                busy  <= 1'b1;
                            end
                            4'd2, 4'd3: begin // DIV / DIVU
                                is_signed_op <= (op == 4'd2);
                                if (rt_val == 32'h0) begin
                                    // Division by zero: define result deterministically
                                    lo_r <= (op == 4'd3) ? 32'hFFFF_FFFF : 32'hFFFF_FFFF;
                                    hi_r <= rs_val;
                                    state <= ST_DONE;
                                    busy  <= 1'b1;
                                end else begin
                                    div_rem_dividend <= {32'h0, (op == 4'd2) ? rs_abs : rs_val};
                                    div_divisor      <= (op == 4'd2) ? rt_abs : rt_val;
                                    div_ctr          <= 6'd32;
                                    state <= ST_DIV_ITER;
                                    busy  <= 1'b1;
                                end
                            end
                            4'd4: lo_r <= hi_r;  // MFHI - stored in lo_r for readout convenience — see wrapper
                            4'd5: lo_r <= lo_r;  // MFLO passthrough
                            4'd6: hi_r <= rs_val; // MTHI
                            4'd7: lo_r <= rs_val; // MTLO
                            default: ;
                        endcase
                    end
                end

                ST_MUL_PIPE: begin
                    if (mul_pipe_ctr == 5'd0) begin
                        // Apply sign for MULT
                        if (is_signed_op && (rs_val[31] ^ rt_val[31])) begin
                            {hi_r, lo_r} <= -mul_prod;
                        end else begin
                            {hi_r, lo_r} <= mul_prod;
                        end
                        state <= ST_DONE;
                    end else begin
                        mul_pipe_ctr <= mul_pipe_ctr - 1'b1;
                    end
                end

                ST_DIV_ITER: begin
                    // Restoring division, 1 bit per cycle
                    if (div_ctr != 6'd0) begin
                        div_rem_dividend <= div_rem_dividend << 1;
                        if ((div_rem_dividend[62:31] | (div_rem_dividend[63] ? 32'h0 : 32'h0))
                             >= div_divisor) begin
                            div_rem_dividend[63:32] <= div_rem_dividend[62:31] - div_divisor;
                            div_rem_dividend[0]     <= 1'b1;
                        end
                        div_ctr <= div_ctr - 1'b1;
                    end else begin
                        if (is_signed_op) begin
                            lo_r <= neg_quot ? -div_rem_dividend[31:0]  : div_rem_dividend[31:0];
                            hi_r <= neg_rem  ? -div_rem_dividend[63:32] : div_rem_dividend[63:32];
                        end else begin
                            lo_r <= div_rem_dividend[31:0];
                            hi_r <= div_rem_dividend[63:32];
                        end
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    done_pulse <= 1'b1;
                    busy       <= 1'b0;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    always @(*) begin
        hi_out = hi_r;
        lo_out = lo_r;
    end

endmodule
