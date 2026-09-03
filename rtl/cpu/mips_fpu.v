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
    shortreal ar, br, rr;
    real ar_double, br_double, cr_double, rr_double, exact_single,
         exact_double;
    reg a_nan, b_nan, a_snan, b_snan, unordered;
    reg single_bits_override_valid, double_bits_override_valid;
    reg [31:0] single_bits_override;
    reg [63:0] double_bits_override;
    always @(*) begin
        ar = $bitstoshortreal(a);
        br = $bitstoshortreal(b);
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
        exact_double = 0.0;
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
        // Compare the rounded single result against a real-precision
        // intermediate for arithmetic operations. This gives deterministic
        // behavioral inexact/underflow classification without depending on
        // simulator host floating-point status flags.
        if (!fmt_double && a[30:23] != 8'hff &&
            ((op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) ||
             (op == OP_DIV) || (op == OP_SQRT) || (op == OP_MADD) || (op == OP_MSUB) ||
             (op == OP_NMADD) || (op == OP_NMSUB))) begin
            case (op)
                OP_ADD:  exact_single = ar + br;
                OP_SUB:  exact_single = ar - br;
                OP_MUL:  exact_single = ar * br;
                OP_DIV:  if (b[30:23] != 0 || b[22:0] != 0) exact_single = ar / br;
                OP_SQRT: if (!a[31] && a[30:23] != 0)
                             exact_single = rr;
                OP_MADD: exact_single = (ar * br) + $bitstoshortreal(c);
                OP_MSUB: exact_single = (ar * br) - $bitstoshortreal(c);
                OP_NMADD: exact_single = -((ar * br) + $bitstoshortreal(c));
                OP_NMSUB: exact_single = -((ar * br) - $bitstoshortreal(c));
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
