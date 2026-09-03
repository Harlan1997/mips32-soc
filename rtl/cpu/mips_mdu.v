// =============================================================================
// File Name: mips_mdu.v
// Design:    Multi-Cycle MDU — current DUT baseline
// Author:    Antigravity — Phase B.7
// Description:
//   Multi-cycle FSM MDU. Runs in parallel with the main pipeline; EX only
//   stalls on true HI/LO write-after-write / read-after-write hazards.
//   Current baseline MDU (the earlier single-cycle implementation was
//   retired after block-level verification of this one).
//   See docs/block_specs/mdu_spec.md.
//
//   Block RTL supports 4-bit ops (0..12), including MADD/MADDU/MSUB/MSUBU/MUL.
//   CPU pipeline integration in mips_ex_stage exposes the full Phase 4B
//   CPU-visible MDU operation path. MADD/MADDU/MSUB/MSUBU update HI/LO, and
//   MUL returns the low word through the normal GPR writeback path.
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
//   Multiplier: unsigned magnitude operands are accumulated with a
//   synthesizable radix-4 shift/add datapath. Four radix-4 digits (8
//   multiplier bits) are consumed per cycle, followed by one result commit
//   cycle. Signed operations use magnitude arithmetic and a final two's
//   complement, so the INT_MIN corner remains representable.
//
//   Divider: restoring radix-2 by default, with an opt-in radix-4 mode that
//   consumes two dividend bits per cycle. Early-exit: if divisor > dividend
//   in unsigned magnitude we skip iteration and return LO=0/HI=dividend.
// =============================================================================

