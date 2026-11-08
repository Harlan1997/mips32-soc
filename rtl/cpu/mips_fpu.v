// Opt-in COP1 execution primitive.  Single precision is the original path;
// the double-precision path is a behavioral register-pair extension used by
// the development contract.  Synthesis, exact trap policy, and OS ABI remain
// separate contracts.
module mips_fpu (
    input wire [4:0] op, input wire [31:0] a, input wire [31:0] b,
    output reg [31:0] result, output reg compare_true,
    // COP1 compare condition, matching funct[3:0] for C.* (0x30..0x3f).
    // 0=F, 1=UN, 2=EQ, 3=UEQ, 4=OLT, 5=ULT, 6=OLE, 7=ULE,
    // 8=SF, 9=NGLE, A=SEQ, B=NGL, C=LT, D=NGE, E=LE, F=NGT.
    input wire [3:0] compare_condition,
    input wire fmt_double,
    // FCSR.RM: 00 nearest-even, 01 toward-zero, 10 toward +inf,
    // 11 toward -inf. Fixed ROUND/TRUNC/CEIL/FLOOR opcodes override it.
    input wire [1:0] rounding_mode,
    input wire [63:0] a_double, input wire [63:0] b_double,
    input wire [31:0] c, input wire [63:0] c_double,
    output reg [63:0] result_double,
    output reg [31:0] result_word,
    // [0]=inexact, [1]=underflow, [2]=overflow, [3]=divide-by-zero,
    // [4]=invalid.  Trap enable/precise exception delivery is CPU policy.
    output reg [4:0] exception_flags
);
    localparam OP_ADD=5'd0, OP_SUB=5'd1, OP_MUL=5'd2, OP_DIV=5'd3,
               OP_SQRT=5'd4, OP_ABS=5'd5, OP_MOV=5'd6, OP_NEG=5'd7,
               OP_CMP=5'd8, OP_CVT_S_W=5'd9, OP_CVT_W_S=5'd10,
               OP_ROUND_W=5'd11, OP_TRUNC_W=5'd12, OP_CEIL_W=5'd13,
               OP_FLOOR_W=5'd14, OP_CVT_S_D=5'd15, OP_CVT_D_S=5'd16,
               OP_CVT_D_W=5'd17, OP_CVT_W_D=5'd18,
               OP_ROUND_W_D=5'd19, OP_TRUNC_W_D=5'd20,
               OP_CEIL_W_D=5'd21, OP_FLOOR_W_D=5'd22,
               OP_RECIP=5'd23, OP_RSQRT=5'd24,
               OP_MADD=5'd25, OP_MSUB=5'd26,
               OP_NMADD=5'd27, OP_NMSUB=5'd28;

    function automatic signed [31:0] round_real_to_word;
        input real value;
        input [1:0] mode;
        real lower;
        real fraction;
        integer base;
        integer rounded;
        begin
            case (mode)
                2'b01: rounded = $rtoi(value);
                2'b10: rounded = $rtoi($ceil(value));
                2'b11: rounded = $rtoi($floor(value));
                default: begin
                    lower = $floor(value);
                    base = $rtoi(lower);
                    fraction = value - lower;
                    if ((fraction > 0.5) ||
                        ((fraction == 0.5) && ((base & 1) != 0)))
                        rounded = base + 1;
                    else
                        rounded = base;
                end
            endcase
            round_real_to_word = rounded;
        end
    endfunction
    // MIPS ROUND.W.{S,D} uses round-to-nearest with ties away from zero.
    // Keep this separate from CVT.W.*, whose 00 mode is nearest-even.
    function automatic signed [31:0] round_real_nearest_away;
        input real value;
        real magnitude;
        integer rounded_abs;
        begin
            magnitude = (value < 0.0) ? -value : value;
            rounded_abs = $rtoi($floor(magnitude + 0.5));
            round_real_nearest_away = (value < 0.0) ? -rounded_abs : rounded_abs;
        end
    endfunction

    // Return the adjacent single-precision value in numeric order. These
    // encoded operations keep directed rounding deterministic when a host
    // simulator flushes subnormals during real/shortreal conversion.
    function automatic [31:0] single_next_up;
        input [31:0] bits;
        begin
            if ((bits[30:23] == 8'hff) && (bits[22:0] != 0))
                single_next_up = bits;              // NaN
            else if (bits == 32'h7f80_0000)
                single_next_up = bits;              // +Inf
            else if (bits == 32'h8000_0000)
                single_next_up = 32'd0;             // -0 -> +0
            else if (bits[31])
                single_next_up = bits - 32'd1;      // toward +Inf
            else
                single_next_up = bits + 32'd1;
        end
    endfunction

    function automatic [31:0] single_next_down;
        input [31:0] bits;
        begin
            if ((bits[30:23] == 8'hff) && (bits[22:0] != 0))
                single_next_down = bits;            // NaN
            else if (bits == 32'hff80_0000)
                single_next_down = bits;            // -Inf
            else if (bits == 32'd0)
                single_next_down = 32'h8000_0001;   // +0 -> -minsub
            else if (bits[31])
                single_next_down = bits + 32'd1;    // toward -Inf
            else
                single_next_down = bits - 32'd1;
        end
    endfunction

    // $shortrealtobits performs nearest-even conversion. Correct that result
    // by one ULP for the three directed MIPS rounding modes.
    function automatic [31:0] round_single_real;
        input real exact_value;
        input [1:0] mode;
        reg [31:0] nearest_bits;
        reg [31:0] rounded_bits;
        shortreal nearest_short;
        real nearest_value;
        begin
            nearest_bits = $shortrealtobits(exact_value);
            rounded_bits = nearest_bits;
            nearest_short = $bitstoshortreal(nearest_bits);
            nearest_value = nearest_short;
            if (mode != 2'b00 && nearest_value != exact_value) begin
                case (mode)
                    2'b01: begin // toward zero
                        if (exact_value >= 0.0) begin
                            if (nearest_value > exact_value)
                                rounded_bits = single_next_down(nearest_bits);
                        end else if (nearest_value < exact_value) begin
                            rounded_bits = single_next_up(nearest_bits);
                        end
                    end
                    2'b10: begin // toward +infinity
                        if (nearest_value < exact_value)
                            rounded_bits = single_next_up(nearest_bits);
                    end
                    default: begin // toward -infinity
                        if (nearest_value > exact_value)
                            rounded_bits = single_next_down(nearest_bits);
                    end
                endcase
            end
            round_single_real = rounded_bits;
        end
    endfunction

    // Round an exact finite binary64 add/subtract result.  A Verilog real is
    // itself binary64, so using it as the intermediate loses the low bits
    // needed to distinguish a value just below or above a halfway boundary.
    // The operands below are represented as signed integer significands at a
    // common binary exponent.  The wide accumulator also retains a sticky tail
    // when the operands are separated by the full binary64 exponent range.
    // Return {inexact, result_bits}.
    function automatic [64:0] round_double_add_exact;
        input [63:0] lhs;
        input [63:0] rhs;
        input [1:0] mode;
        reg [52:0] lhs_mant;
        reg [52:0] rhs_mant;
        integer lhs_exp;
        integer rhs_exp;
        integer common_exp;
        integer lhs_shift;
        integer rhs_shift;
        reg signed [4095:0] lhs_term;
        reg signed [4095:0] rhs_term;
        reg signed [4095:0] exact_sum;
        reg [4095:0] magnitude;
        integer i;
        integer highest;
        integer exact_exp;
        integer discard_shift;
        integer subnormal_shift;
        reg [53:0] significand;
        reg [4095:0] subnormal_value;
        reg guard_bit;
        reg sticky_bit;
        reg discarded;
        reg round_up;
        reg result_sign;
        integer packed_exp;
        reg [10:0] exponent_field;
        reg [63:0] packed_result;
        reg inexact_result;
        begin
            packed_result = 64'd0;
            inexact_result = 1'b0;
            lhs_mant = 53'd0;
            rhs_mant = 53'd0;
            lhs_exp = -1074;
            rhs_exp = -1074;
            if (lhs[62:52] == 0) begin
                lhs_mant = {1'b0, lhs[51:0]};
                lhs_exp = -1074;
            end else begin
                lhs_mant = {1'b1, lhs[51:0]};
                lhs_exp = lhs[62:52];
                lhs_exp = lhs_exp - 1023 - 52;
            end
            if (rhs[62:52] == 0) begin
                rhs_mant = {1'b0, rhs[51:0]};
                rhs_exp = -1074;
            end else begin
                rhs_mant = {1'b1, rhs[51:0]};
                rhs_exp = rhs[62:52];
                rhs_exp = rhs_exp - 1023 - 52;
            end

            common_exp = (lhs_exp < rhs_exp) ? lhs_exp : rhs_exp;
            lhs_shift = lhs_exp - common_exp;
            rhs_shift = rhs_exp - common_exp;
            lhs_term = 4096'sd0;
            rhs_term = 4096'sd0;
            lhs_term[52:0] = lhs_mant;
            rhs_term[52:0] = rhs_mant;
            lhs_term = lhs_term <<< lhs_shift;
            rhs_term = rhs_term <<< rhs_shift;
            if (lhs[63]) lhs_term = -lhs_term;
            if (rhs[63]) rhs_term = -rhs_term;
            exact_sum = lhs_term + rhs_term;

            if (exact_sum == 0) begin
                // Exact cancellation is +0 except under round-toward-minus-
                // infinity, where IEEE-754 preserves a negative zero.
                packed_result = {(mode == 2'b11), 63'd0};
            end else begin
                result_sign = (exact_sum < 0);
                magnitude = result_sign ? -exact_sum : exact_sum;
                highest = -1;
                for (i = 4095; i >= 0; i = i - 1)
                    if (highest == -1 && magnitude[i]) highest = i;
                exact_exp = common_exp + highest;

                if (exact_exp >= -1022) begin
                    // Keep the leading 53 bits for a normal result.
                    discard_shift = highest - 52;
                    significand = 54'd0;
                    guard_bit = 1'b0;
                    sticky_bit = 1'b0;
                    if (discard_shift > 0) begin
                        significand = magnitude >> discard_shift;
                        guard_bit = magnitude[discard_shift - 1];
                        for (i = 0; i < discard_shift - 1; i = i + 1)
                            if (magnitude[i]) sticky_bit = 1'b1;
                    end else begin
                        significand = magnitude << (-discard_shift);
                    end
                    discarded = guard_bit | sticky_bit;
                    case (mode)
                        2'b01: round_up = 1'b0;
                        2'b10: round_up = !result_sign && discarded;
                        2'b11: round_up = result_sign && discarded;
                        default: round_up = guard_bit && (sticky_bit || significand[0]);
                    endcase
                    if (round_up) significand = significand + 1'b1;
                    packed_exp = exact_exp;
                    if (significand[53]) begin
                        significand = significand >> 1;
                        packed_exp = packed_exp + 1;
                    end
                    if (packed_exp > 1023) begin
                        // Overflow selects infinity or max finite according
                        // to the active directed mode and the result sign.
                        inexact_result = 1'b1;
                        if (mode == 2'b00 ||
                            (mode == 2'b10 && !result_sign) ||
                            (mode == 2'b11 && result_sign))
                            packed_result = {result_sign, 11'h7ff, 52'd0};
                        else
                            packed_result = {result_sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
                    end else begin
                        inexact_result = discarded;
                        exponent_field = packed_exp + 1023;
                        packed_result = {result_sign, exponent_field,
                                         significand[51:0]};
                    end
                end else begin
                    // Subnormal results are rounded in units of 2^-1074.
                    subnormal_shift = common_exp + 1074;
                    subnormal_value = 4096'd0;
                    guard_bit = 1'b0;
                    sticky_bit = 1'b0;
                    if (subnormal_shift >= 0) begin
                        subnormal_value = magnitude << subnormal_shift;
                    end else begin
                        subnormal_shift = -subnormal_shift;
                        subnormal_value = magnitude >> subnormal_shift;
                        guard_bit = magnitude[subnormal_shift - 1];
                        for (i = 0; i < subnormal_shift - 1; i = i + 1)
                            if (magnitude[i]) sticky_bit = 1'b1;
                    end
                    discarded = guard_bit | sticky_bit;
                    case (mode)
                        2'b01: round_up = 1'b0;
                        2'b10: round_up = !result_sign && discarded;
                        2'b11: round_up = result_sign && discarded;
                        default: round_up = guard_bit &&
                                             (sticky_bit || subnormal_value[0]);
                    endcase
                    if (round_up) subnormal_value = subnormal_value + 1'b1;
                    inexact_result = discarded;
                    if (subnormal_value[52])
                        packed_result = {result_sign, 11'd1, 52'd0};
                    else
                        packed_result = {result_sign, 11'd0,
                                         subnormal_value[51:0]};
                end
            end
            round_double_add_exact = {inexact_result, packed_result};
        end
    endfunction

    function automatic [63:0] double_next_up;
        input [63:0] bits;
        begin
            if ((bits[62:52] == 11'h7ff) && (bits[51:0] != 0))
                double_next_up = bits;
            else if (bits == 64'h7ff0_0000_0000_0000)
                double_next_up = bits;
            else if (bits == 64'h8000_0000_0000_0000)
                double_next_up = 64'd0;
            else if (bits[63])
                double_next_up = bits - 64'd1;
            else
                double_next_up = bits + 64'd1;
        end
    endfunction

    function automatic [63:0] double_next_down;
        input [63:0] bits;
        begin
            if ((bits[62:52] == 11'h7ff) && (bits[51:0] != 0))
                double_next_down = bits;
            else if (bits == 64'hfff0_0000_0000_0000)
                double_next_down = bits;
            else if (bits == 64'd0)
                double_next_down = 64'h8000_0000_0000_0001;
            else if (bits[63])
                double_next_down = bits + 64'd1;
            else
                double_next_down = bits - 64'd1;
        end
    endfunction

    // Compare an exact finite binary64 product with a candidate result.  The
    // return value is 01 when exact<candidate, 10 when exact>candidate and 00
    // when they are equal.  The product is retained at full 106-bit precision
    // before the two values are aligned in the wide signed accumulator.
    function automatic [1:0] compare_double_mul_exact;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] candidate;
        reg [52:0] lhs_mant;
        reg [52:0] rhs_mant;
        reg [105:0] lhs_ext;
        reg [105:0] rhs_ext;
        reg [105:0] product;
        integer lhs_exp;
        integer rhs_exp;
        integer product_exp;
        integer candidate_exp;
        integer common_exp;
        integer product_shift;
        integer candidate_shift;
        reg [52:0] candidate_mant;
        reg signed [8191:0] product_term;
        reg signed [8191:0] candidate_term;
        begin
            compare_double_mul_exact = 2'b00;
            lhs_mant = (lhs[62:52] == 0) ? {1'b0, lhs[51:0]} :
                       {1'b1, lhs[51:0]};
            rhs_mant = (rhs[62:52] == 0) ? {1'b0, rhs[51:0]} :
                       {1'b1, rhs[51:0]};
            lhs_exp = (lhs[62:52] == 0) ? -1074 : lhs[62:52] - 1023 - 52;
            rhs_exp = (rhs[62:52] == 0) ? -1074 : rhs[62:52] - 1023 - 52;
            lhs_ext = 106'd0;
            rhs_ext = 106'd0;
            lhs_ext[52:0] = lhs_mant;
            rhs_ext[52:0] = rhs_mant;
            product = lhs_ext * rhs_ext;
            product_exp = lhs_exp + rhs_exp;

            // An overflowed nearest result is still a valid comparison target:
            // every finite positive product is below +Inf and every finite
            // negative product is above -Inf.
            if (candidate[62:52] == 11'h7ff && candidate[51:0] == 0) begin
                if (candidate[63] == (lhs[63] ^ rhs[63]))
                    compare_double_mul_exact = candidate[63] ? 2'b10 : 2'b01;
            end else begin
                candidate_mant = (candidate[62:52] == 0) ?
                                 {1'b0, candidate[51:0]} :
                                 {1'b1, candidate[51:0]};
                candidate_exp = (candidate[62:52] == 0) ? -1074 :
                                candidate[62:52] - 1023 - 52;
                common_exp = (product_exp < candidate_exp) ?
                             product_exp : candidate_exp;
                product_shift = product_exp - common_exp;
                candidate_shift = candidate_exp - common_exp;
                product_term = 8192'sd0;
                candidate_term = 8192'sd0;
                product_term[105:0] = product;
                candidate_term[52:0] = candidate_mant;
                product_term = product_term <<< product_shift;
                candidate_term = candidate_term <<< candidate_shift;
                if (lhs[63] ^ rhs[63]) product_term = -product_term;
                if (candidate[63]) candidate_term = -candidate_term;
                if (product_term < candidate_term)
                    compare_double_mul_exact = 2'b01;
                else if (product_term > candidate_term)
                    compare_double_mul_exact = 2'b10;
            end
        end
    endfunction

    shortreal ar, br, rr;
    real ar_real, br_real, c_real;
    real ar_double, br_double, cr_double, rr_double, exact_single,
         exact_double, exact_arithmetic;
    reg a_nan, b_nan, a_snan, b_snan, unordered;
    reg single_bits_override_valid, double_bits_override_valid;
    reg [31:0] single_bits_override;
    reg [63:0] double_bits_override;
    reg [64:0] double_exact_pack;
    reg double_exact_valid;
    reg double_exact_inexact;
    reg [1:0] double_mul_relation;
    always @(*) begin
        ar = $bitstoshortreal(a);
        br = $bitstoshortreal(b);
        ar_real = ar;
        br_real = br;
        c_real = $bitstoshortreal(c);
        rr = 0.0;
        exact_single = 0.0;
        ar_double = $bitstoreal(a_double);
        br_double = $bitstoreal(b_double);
        cr_double = $bitstoreal(c_double);
        rr_double = 0.0;
        result_word = 32'd0;
        compare_true = 1'b0;
        exception_flags = 5'd0;
        a_nan = 1'b0;
        b_nan = 1'b0;
        a_snan = 1'b0;
        b_snan = 1'b0;
        unordered = 1'b0;
        single_bits_override_valid = 1'b0;
        double_bits_override_valid = 1'b0;
        single_bits_override = 32'd0;
        double_bits_override = 64'd0;
        double_exact_pack = 65'd0;
        double_exact_valid = 1'b0;
        double_exact_inexact = 1'b0;
        double_mul_relation = 2'b00;
        exact_double = 0.0;
        exact_arithmetic = 0.0;
        if (fmt_double) begin
            a_nan = (a_double[62:52] == 11'h7ff && a_double[51:0] != 0);
            b_nan = (b_double[62:52] == 11'h7ff && b_double[51:0] != 0);
            // 24Kf uses the pre-NAN2008 MIPS encoding: fraction MSB one
            // denotes signaling NaN, while zero denotes quiet NaN.
            a_snan = a_nan && a_double[51];
            b_snan = b_nan && b_double[51];
            unordered = a_nan || b_nan;
            // MOV/ABS/NEG are bitwise operations.  A NaN operand is not an
            // invalid arithmetic operation for these instructions; preserve
            // the payload without changing FCSR sticky Invalid.
            if (unordered && op != OP_ABS && op != OP_MOV && op != OP_NEG &&
                (op != OP_CMP || a_snan || b_snan || compare_condition[3]))
                exception_flags[4] = 1'b1;
            if (op == OP_DIV && b_double[62:52] == 0 &&
                b_double[51:0] == 0) begin
                if ((a_double[62:52] == 0 && a_double[51:0] == 0) ||
                    (a_double[62:52] == 11'h7ff && a_double[51:0] != 0))
                    exception_flags[4] = 1'b1;
                else
                    exception_flags[3] = 1'b1;
            end
            case (op)
                OP_ADD:  rr_double = ar_double + br_double;
                OP_SUB:  rr_double = ar_double - br_double;
                OP_MUL:  rr_double = ar_double * br_double;
                OP_DIV:  rr_double = ar_double / br_double;
                OP_SQRT: begin
                    // Protect the simulator math primitive from NaN/negative
                    // inputs; the architectural invalid result is modeled
                    // without invoking an implementation-defined system call.
                    if (a_nan) begin
                        rr_double = ar_double;
                        exception_flags[4] = 1'b1;
                    end else if (a_double[63] && (a_double[62:0] != 0)) begin
                        rr_double = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a_double == 64'h8000000000000000) begin
                        // IEEE-754 sqrt(-0) is -0 and is not Invalid.
                        rr_double = $bitstoreal(a_double);
                    end else begin
                        rr_double = $sqrt(ar_double);
                    end
                end
                OP_ABS: begin
                    rr_double = (ar_double < 0.0) ? -ar_double : ar_double;
                    double_bits_override_valid = 1'b1;
                    double_bits_override = a_double & 64'h7fff_ffff_ffff_ffff;
                end
                OP_MOV: begin
                    rr_double = ar_double;
                    double_bits_override_valid = 1'b1;
                    double_bits_override = a_double;
                end
                OP_NEG: begin
                    rr_double = -ar_double;
                    double_bits_override_valid = 1'b1;
                    double_bits_override = a_double ^ 64'h8000_0000_0000_0000;
                end
                OP_MADD:  rr_double = (ar_double * br_double) + cr_double;
                OP_MSUB:  rr_double = (ar_double * br_double) - cr_double;
                OP_NMADD: rr_double = -((ar_double * br_double) + cr_double);
                OP_NMSUB: rr_double = -((ar_double * br_double) - cr_double);
                OP_RECIP: begin
                    if (a_nan) begin
                        rr_double = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a_double[62:52] == 0 && a_double[51:0] == 0) begin
                        // MIPS RECIP follows the IEEE divide-by-zero boundary:
                        // reciprocal of signed zero is signed infinity.
                        rr_double = 0.0;
                        double_bits_override_valid = 1'b1;
                        double_bits_override = {a_double[63], 11'h7ff, 52'd0};
                        exception_flags[3] = 1'b1;
                    end else if (a_double[62:52] == 11'h7ff &&
                                 a_double[51:0] == 0) begin
                        // The reciprocal of signed infinity is signed zero.
                        rr_double = 0.0;
                        double_bits_override_valid = 1'b1;
                        double_bits_override = {a_double[63], 63'd0};
                    end else begin
                        rr_double = 1.0 / ar_double;
                    end
                end
                OP_RSQRT: begin
                    if (a_nan || (a_double[63] && (a_double[62:0] != 0))) begin
                        rr_double = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a_double[62:52] == 0 && a_double[51:0] == 0) begin
                        // sqrt(-0) is -0, so its reciprocal is signed -Inf;
                        // both signed zeros raise Divide-by-zero here.
                        rr_double = 0.0;
                        double_bits_override_valid = 1'b1;
                        double_bits_override = {a_double[63], 11'h7ff, 52'd0};
                        exception_flags[3] = 1'b1;
                    end else if (a_double[62:52] == 11'h7ff &&
                                 a_double[51:0] == 0) begin
                        rr_double = 0.0;
                        double_bits_override_valid = 1'b1;
                        double_bits_override = 64'd0;
                    end else begin
                        rr_double = 1.0 / $sqrt(ar_double);
                    end
                end
                OP_CVT_S_D: begin
                    if (a_nan) begin
                        rr = ar_double;
                        exception_flags[4] = 1'b1;
                    end else begin
                        rr = ar_double;
                        if (rr != ar_double)
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_CVT_W_D, OP_ROUND_W_D, OP_TRUNC_W_D,
                OP_CEIL_W_D, OP_FLOOR_W_D: begin
                    // MIPS conversion to a 32-bit signed integer raises
                    // Invalid for NaN, infinity, or values outside the
                    // representable interval.  Do not pass those values to
                    // host $rtoi: its out-of-range result is simulator
                    // dependent and would make FCSR behavior nondeterministic.
                    if (a_nan || a_double[62:52] == 11'h7ff ||
                        ar_double >= 2147483648.0 ||
                        ar_double < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        case (op)
                            OP_CVT_W_D:
                                result_word = round_real_to_word(ar_double,
                                                                 rounding_mode);
                            OP_TRUNC_W_D:
                                result_word = round_real_to_word(ar_double,
                                                                 2'b01);
                            OP_ROUND_W_D:
                                result_word = round_real_nearest_away(ar_double);
                            OP_CEIL_W_D:
                                result_word = round_real_to_word(ar_double,
                                                                 2'b10);
                            default:
                                result_word = round_real_to_word(ar_double,
                                                                 2'b11);
                        endcase
                        if (ar_double != $itor($rtoi(ar_double)))
                            exception_flags[0] = 1'b1;
                    end
                end
                // Conversion results are returned through the single-word
                // result port; these W/S forms are kept out of the D path.
                OP_CVT_W_S, OP_ROUND_W, OP_TRUNC_W, OP_CEIL_W, OP_FLOOR_W:
                    rr_double = 0.0;
                OP_CMP: begin
                    case (compare_condition)
                        4'h0, 4'h8: compare_true = 1'b0;
                        4'h1:       compare_true = unordered;
                        4'h2:       compare_true = !unordered && (ar_double == br_double);
                        4'h3:       compare_true = unordered || (ar_double == br_double);
                        4'h4:       compare_true = !unordered && (ar_double < br_double);
                        4'h5:       compare_true = unordered || (ar_double < br_double);
                        4'h6:       compare_true = !unordered && (ar_double <= br_double);
                        4'h7:       compare_true = unordered || (ar_double <= br_double);
                        4'h9:       compare_true = unordered;
                        4'ha:       compare_true = !unordered && (ar_double == br_double);
                        4'hb:       compare_true = unordered || (ar_double == br_double);
                        4'hc:       compare_true = !unordered && (ar_double < br_double);
                        4'hd:       compare_true = unordered || (ar_double < br_double);
                        4'he:       compare_true = !unordered && (ar_double <= br_double);
                        4'hf:       compare_true = unordered || (ar_double <= br_double);
                        default:    compare_true = 1'b0;
                    endcase
                end
                default: rr_double = 0.0;
            endcase
        end else begin
            a_nan = (a[30:23] == 8'hff && a[22:0] != 0);
            b_nan = (b[30:23] == 8'hff && b[22:0] != 0);
            // Legacy MIPS NaN encoding is opposite the IEEE-754 quiet-bit
            // convention used by the raw bit pattern.
            a_snan = a_nan && a[22];
            b_snan = b_nan && b[22];
            unordered = a_nan || b_nan;
            // The sign/move operations above are non-arithmetic and must not
            // raise Invalid merely because their operand is a NaN.
            if (unordered && op != OP_ABS && op != OP_MOV && op != OP_NEG &&
                (op != OP_CMP || a_snan || b_snan || compare_condition[3]))
                exception_flags[4] = 1'b1;
            if (op == OP_DIV && b[30:23] == 0 && b[22:0] == 0) begin
                if ((a[30:23] == 0 && a[22:0] == 0) ||
                    (a[30:23] == 8'hff && a[22:0] != 0))
                    exception_flags[4] = 1'b1;
                else
                    exception_flags[3] = 1'b1;
            end
            case (op)
                OP_ADD:  rr = ar + br;
                OP_SUB:  rr = ar - br;
                OP_MUL:  rr = ar * br;
                OP_DIV:  rr = ar / br;
                OP_SQRT: begin
                    if (a_nan) begin
                        rr = ar;
                        exception_flags[4] = 1'b1;
                    end else if (a[31] && (a[30:0] != 0)) begin
                        rr = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a == 32'h80000000) begin
                        // IEEE-754 sqrt(-0) is -0 and is not Invalid.
                        rr = $bitstoshortreal(a);
                    end else begin
                        rr = $sqrt(ar);
                    end
                end
                OP_ABS: begin
                    rr = (ar < 0.0) ? -ar : ar;
                    single_bits_override_valid = 1'b1;
                    single_bits_override = a & 32'h7fff_ffff;
                end
                OP_MOV: begin
                    rr = ar;
                    single_bits_override_valid = 1'b1;
                    single_bits_override = a;
                end
                OP_NEG: begin
                    rr = -ar;
                    single_bits_override_valid = 1'b1;
                    single_bits_override = a ^ 32'h8000_0000;
                end
                OP_MADD:  rr = (ar * br) + $bitstoshortreal(c);
                OP_MSUB:  rr = (ar * br) - $bitstoshortreal(c);
                OP_NMADD: rr = -((ar * br) + $bitstoshortreal(c));
                OP_NMSUB: rr = -((ar * br) - $bitstoshortreal(c));
                OP_RECIP: begin
                    if (a_nan) begin
                        rr = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a[30:23] == 0 && a[22:0] == 0) begin
                        // Reciprocal of signed zero is signed infinity and
                        // raises Divide-by-zero.
                        rr = 0.0;
                        single_bits_override_valid = 1'b1;
                        single_bits_override = {a[31], 8'hff, 23'd0};
                        exception_flags[3] = 1'b1;
                    end else if (a[30:23] == 8'hff && a[22:0] == 0) begin
                        // The reciprocal of signed infinity is signed zero.
                        rr = 0.0;
                        single_bits_override_valid = 1'b1;
                        single_bits_override = {a[31], 31'd0};
                    end else begin
                        rr = 1.0 / ar;
                    end
                end
                OP_RSQRT: begin
                    if (a_nan || (a[31] && (a[30:0] != 0))) begin
                        rr = 0.0;
                        exception_flags[4] = 1'b1;
                    end else if (a[30:23] == 0 && a[22:0] == 0) begin
                        // Preserve the sign of zero through sqrt and its
                        // reciprocal; both signed-zero inputs divide by zero.
                        rr = 0.0;
                        single_bits_override_valid = 1'b1;
                        single_bits_override = {a[31], 8'hff, 23'd0};
                        exception_flags[3] = 1'b1;
                    end else if (a[30:23] == 8'hff && a[22:0] == 0) begin
                        rr = 0.0;
                        single_bits_override_valid = 1'b1;
                        single_bits_override = 32'd0;
                    end else begin
                        rr = 1.0 / $sqrt(ar);
                    end
                end
                OP_CVT_S_W: rr = $itor($signed(a));
                OP_CVT_D_S: rr_double = ar;
                OP_CVT_D_W: rr_double = $itor($signed(a));
                OP_CVT_W_S: begin
                    if (a_nan || a[30:23] == 8'hff ||
                        ar >= 2147483648.0 || ar < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        result_word = round_real_to_word(ar, rounding_mode);
                        if (ar != $itor($rtoi(ar)))
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_ROUND_W: begin
                    if (a_nan || a[30:23] == 8'hff ||
                        ar >= 2147483648.0 || ar < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        result_word = round_real_nearest_away(ar);
                        if (ar != $itor($rtoi(ar)))
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_TRUNC_W: begin
                    if (a_nan || a[30:23] == 8'hff ||
                        ar >= 2147483648.0 || ar < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        result_word = round_real_to_word(ar, 2'b01);
                        if (ar != $itor($rtoi(ar)))
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_CEIL_W: begin
                    if (a_nan || a[30:23] == 8'hff ||
                        ar >= 2147483648.0 || ar < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        result_word = round_real_to_word(ar, 2'b10);
                        if (ar != $itor($rtoi(ar)))
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_FLOOR_W: begin
                    if (a_nan || a[30:23] == 8'hff ||
                        ar >= 2147483648.0 || ar < -2147483648.0) begin
                        result_word = 32'h80000000;
                        exception_flags[4] = 1'b1;
                    end else begin
                        result_word = round_real_to_word(ar, 2'b11);
                        if (ar != $itor($rtoi(ar)))
                            exception_flags[0] = 1'b1;
                    end
                end
                OP_CMP: begin
                    case (compare_condition)
                        4'h0, 4'h8: compare_true = 1'b0;
                        4'h1:       compare_true = unordered;
                        4'h2:       compare_true = !unordered && (ar == br);
                        4'h3:       compare_true = unordered || (ar == br);
                        4'h4:       compare_true = !unordered && (ar < br);
                        4'h5:       compare_true = unordered || (ar < br);
                        4'h6:       compare_true = !unordered && (ar <= br);
                        4'h7:       compare_true = unordered || (ar <= br);
                        4'h9:       compare_true = unordered;
                        4'ha:       compare_true = !unordered && (ar == br);
                        4'hb:       compare_true = unordered || (ar == br);
                        4'hc:       compare_true = !unordered && (ar < br);
                        4'hd:       compare_true = unordered || (ar < br);
                        4'he:       compare_true = !unordered && (ar <= br);
                        4'hf:       compare_true = unordered || (ar <= br);
                        default:    compare_true = 1'b0;
                    endcase
                end
                default: rr = 0.0;
            endcase
        end
        result = $shortrealtobits(rr);
        result_double = $realtobits(rr_double);
        if (single_bits_override_valid)
            result = single_bits_override;
        if (double_bits_override_valid)
            result_double = double_bits_override;

        // ADD.D, SUB.D and MUL.D are routed through exact significand logic.
        // This removes host-binary64 ambiguity at directed-rounding boundaries
        // while leaving the other double operations on their existing
        // behavioral implementation.
        if (fmt_double && !a_nan && !b_nan &&
            a_double[62:52] != 11'h7ff && b_double[62:52] != 11'h7ff &&
            (op == OP_ADD || op == OP_SUB)) begin
            double_exact_pack = round_double_add_exact(
                a_double,
                (op == OP_SUB) ? (b_double ^ 64'h8000_0000_0000_0000) : b_double,
                rounding_mode);
            result_double = double_exact_pack[63:0];
            double_exact_inexact = double_exact_pack[64];
            double_exact_valid = 1'b1;
        end

        // The host multiply supplies the correctly rounded nearest result.
        // Compare that result with the exact 106-bit product before applying
        // directed rounding, so overflow and underflow remain visible even
        // when the selected mode returns a finite value.
        if (fmt_double && !a_nan && !b_nan &&
            a_double[62:52] != 11'h7ff && b_double[62:52] != 11'h7ff &&
            op == OP_MUL) begin
            double_mul_relation = compare_double_mul_exact(
                a_double, b_double, result_double);
            if (double_mul_relation != 2'b00) begin
                exception_flags[0] = 1'b1;
                if (result_double[62:52] == 11'h7ff &&
                    result_double[51:0] == 0)
                    exception_flags[2] = 1'b1;
                if (result_double[62:52] == 0)
                    exception_flags[1] = 1'b1;
                case (rounding_mode)
                    2'b01: begin // toward zero
                        if (a_double[63] ^ b_double[63]) begin
                            if (double_mul_relation == 2'b10)
                                result_double = double_next_up(result_double);
                        end else if (double_mul_relation == 2'b01) begin
                            result_double = double_next_down(result_double);
                        end
                    end
                    2'b10: if (double_mul_relation == 2'b10)
                               result_double = double_next_up(result_double);
                    2'b11: if (double_mul_relation == 2'b01)
                               result_double = double_next_down(result_double);
                    default: begin end
                endcase
            end
        end

        // Arithmetic uses the exact real intermediate and then applies the
        // target-format rounding selected by FCSR.RM. Invalid and divide by
        // zero cases keep their NaN/Inf result and are excluded here.
        if (!fmt_double && !exception_flags[4] && !exception_flags[3] &&
            a[30:23] != 8'hff &&
            ((op == OP_SQRT) || (b[30:23] != 8'hff)) &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_SQRT) || (op == OP_MADD) ||
             (op == OP_MSUB) || (op == OP_NMADD) || (op == OP_NMSUB))) begin
            case (op)
                OP_ADD:   exact_arithmetic = ar_real + br_real;
                OP_SUB:   exact_arithmetic = ar_real - br_real;
                OP_MUL:   exact_arithmetic = ar_real * br_real;
                OP_DIV:   exact_arithmetic = ar_real / br_real;
                OP_SQRT:  exact_arithmetic = $sqrt(ar_real);
                OP_MADD:  exact_arithmetic = (ar_real * br_real) + c_real;
                OP_MSUB:  exact_arithmetic = (ar_real * br_real) - c_real;
                OP_NMADD: exact_arithmetic = -((ar_real * br_real) + c_real);
                default:  exact_arithmetic = -((ar_real * br_real) - c_real);
            endcase
            // A NaN result is an invalid operation (for example 0*Inf) and
            // is intentionally left to the default-NaN path below.
            if (result[30:23] != 8'hff || result[22:0] == 0)
                result = round_single_real(exact_arithmetic, rounding_mode);
        end

        // CVT.S.D has a single-precision destination and obeys FCSR.RM. The
        // host conversion previously forced nearest-even for every mode.
        if (fmt_double && op == OP_CVT_S_D && !a_nan &&
            a_double[62:52] != 11'h7ff)
            result = round_single_real(ar_double, rounding_mode);

        // Compare the rounded single result against a real-precision
        // intermediate for arithmetic operations. This gives deterministic
        // behavioral inexact/underflow classification without depending on
        // simulator host floating-point status flags.
        if (!fmt_double && a[30:23] != 8'hff &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_SQRT) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB))) begin
            case (op)
                OP_ADD:  exact_single = ar_real + br_real;
                OP_SUB:  exact_single = ar_real - br_real;
                OP_MUL:  exact_single = ar_real * br_real;
                OP_DIV:  if (b[30:23] != 0 || b[22:0] != 0) exact_single = ar_real / br_real;
                OP_SQRT: if (!a[31] && a[30:23] != 0)
                             exact_single = rr;
                OP_MADD: exact_single = (ar_real * br_real) + c_real;
                OP_MSUB: exact_single = (ar_real * br_real) - c_real;
                OP_NMADD: exact_single = -((ar_real * br_real) + c_real);
                OP_NMSUB: exact_single = -((ar_real * br_real) - c_real);
                default: exact_single = 0.0;
            endcase
            if (exact_single != 0.0 && result[30:23] == 0)
                exception_flags[1] = 1'b1;
            if (exact_single != 0.0 &&
                ($bitstoshortreal(result) != exact_single))
                exception_flags[0] = 1'b1;
            // For sqrt, compare the rounded result squared with the input.
            // Comparing the result itself with result*result incorrectly
            // marks every non-unit square root as inexact.
            if (op == OP_SQRT && !a[31] && a[30:23] != 0 &&
                (rr * rr) != ar)
                exception_flags[0] = 1'b1;
        end
        // SQRT.D is rounded to the destination double format by result_double;
        // compare its square with the finite positive operand to expose the
        // architectural Inexact condition without host FP status flags.
        if (fmt_double && op == OP_SQRT && !a_nan &&
            !a_double[63] && a_double[62:52] != 11'h7ff &&
            a_double[62:52] != 0) begin
            exact_double = rr_double * rr_double;
            if (exact_double != ar_double)
                exception_flags[0] = 1'b1;
        end
        // CVT.S.D rounds the double operand into the single destination
        // format.  The host shortreal conversion already supplies the
        // rounded result, but its floating-point status flags are not
        // portable across simulators, so classify the architectural flags
        // from the materialized result and the original double value.
        if (fmt_double && op == OP_CVT_S_D && !a_nan &&
            a_double[62:52] != 11'h7ff) begin
            if (result[30:23] == 8'hff && result[22:0] == 0) begin
                exception_flags[2] = 1'b1;
                exception_flags[0] = 1'b1;
            end else if (result[30:23] == 0 &&
                         a_double[62:0] != 0 &&
                         rr != ar_double) begin
                // A nonzero finite double rounded into the single subnormal
                // range, or to zero, is underflow only when information was
                // lost.  An exactly representable single subnormal does not
                // raise Underflow.
                exception_flags[1] = 1'b1;
                exception_flags[0] = 1'b1;
            end else if (rr != ar_double) begin
                exception_flags[0] = 1'b1;
            end
        end
        // Some simulators flush the smallest shortreal subnormals while
        // converting the bit pattern to a host real. Preserve the architectural
        // classification for the common subnormal-times-less-than-one case
        // directly from the IEEE-754 fields.
        if (!fmt_double && op == OP_MUL &&
            ((a[30:23] == 0 && a[22:0] != 0) ||
             (b[30:23] == 0 && b[22:0] != 0)) &&
            ((b[30:23] < 8'h7f) || (a[30:23] < 8'h7f))) begin
            exception_flags[1] = 1'b1;
            exception_flags[0] = 1'b1;
        end
        // The host arithmetic is already rounded to the target format.  An
        // infinity produced from finite operands therefore represents the
        // IEEE overflow condition (division by zero is classified above).
        if (!fmt_double && result[30:23] == 8'hff && result[22:0] == 0 &&
            a[30:23] != 8'hff &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB)) &&
            !(op == OP_DIV && b[30:23] == 0 && b[22:0] == 0)) begin
            exception_flags[2] = 1'b1;
            // IEEE-754 overflow is inexact as well: the finite result
            // crossed the destination format's range and was rounded.
            exception_flags[0] = 1'b1;
        end
        if (fmt_double && result_double[62:52] == 11'h7ff &&
            result_double[51:0] == 0 && a_double[62:52] != 11'h7ff &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB)) &&
            !(op == OP_DIV && b_double[62:52] == 0 &&
              b_double[51:0] == 0)) begin
            exception_flags[2] = 1'b1;
            // Overflow implies inexact for the same reason in the double
            // precision path.
            exception_flags[0] = 1'b1;
        end
        if (double_exact_valid && double_exact_inexact)
            exception_flags[0] = 1'b1;
        // Host real arithmetic reports several IEEE invalid operations as
        // NaN. Operand NaNs were classified above; this covers finite/
        // infinity combinations such as 0*Inf, Inf-Inf and Inf/Inf.
        if (fmt_double && result_double[62:52] == 11'h7ff &&
            result_double[51:0] != 0 && !a_nan && !b_nan &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB))) begin
            exception_flags[4] = 1'b1;
        end
        if (!fmt_double && result[30:23] == 8'hff && result[22:0] != 0 &&
            !a_nan && !b_nan &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB))) begin
            exception_flags[4] = 1'b1;
        end
        // MIPS uses a target-defined default NaN when an arithmetic
        // operation is invalid.  Do not expose simulator/host NaN payloads
        // through the architectural FPR state; QEMU's pre-2008 MIPS mode
        // uses these same default patterns (SNaN bit is one).
        if (fmt_double && exception_flags[4] &&
             ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_SQRT) || (op == OP_MADD) ||
             (op == OP_MSUB) || (op == OP_NMADD) || (op == OP_NMSUB) ||
             (op == OP_RECIP) || (op == OP_RSQRT))) begin
            double_bits_override_valid = 1'b1;
            double_bits_override = 64'h7ff7_ffff_ffff_ffff;
        end
        if (!fmt_double && exception_flags[4] &&
             ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_SQRT) || (op == OP_MADD) ||
             (op == OP_MSUB) || (op == OP_NMADD) || (op == OP_NMSUB) ||
             (op == OP_RECIP) || (op == OP_RSQRT))) begin
            single_bits_override_valid = 1'b1;
            single_bits_override = 32'h7fbf_ffff;
        end
        // A finite non-zero result in the double subnormal range is the
        // underflow boundary for this behavioral contract. Exact cancellation
        // to zero is deliberately excluded.
        if (fmt_double && result_double[62:52] == 0 &&
            result_double[51:0] != 0 &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB))) begin
            exception_flags[1] = 1'b1;
        end
        // Some simulators flush the smallest double subnormal to zero before
        // result_double is materialized. Preserve the architectural boundary
        // classification for a subnormal multiplied by a factor below one
        // directly from the operand fields.
        if (fmt_double && op == OP_MUL &&
            ((a_double[62:52] == 0 && a_double[51:0] != 0) ||
             (b_double[62:52] == 0 && b_double[51:0] != 0)) &&
            ((a_double[62:52] < 11'h3ff) ||
             (b_double[62:52] < 11'h3ff))) begin
            exception_flags[1] = 1'b1;
            exception_flags[0] = 1'b1;
        end
        // If the simulator flushes a result at the normal/subnormal
        // boundary, retain the exact-underflow case from the operand fields.
        // This covers min-normal * 0.5, whose result is the minimum subnormal
        // and therefore raises Underflow without Inexact in this contract.
        if (fmt_double && op == OP_MUL &&
            (((a_double[62:52] == 11'd1) && (a_double[51:0] == 0) &&
              (b_double[62:52] < 11'h3ff)) ||
             ((b_double[62:52] == 11'd1) && (b_double[51:0] == 0) &&
              (a_double[62:52] < 11'h3ff)))) begin
            exception_flags[1] = 1'b1;
        end
        // Apply overrides after all host-result classification has completed.
        // This ordering is required because invalid arithmetic is discovered
        // below the initial result materialization.
        if (single_bits_override_valid)
            result = single_bits_override;
        if (double_bits_override_valid)
            result_double = double_bits_override;
    end
endmodule
