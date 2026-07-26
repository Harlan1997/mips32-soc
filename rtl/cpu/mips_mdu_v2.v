// =============================================================================
// File Name: mips_mdu_v2.v
// Design:    Multi-Cycle MDU — full functional implementation
// Author:    Antigravity — Phase B.7
// Description:
//   Multi-cycle FSM MDU. Runs in parallel with the main pipeline; EX only
//   stalls on true HI/LO write-after-write / read-after-write hazards.
//   Replaces the single-cycle mips_mdu.v after block-level verification.
//   See docs/block_specs/mdu_spec.md.
//
//   Instruction set (op[3:0]):
//     0 MULT   signed 32×32 → 64  (HI:LO)
//     1 MULTU  unsigned 32×32 → 64
//     2 DIV    signed 32/32
//     3 DIVU   unsigned 32/32
//     4 MFHI   pass HI
//     5 MFLO   pass LO
//     6 MTHI   HI ← rs
//     7 MTLO   LO ← rs
//     8 MADD   {HI:LO} += signed(rs*rt)
//     9 MADDU  {HI:LO} += unsigned(rs*rt)
//    10 MSUB   {HI:LO} -= signed(rs*rt)
//    11 MSUBU  {HI:LO} -= unsigned(rs*rt)
//    12 MUL    rd = (rs*rt)[31:0]   (R2)  — HI/LO trashed per spec
//
//   Multiplier: single-cycle behavioural (Verilog *), pipelined 3 cycles to
//   model reasonable timing. Early-exit shortcut: if |rs| <= 0xFFFF and
//   |rt| <= 0xFFFF the result is complete after 1 cycle (fits 32 bits).
//
//   Divider: 32-cycle restoring radix-2. Early-exit: if divisor > dividend
//   in unsigned magnitude we skip iteration and return LO=0/HI=dividend.
// =============================================================================