`include "soc_config.vh"

module mips_mdu (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

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
    reg  [65:0] mul_acc;
    reg  [65:0] mul_mcand;
    reg  [31:0] mul_mult;
    reg  [2:0]  mul_ctr;     // four radix-4 chunks: 0..3
    reg         mul_short;
    reg         mul_commit_pending;

    // ---- Divider state ----
    reg  [31:0] div_divisor;
    reg  [63:0] div_ws;     // {rem, dividend_remaining}
    reg  [5:0]  div_ctr;
    reg  [31:0] div_dividend_orig;
    reg  [33:0] div_r4_rem;
    reg  [31:0] div_r4_quot;
    reg  [31:0] div_r4_bits;
    reg  [5:0]  div_r4_ctr;

    wire [33:0] div_r4_shifted = (div_r4_rem << 2) |
                                  {32'h0, div_r4_bits[31:30]};
    wire [33:0] div_r4_divisor = {2'b0, div_divisor};
    wire [33:0] div_r4_twice = div_r4_divisor << 1;
    wire [33:0] div_r4_thrice = div_r4_twice + div_r4_divisor;

    // ---- Busy ----
    // A multiply result parked in ST_DONE is still uncommitted. Keep the
    // pipeline stalled through the commit edge so consumers cannot observe
    // the previous HI/LO value in the pending-result window.
    assign busy = ((state != ST_IDLE) && (state != ST_DONE)) ||
                  ((state == ST_DONE) && mul_commit_pending);

    // Working temporary for MADD result
    reg [63:0] acc_tmp;

    // Process four radix-4 digits without using a behavioural multiply.  The
    // extra two accumulator bits absorb the intermediate carry before the
    // final 64-bit architectural result is committed.
    function [65:0] radix4_chunk;
        input [65:0] acc;
        input [65:0] mcand;
        input [31:0] multiplier;
        reg [65:0] t;
        reg [65:0] digit_mcand;
        integer digit;
        begin
            t = acc;
            digit_mcand = mcand;
            for (digit = 0; digit < 4; digit = digit + 1) begin
                case (multiplier[(digit * 2) +: 2])
                    2'b01: t = t + digit_mcand;
                    2'b10: t = t + (digit_mcand << 1);
                    2'b11: t = t + digit_mcand + (digit_mcand << 1);
                    default: ;
                endcase
                digit_mcand = digit_mcand << 2;
            end
            radix4_chunk = t;
        end
    endfunction

    // Short operands fit in 16 bits of magnitude.  Consume all eight
    // radix-4 digits in one combinational early-exit step; the following
    // state transition is still the same architectural commit boundary.
    function [65:0] radix4_short;
        input [65:0] acc;
        input [65:0] mcand;
        input [31:0] multiplier;
        reg [65:0] t;
        reg [65:0] digit_mcand;
        integer digit;
        begin
            t = acc;
            digit_mcand = mcand;
            for (digit = 0; digit < 8; digit = digit + 1) begin
                case (multiplier[(digit * 2) +: 2])
                    2'b01: t = t + digit_mcand;
                    2'b10: t = t + (digit_mcand << 1);
                    2'b11: t = t + digit_mcand + (digit_mcand << 1);
                    default: ;
                endcase
                digit_mcand = digit_mcand << 2;
            end
            radix4_short = t;
        end
    endfunction

    function [31:0] abs32;
        input [31:0] value;
        begin
            abs32 = value[31] ? (~value + 32'd1) : value;
        end
    endfunction

    function [5:0] leading_zeroes;
        input [31:0] value;
        integer bit_index;
        begin
            leading_zeroes = 6'd32;
            for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1)
                if ((leading_zeroes == 6'd32) && value[bit_index])
                    leading_zeroes = 6'd31 - bit_index;
        end
    endfunction

    wire [65:0] mul_acc_next = radix4_chunk(mul_acc, mul_mcand, mul_mult);
    wire [65:0] mul_short_next = radix4_short(mul_acc, mul_mcand, mul_mult);
    wire [63:0] mul_signed_next = result_neg_mul ?
                                   (~mul_acc_next[63:0] + 64'd1) :
                                   mul_acc_next[63:0];

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
            mul_acc           <= 66'h0;
            mul_mcand         <= 66'h0;
            mul_mult          <= 32'h0;
            mul_ctr           <= 3'h0;
            mul_short         <= 1'b0;
            mul_commit_pending <= 1'b0;
            div_divisor       <= 32'h0;
            div_ws            <= 64'h0;
            div_ctr           <= 6'h0;
            div_dividend_orig <= 32'h0;
            div_r4_rem        <= 34'h0;
            div_r4_quot       <= 32'h0;
            div_r4_bits       <= 32'h0;
            div_r4_ctr        <= 6'h0;
            done_pulse        <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            // A pipeline flush cancels an uncommitted operation. HI/LO are
            // intentionally untouched because the in-flight result has not
            // reached architectural state.
            if (flush) begin
                state             <= ST_IDLE;
                op_r              <= 4'h0;
                rs_r              <= 32'h0;
                rt_r              <= 32'h0;
                mul_acc           <= 66'h0;
                mul_mcand         <= 66'h0;
                mul_mult          <= 32'h0;
                mul_ctr           <= 3'h0;
                mul_short         <= 1'b0;
                mul_commit_pending <= 1'b0;
                div_ctr           <= 6'h0;
                div_ws            <= 64'h0;
                div_divisor       <= 32'h0;
                div_dividend_orig <= 32'h0;
                div_r4_rem        <= 34'h0;
                div_r4_quot       <= 32'h0;
                div_r4_bits       <= 32'h0;
                div_r4_ctr        <= 6'h0;
            end else case (state)
                //=============================================================
                ST_IDLE: begin
                    if (issue_valid) begin
                        op_r <= op;
                        rs_r <= rs_val;
                        rt_r <= rt_val;
                        case (op)
                            OP_MFHI, OP_MFLO: begin
                                // hi_out/lo_out are always live; caller selects
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
                                mul_acc        <= 66'h0;
                                mul_mcand      <= {34'h0, (rs_val[31] ? (~rs_val + 1'b1) : rs_val)};
                                mul_mult       <= (rt_val[31] ? (~rt_val + 1'b1) : rt_val);
                                mul_ctr        <= 3'd0;
                                mul_short      <= ((rs_val[31] ? (~rs_val + 1'b1) : rs_val) < 32'h0001_0000) &&
                                                   ((rt_val[31] ? (~rt_val + 1'b1) : rt_val) < 32'h0001_0000);
                                state          <= ST_MUL;
                            end
                            OP_MULTU, OP_MADDU, OP_MSUBU: begin
                                is_signed      <= 1'b0;
                                is_acc         <= (op == OP_MADDU) || (op == OP_MSUBU);
                                is_accsub      <= (op == OP_MSUBU);
                                mul_a          <= rs_val;
                                mul_b          <= rt_val;
                                result_neg_mul <= 1'b0;
                                mul_acc        <= 66'h0;
                                mul_mcand      <= {34'h0, rs_val};
                                mul_mult       <= rt_val;
                                mul_ctr        <= 3'd0;
                                mul_short      <= (rs_val < 32'h0001_0000) &&
                                                   (rt_val < 32'h0001_0000);
                                state          <= ST_MUL;
                            end
                            OP_DIV: begin
                                is_signed          <= 1'b1;
                                if (rt_val == 32'h0) begin
                                    // divide-by-zero: deterministic
                                    lo_r  <= 32'hFFFF_FFFF;
                                    hi_r  <= rs_val;
                                    state <= ST_DONE;
                                end else if (abs32(rt_val) > abs32(rs_val)) begin
                                    // Quotient is zero when the divisor is
                                    // already larger than the dividend. This
                                    // is an architectural early-exit; the
                                    // remainder keeps the dividend sign.
                                    lo_r  <= 32'h0;
                                    hi_r  <= rs_val;
                                    state <= ST_DONE;
                                end else if (rs_val == 32'h0) begin
                                    lo_r  <= 32'h0;
                                    hi_r  <= 32'h0;
                                    state <= ST_DONE;
                                end else begin
                                    div_divisor       <= abs32(rt_val);
                                    div_dividend_orig <= abs32(rs_val);
                                    div_r4_rem        <= 34'h0;
                                    div_r4_quot       <= 32'h0;
                                    div_r4_bits       <= abs32(rs_val);
                                    div_r4_ctr        <= 6'h0;
                                    if (`SOC_MDU_DIV_RADIX == 4) begin
                                        div_r4_bits <= abs32(rs_val) <<
                                            (leading_zeroes(abs32(rs_val)) -
                                             ((32 - leading_zeroes(abs32(rs_val))) & 1));
                                        div_r4_ctr <= ((32 - leading_zeroes(abs32(rs_val))) + 1) >> 1;
                                    end
                                    div_ws            <= {32'h0, abs32(rs_val)} <<
                                                         leading_zeroes(abs32(rs_val));
                                    div_ctr           <= 6'd32 -
                                                         leading_zeroes(abs32(rs_val));
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
                                end else if (rt_val > rs_val) begin
                                    lo_r  <= 32'h0;
                                    hi_r  <= rs_val;
                                    state <= ST_DONE;
                                end else if (rs_val == 32'h0) begin
                                    lo_r  <= 32'h0;
                                    hi_r  <= 32'h0;
                                    state <= ST_DONE;
                                end else begin
                                    div_divisor       <= rt_val;
                                    div_dividend_orig <= rs_val;
                                    div_r4_rem        <= 34'h0;
                                    div_r4_quot       <= 32'h0;
                                    div_r4_bits       <= rs_val;
                                    div_r4_ctr        <= 6'h0;
                                    if (`SOC_MDU_DIV_RADIX == 4) begin
                                        div_r4_bits <= rs_val <<
                                            (leading_zeroes(rs_val) -
                                             ((32 - leading_zeroes(rs_val)) & 1));
                                        div_r4_ctr <= ((32 - leading_zeroes(rs_val)) + 1) >> 1;
                                    end
                                    div_ws            <= {32'h0, rs_val} <<
                                                         leading_zeroes(rs_val);
                                    div_ctr           <= 6'd32 - leading_zeroes(rs_val);
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
                    if (mul_short) begin
                        mul_acc  <= mul_short_next;
                        mul_prod <= result_neg_mul ? (~mul_short_next[63:0] + 64'd1) :
                                    mul_short_next[63:0];
                        if (is_acc) begin
                            state <= ST_ACC;
                        end else begin
                            // Keep the result pending until ST_DONE so the
                            // common flush boundary can cancel it.
                            mul_commit_pending <= 1'b1;
                            state <= ST_DONE;
                        end
                    end else begin
                    // Each cycle consumes four radix-4 digits.  The fourth
                    // chunk covers multiplier bits [31:24], so its result is
                    // complete without a hidden behavioural multiplication.
                    mul_acc   <= mul_acc_next;
                    mul_mcand <= mul_mcand << 8;
                    mul_mult  <= mul_mult >> 8;
                    if (mul_ctr == 3'd3) begin
                        mul_prod <= mul_signed_next;
                        if (is_acc) begin
                            state <= ST_ACC;
                        end else begin
                            mul_commit_pending <= 1'b1;
                            state <= ST_DONE;
                        end
                    end else begin
                        mul_ctr <= mul_ctr + 1'b1;
                    end
                    end
                end

                //=============================================================
                ST_ACC: begin
                    // MADD / MSUB accumulate: current {HI, LO} +/- signed mul_prod.
                    // mul_prod was negated in ST_MUL if result_neg_mul was set.
                    acc_tmp = {hi_r, lo_r};
                    if (is_accsub) acc_tmp = acc_tmp - mul_prod;
                    else           acc_tmp = acc_tmp + mul_prod;
                    {hi_r, lo_r} <= acc_tmp;
                    state <= ST_DONE;
                end

                //=============================================================
                ST_DIV_ITR: begin
                    if (`SOC_MDU_DIV_RADIX == 4) begin
                        if (div_r4_ctr != 6'd0) begin
                            div_r4_bits <= div_r4_bits << 2;
                            if (div_r4_shifted >= div_r4_thrice) begin
                                div_r4_rem  <= div_r4_shifted - div_r4_thrice;
                                div_r4_quot <= (div_r4_quot << 2) | 32'd3;
                            end else if (div_r4_shifted >= div_r4_twice) begin
                                div_r4_rem  <= div_r4_shifted - div_r4_twice;
                                div_r4_quot <= (div_r4_quot << 2) | 32'd2;
                            end else if (div_r4_shifted >= div_r4_divisor) begin
                                div_r4_rem  <= div_r4_shifted - div_r4_divisor;
                                div_r4_quot <= (div_r4_quot << 2) | 32'd1;
                            end else begin
                                div_r4_rem  <= div_r4_shifted;
                                div_r4_quot <= div_r4_quot << 2;
                            end
                            div_r4_ctr <= div_r4_ctr - 1'b1;
                        end else begin
                            state <= ST_DIV_FIX;
                        end
                    end else begin
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
                end

                //=============================================================
                ST_DIV_FIX: begin
                    if (`SOC_MDU_DIV_RADIX == 4) begin
                        if (is_signed) begin
                            lo_r <= result_neg_quot ? (~div_r4_quot + 32'd1) : div_r4_quot;
                            hi_r <= result_neg_rem ? (~div_r4_rem[31:0] + 32'd1) : div_r4_rem[31:0];
                        end else begin
                            lo_r <= div_r4_quot;
                            hi_r <= div_r4_rem[31:0];
                        end
                    end else if (is_signed) begin
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
                    if (mul_commit_pending) begin
                        hi_r <= mul_prod[63:32];
                        lo_r <= mul_prod[31:0];
                        mul_commit_pending <= 1'b0;
                    end
                    done_pulse <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