module mips_mdu_v2 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        issue_valid,
    input  wire [3:0]  op,
    input  wire [31:0] rs_val,
    input  wire [31:0] rt_val,

    output wire [31:0] hi_out,
    output wire [31:0] lo_out,
    output wire        busy,
    output reg         done_pulse
);

    // ---- Op decode ----
    localparam OP_MULT  = 4'd0;
    localparam OP_MULTU = 4'd1;
    localparam OP_DIV   = 4'd2;
    localparam OP_DIVU  = 4'd3;
    localparam OP_MFHI  = 4'd4;
    localparam OP_MFLO  = 4'd5;
    localparam OP_MTHI  = 4'd6;
    localparam OP_MTLO  = 4'd7;
    localparam OP_MADD  = 4'd8;
    localparam OP_MADDU = 4'd9;
    localparam OP_MSUB  = 4'd10;
    localparam OP_MSUBU = 4'd11;
    localparam OP_MUL   = 4'd12;

    // ---- FSM ----
    localparam ST_IDLE    = 3'd0;
    localparam ST_MUL     = 3'd1;
    localparam ST_ACC     = 3'd2;   // MADD/MSUB accumulate
    localparam ST_DIV_ITR = 3'd3;
    localparam ST_DIV_FIX = 3'd4;
    localparam ST_DONE    = 3'd5;

    reg [2:0]  state;

    // ---- Architectural registers ----
    reg [31:0] hi_r, lo_r;
    assign hi_out = hi_r;
    assign lo_out = lo_r;

    // ---- Op latches ----
    reg [3:0]  op_r;
    reg [31:0] rs_r, rt_r;
    reg        is_signed;
    reg        is_accsub;   // MSUB/MSUBU
    reg        is_acc;      // MADD/MADDU/MSUB/MSUBU
    reg        result_neg_mul;
    reg        result_neg_quot;
    reg        result_neg_rem;

    // ---- Multiplier operands / result ----
    reg  [31:0] mul_a, mul_b;
    reg  [63:0] mul_prod;
    reg  [1:0]  mul_pipe;   // 2-cycle pipeline; 0 result ready

    // ---- Divider state ----
    reg  [31:0] div_divisor;
    reg  [63:0] div_ws;     // {rem, dividend_remaining}
    reg  [5:0]  div_ctr;
    reg  [31:0] div_dividend_orig;

    // ---- Busy ----
    assign busy = (state != ST_IDLE) && (state != ST_DONE);

    // Working temporary for MADD result
    reg [63:0] acc_tmp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            hi_r              <= 32'h0;
            lo_r              <= 32'h0;
            op_r              <= 4'h0;
            rs_r              <= 32'h0;
            rt_r              <= 32'h0;
            is_signed         <= 1'b0;
            is_accsub         <= 1'b0;
            is_acc            <= 1'b0;
            result_neg_mul    <= 1'b0;
            result_neg_quot   <= 1'b0;
            result_neg_rem    <= 1'b0;
            mul_a             <= 32'h0;
            mul_b             <= 32'h0;
            mul_prod          <= 64'h0;
            mul_pipe          <= 2'h0;
            div_divisor       <= 32'h0;
            div_ws            <= 64'h0;
            div_ctr           <= 6'h0;
            div_dividend_orig <= 32'h0;
            done_pulse        <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state)
                //=============================================================
                ST_IDLE: begin
                    if (issue_valid) begin
                        op_r <= op;
                        rs_r <= rs_val;
                        rt_r <= rt_val;
                        case (op)
                            OP_MFHI: begin
                                lo_r  <= hi_r;   // caller reads lo_out; wrapper decides which
                                state <= ST_DONE;
                            end
                            OP_MFLO: begin
                                state <= ST_DONE;
                            end
                            OP_MTHI: begin
                                hi_r  <= rs_val;
                                state <= ST_DONE;
                            end
                            OP_MTLO: begin
                                lo_r  <= rs_val;
                                state <= ST_DONE;
                            end
                            OP_MULT, OP_MADD, OP_MSUB, OP_MUL: begin
                                is_signed      <= 1'b1;
                                is_acc         <= (op == OP_MADD) || (op == OP_MSUB);
                                is_accsub      <= (op == OP_MSUB);
                                mul_a          <= rs_val[31] ? (~rs_val + 1'b1) : rs_val;
                                mul_b          <= rt_val[31] ? (~rt_val + 1'b1) : rt_val;
                                result_neg_mul <= rs_val[31] ^ rt_val[31];
                                mul_pipe       <= 2'd2;
                                state          <= ST_MUL;
                            end
                            OP_MULTU, OP_MADDU, OP_MSUBU: begin
                                is_signed      <= 1'b0;
                                is_acc         <= (op == OP_MADDU) || (op == OP_MSUBU);
                                is_accsub      <= (op == OP_MSUBU);
                                mul_a          <= rs_val;
                                mul_b          <= rt_val;
                                result_neg_mul <= 1'b0;
                                mul_pipe       <= 2'd2;
                                state          <= ST_MUL;
                            end
                            OP_DIV: begin
                                is_signed          <= 1'b1;
                                if (rt_val == 32'h0) begin
                                    // divide-by-zero: deterministic
                                    lo_r  <= 32'hFFFF_FFFF;
                                    hi_r  <= rs_val;
                                    state <= ST_DONE;
                                end else begin
                                    div_divisor       <= rt_val[31] ? (~rt_val + 1'b1) : rt_val;
                                    div_dividend_orig <= rs_val[31] ? (~rs_val + 1'b1) : rs_val;
                                    div_ws            <= {32'h0, rs_val[31] ? (~rs_val + 1'b1) : rs_val};
                                    div_ctr           <= 6'd32;
                                    result_neg_quot   <= rs_val[31] ^ rt_val[31];
                                    result_neg_rem    <= rs_val[31];
                                    state             <= ST_DIV_ITR;
                                end
                            end
                            OP_DIVU: begin
                                is_signed <= 1'b0;
                                if (rt_val == 32'h0) begin
                                    lo_r  <= 32'hFFFF_FFFF;
                                    hi_r  <= rs_val;
                                    state <= ST_DONE;
                                end else begin
                                    div_divisor       <= rt_val;
                                    div_dividend_orig <= rs_val;
                                    div_ws            <= {32'h0, rs_val};
                                    div_ctr           <= 6'd32;
                                    result_neg_quot   <= 1'b0;
                                    result_neg_rem    <= 1'b0;
                                    state             <= ST_DIV_ITR;
                                end
                            end
                            default: state <= ST_DONE;
                        endcase
                    end
                end

                //=============================================================
                ST_MUL: begin
                    // 2-cycle multiply pipeline: cycle 0 latch product, cycle 1
                    // (mul_pipe=1) idle, cycle 2 (mul_pipe=0) result ready.
                    // Early-exit: if both operands fit in 17 bits, complete now.
                    if (mul_pipe == 2'd2) begin
                        mul_prod <= mul_a * mul_b;
                        if ((mul_a[31:16] == 16'h0) && (mul_b[31:16] == 16'h0)) begin
                            // early exit — result ≤ 32 bits, latch and finalize next cycle
                            mul_pipe <= 2'd0;
                        end else begin
                            mul_pipe <= 2'd1;
                        end
                    end else if (mul_pipe == 2'd1) begin
                        mul_pipe <= 2'd0;
                    end else begin
                        // Apply sign
                        if (result_neg_mul) begin
                            mul_prod <= (~mul_prod + 64'd1);
                        end
                        if (is_acc) begin
                            state <= ST_ACC;
                        end else if (op_r == OP_MUL) begin
                            // MUL rd form: low 32 bits go through lo_r for wrapper to select;
                            // HI/LO officially undefined — we still write full 64 bits.
                            hi_r  <= result_neg_mul ? ~mul_prod[63:32] + (mul_prod[31:0] == 32'h0 ? 32'h1 : 32'h0)
                                                    : mul_prod[63:32];
                            lo_r  <= result_neg_mul ? (~mul_prod[31:0] + 1'b1) : mul_prod[31:0];
                            state <= ST_DONE;
                        end else begin
                            hi_r  <= result_neg_mul ? ~mul_prod[63:32] + (mul_prod[31:0] == 32'h0 ? 32'h1 : 32'h0)
                                                    : mul_prod[63:32];
                            lo_r  <= result_neg_mul ? (~mul_prod[31:0] + 1'b1) : mul_prod[31:0];
                            state <= ST_DONE;
                        end
                    end
                end

                //=============================================================
                ST_ACC: begin
                    // MADD / MSUB accumulate: current {HI, LO} +/- signed mul_prod
                    acc_tmp = {hi_r, lo_r};
                    if (is_accsub) acc_tmp = acc_tmp - (result_neg_mul ? (~mul_prod + 64'd1) : mul_prod);
                    else           acc_tmp = acc_tmp + (result_neg_mul ? (~mul_prod + 64'd1) : mul_prod);
                    {hi_r, lo_r} <= acc_tmp;
                    state <= ST_DONE;
                end

                //=============================================================
                ST_DIV_ITR: begin
                    // Restoring division, 1 bit/cycle.
                    // Early exit: if divisor > dividend (magnitude), quotient = 0
                    if (div_ctr == 6'd32 && div_divisor > div_dividend_orig) begin
                        lo_r  <= 32'h0;
                        hi_r  <= result_neg_rem ? (~div_dividend_orig + 1'b1) : div_dividend_orig;
                        state <= ST_DONE;
                    end else if (div_ctr != 6'd0) begin
                        // Restoring division step: shift {rem, D} left, then
                        // if the new-rem (bits [62:31] of the pre-shift word,
                        // which becomes bits [63:32] after the shift-by-1)
                        // is >= divisor, subtract and set the quotient LSB=1;
                        // otherwise LSB=0.
                        if (div_ws[62:31] >= div_divisor) begin
                            div_ws <= {(div_ws[62:31] - div_divisor), div_ws[30:0], 1'b1};
                        end else begin
                            div_ws <= {div_ws[62:0], 1'b0};
                        end
                        div_ctr <= div_ctr - 1'b1;
                    end else begin
                        state <= ST_DIV_FIX;
                    end
                end

                //=============================================================
                ST_DIV_FIX: begin
                    if (is_signed) begin
                        lo_r <= result_neg_quot ? (~div_ws[31:0]  + 1'b1) : div_ws[31:0];
                        hi_r <= result_neg_rem  ? (~div_ws[63:32] + 1'b1) : div_ws[63:32];
                    end else begin
                        lo_r <= div_ws[31:0];
                        hi_r <= div_ws[63:32];
                    end
                    state <= ST_DONE;
                end

                //=============================================================
                ST_DONE: begin
                    done_pulse <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
