`timescale 1ns/1ps

module tb_mips_fpu_rounding;
    localparam OP_ADD = 5'd0;
    localparam OP_SUB = 5'd1;
    localparam OP_MUL = 5'd2;
    localparam OP_DIV = 5'd3;
    localparam OP_SQRT = 5'd4;
    localparam OP_MADD = 5'd25;
    localparam OP_MSUB = 5'd26;
    localparam OP_NMADD = 5'd27;
    localparam OP_NMSUB = 5'd28;
    localparam OP_RECIP = 5'd23;
    localparam OP_RSQRT = 5'd24;
    localparam OP_CVT_S_D = 5'd15;
    localparam OP_CVT_W_D = 5'd18;
    localparam OP_ROUND_W_D = 5'd19;
    localparam OP_TRUNC_W_D = 5'd20;
    localparam OP_CEIL_W_D = 5'd21;
    localparam OP_FLOOR_W_D = 5'd22;

    reg [4:0] op;
    reg [31:0] a, b, c;
    reg [3:0] compare_condition;
    reg fmt_double;
    reg [1:0] rounding_mode;
    reg flush_subnormals;
    reg [63:0] a_double, b_double, c_double;
    wire [31:0] result;
    wire compare_true;
    wire [63:0] result_double;
    wire [31:0] result_word;
    wire [4:0] exception_flags;
    integer failures;

    mips_fpu dut (
        .op(op), .a(a), .b(b), .result(result),
        .compare_true(compare_true), .compare_condition(compare_condition),
        .fmt_double(fmt_double), .rounding_mode(rounding_mode),
        .flush_subnormals(flush_subnormals),
        .a_double(a_double), .b_double(b_double), .c(c),
        .c_double(c_double), .result_double(result_double),
        .result_word(result_word), .exception_flags(exception_flags)
    );

    task automatic check_single_add;
        input [1:0] mode;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        input [127:0] name;
        begin
            op = OP_ADD;
            a = lhs;
            b = rhs;
            c = 32'd0;
            fmt_double = 1'b0;
            rounding_mode = mode;
            a_double = 64'd0;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_ROUND_FAIL %0s got=%08h flags=%02h expected=%08h",
                         name, result, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_single_addsub;
        input [4:0] arithmetic_op;
        input [1:0] mode;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        input [4:0] expected_flags;
        input [127:0] name;
        begin
            op = arithmetic_op;
            a = lhs;
            b = rhs;
            c = 32'd0;
            fmt_double = 1'b0;
            rounding_mode = mode;
            a_double = 64'd0;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result !== expected || exception_flags !== expected_flags) begin
                $display("FPU_ADDSUB_EXACT_FAIL %0s got=%08h flags=%02h expected=%08h flags=%02h",
                         name, result, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_single_unary_round;
        input [4:0] unary_op;
        input [1:0] mode;
        input [31:0] operand;
        input [31:0] expected;
        input [4:0] expected_flags;
        input [127:0] name;
        begin
            op = unary_op;
            a = operand;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b0;
            rounding_mode = mode;
            a_double = 64'd0;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result !== expected || exception_flags !== expected_flags) begin
                $display("FPU_UNARY_ROUND_FAIL %0s got=%08h flags=%02h expected=%08h flags=%02h",
                         name, result, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_single_fma;
        input [4:0] fma_op;
        input [1:0] mode;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] addend;
        input [31:0] expected;
        input [4:0] expected_flags;
        input [127:0] name;
        begin
            op = fma_op;
            a = lhs;
            b = rhs;
            c = addend;
            fmt_double = 1'b0;
            rounding_mode = mode;
            a_double = 64'd0;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result !== expected || exception_flags !== expected_flags) begin
                $display("FPU_SINGLE_FMA_EXACT_FAIL %0s got=%08h flags=%02h expected=%08h flags=%02h",
                         name, result, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_cvt_s_d;
        input [1:0] mode;
        input [63:0] value;
        input [31:0] expected;
        input [127:0] name;
        begin
            op = OP_CVT_S_D;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = value;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_CVT_ROUND_FAIL %0s got=%08h flags=%02h expected=%08h",
                         name, result, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_cvt_w_d;
        input [4:0] conversion_op;
        input [1:0] mode;
        input [63:0] value;
        input [31:0] expected;
        input [4:0] expected_flags;
        input [127:0] name;
        begin
            op = conversion_op;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = value;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result_word !== expected || exception_flags !== expected_flags) begin
                $display("FPU_CVT_WORD_FAIL %0s got=%08h flags=%02h expected=%08h flags=%02h",
                         name, result_word, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_add;
        input [1:0] mode;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = OP_ADD;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = lhs;
            b_double = rhs;
            c_double = 64'd0;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_sub;
        input [1:0] mode;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = OP_SUB;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = lhs;
            b_double = rhs;
            c_double = 64'd0;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_SUB_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_mul;
        input [1:0] mode;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = OP_MUL;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = lhs;
            b_double = rhs;
            c_double = 64'd0;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_MUL_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_div;
        input [1:0] mode;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = OP_DIV;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = lhs;
            b_double = rhs;
            c_double = 64'd0;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_DIV_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_sqrt;
        input [1:0] mode;
        input [63:0] value;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = OP_SQRT;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = value;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_SQRT_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_fma;
        input [4:0] fma_op;
        input [1:0] mode;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] addend;
        input [63:0] expected;
        input [127:0] name;
        begin
            op = fma_op;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = lhs;
            b_double = rhs;
            c_double = addend;
            #1;
            if (result_double !== expected || exception_flags[0] !== 1'b1) begin
                $display("FPU_DOUBLE_FMA_ROUND_FAIL %0s got=%016h flags=%02h expected=%016h",
                         name, result_double, exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_fma_special;
        input [4:0] fma_op;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] addend;
        input [63:0] expected;
        input [4:0] expected_flags;
        input [127:0] name;
        begin
            op = fma_op;
            fmt_double = 1'b1;
            rounding_mode = 2'b00;
            a_double = lhs;
            b_double = rhs;
            c_double = addend;
            #1;
            if (result_double !== expected || exception_flags !== expected_flags) begin
                $display("FPU_DOUBLE_FMA_SPECIAL_FAIL %0s got=%016h flags=%02h expected=%016h flags=%02h",
                         name, result_double, exception_flags, expected,
                         expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        flush_subnormals = 1'b0;
        compare_condition = 4'd0;

        // 1.0 + 2^-24 is exactly halfway between two single values.
        check_single_add(2'b00, 32'h3f800000, 32'h33800000,
                         32'h3f800000, "add_pos_nearest_even");
        check_single_add(2'b01, 32'h3f800000, 32'h33800000,
                         32'h3f800000, "add_pos_toward_zero");
        check_single_add(2'b10, 32'h3f800000, 32'h33800000,
                         32'h3f800001, "add_pos_toward_plus_inf");
        check_single_add(2'b11, 32'h3f800000, 32'h33800000,
                         32'h3f800000, "add_pos_toward_minus_inf");

        // The negative case exercises the opposite ULP direction.
        check_single_add(2'b00, 32'hbf800000, 32'hb3800000,
                         32'hbf800000, "add_neg_nearest_even");
        check_single_add(2'b01, 32'hbf800000, 32'hb3800000,
                         32'hbf800000, "add_neg_toward_zero");
        check_single_add(2'b10, 32'hbf800000, 32'hb3800000,
                         32'hbf800000, "add_neg_toward_plus_inf");
        check_single_add(2'b11, 32'hbf800000, 32'hb3800000,
                         32'hbf800001, "add_neg_toward_minus_inf");

        // A subnormal operand far below the host-real precision still affects
        // directed rounding and must set Inexact.  1.0 + min-subnormal is
        // greater than 1.0, even though a binary64 host real cannot retain the
        // added bit at this exponent distance.
        check_single_add(2'b00, 32'h3f800000, 32'h00000001,
                         32'h3f800000, "add_tiny_pos_nearest_even");
        check_single_add(2'b01, 32'h3f800000, 32'h00000001,
                         32'h3f800000, "add_tiny_pos_toward_zero");
        check_single_add(2'b10, 32'h3f800000, 32'h00000001,
                         32'h3f800001, "add_tiny_pos_toward_plus_inf");
        check_single_add(2'b11, 32'h3f800000, 32'h00000001,
                         32'h3f800000, "add_tiny_pos_toward_minus_inf");

        // Subtracting a tiny positive value moves 1.0 toward its predecessor.
        check_single_addsub(OP_SUB, 2'b00, 32'h3f800000, 32'h00000001,
                            32'h3f800000, 5'b00001, "sub_tiny_pos_nearest");
        check_single_addsub(OP_SUB, 2'b01, 32'h3f800000, 32'h00000001,
                            32'h3f7fffff, 5'b00001, "sub_tiny_pos_zero");
        check_single_addsub(OP_SUB, 2'b10, 32'h3f800000, 32'h00000001,
                            32'h3f800000, 5'b00001, "sub_tiny_pos_plus_inf");
        check_single_addsub(OP_SUB, 2'b11, 32'h3f800000, 32'h00000001,
                            32'h3f7fffff, 5'b00001, "sub_tiny_pos_minus_inf");

        // -1.0 - (-min-subnormal) moves toward zero. This checks subtraction's
        // RHS sign inversion together with negative directed-rounding order.
        check_single_addsub(OP_SUB, 2'b00, 32'hbf800000, 32'h80000001,
                            32'hbf800000, 5'b00001, "sub_tiny_neg_nearest");
        check_single_addsub(OP_SUB, 2'b01, 32'hbf800000, 32'h80000001,
                            32'hbf7fffff, 5'b00001, "sub_tiny_neg_zero");
        check_single_addsub(OP_SUB, 2'b10, 32'hbf800000, 32'h80000001,
                            32'hbf7fffff, 5'b00001, "sub_tiny_neg_plus_inf");
        check_single_addsub(OP_SUB, 2'b11, 32'hbf800000, 32'h80000001,
                            32'hbf800000, 5'b00001, "sub_tiny_neg_minus_inf");

        // Finite operands can overflow on ADD. Directed modes that round
        // inward return max-finite while still setting Overflow and Inexact.
        check_single_addsub(OP_ADD, 2'b00, 32'h7f7fffff, 32'h7f7fffff,
                            32'h7f800000, 5'b00101, "add_pos_overflow_nearest");
        check_single_addsub(OP_ADD, 2'b01, 32'h7f7fffff, 32'h7f7fffff,
                            32'h7f7fffff, 5'b00101, "add_pos_overflow_zero");
        check_single_addsub(OP_ADD, 2'b10, 32'h7f7fffff, 32'h7f7fffff,
                            32'h7f800000, 5'b00101, "add_pos_overflow_plus_inf");
        check_single_addsub(OP_ADD, 2'b11, 32'h7f7fffff, 32'h7f7fffff,
                            32'h7f7fffff, 5'b00101, "add_pos_overflow_minus_inf");
        check_single_addsub(OP_ADD, 2'b00, 32'hff7fffff, 32'hff7fffff,
                            32'hff800000, 5'b00101, "add_neg_overflow_nearest");
        check_single_addsub(OP_ADD, 2'b01, 32'hff7fffff, 32'hff7fffff,
                            32'hff7fffff, 5'b00101, "add_neg_overflow_zero");
        check_single_addsub(OP_ADD, 2'b10, 32'hff7fffff, 32'hff7fffff,
                            32'hff7fffff, 5'b00101, "add_neg_overflow_plus_inf");
        check_single_addsub(OP_ADD, 2'b11, 32'hff7fffff, 32'hff7fffff,
                            32'hff800000, 5'b00101, "add_neg_overflow_minus_inf");

        // Reciprocal and reciprocal-square-root are rounded at the single
        // destination boundary.  1/3 and 1/sqrt(2) are inexact, so all four
        // modes must retain Inexact while selecting the proper adjacent ULP.
        check_single_unary_round(OP_RECIP, 2'b00, 32'h40400000,
                                 32'h3eaaaaab, 5'b00001,
                                 "recip_three_nearest_even");
        check_single_unary_round(OP_RECIP, 2'b01, 32'h40400000,
                                 32'h3eaaaaaa, 5'b00001,
                                 "recip_three_toward_zero");
        check_single_unary_round(OP_RECIP, 2'b10, 32'h40400000,
                                 32'h3eaaaaab, 5'b00001,
                                 "recip_three_toward_plus_inf");
        check_single_unary_round(OP_RECIP, 2'b11, 32'h40400000,
                                 32'h3eaaaaaa, 5'b00001,
                                 "recip_three_toward_minus_inf");
        // Negative reciprocal uses the opposite adjacent-ULP direction for
        // the directed modes; this also guards the signed RECIP path.
        check_single_unary_round(OP_RECIP, 2'b00, 32'hc0400000,
                                 32'hbeaaaaab, 5'b00001,
                                 "recip_neg_three_nearest_even");
        check_single_unary_round(OP_RECIP, 2'b01, 32'hc0400000,
                                 32'hbeaaaaaa, 5'b00001,
                                 "recip_neg_three_toward_zero");
        check_single_unary_round(OP_RECIP, 2'b10, 32'hc0400000,
                                 32'hbeaaaaaa, 5'b00001,
                                 "recip_neg_three_toward_plus_inf");
        check_single_unary_round(OP_RECIP, 2'b11, 32'hc0400000,
                                 32'hbeaaaaab, 5'b00001,
                                 "recip_neg_three_toward_minus_inf");
        check_single_unary_round(OP_RSQRT, 2'b00, 32'h40000000,
                                 32'h3f3504f3, 5'b00001,
                                 "rsqrt_two_nearest_even");
        check_single_unary_round(OP_RSQRT, 2'b01, 32'h40000000,
                                 32'h3f3504f3, 5'b00001,
                                 "rsqrt_two_toward_zero");
        check_single_unary_round(OP_RSQRT, 2'b10, 32'h40000000,
                                 32'h3f3504f4, 5'b00001,
                                 "rsqrt_two_toward_plus_inf");
        check_single_unary_round(OP_RSQRT, 2'b11, 32'h40000000,
                                 32'h3f3504f3, 5'b00001,
                                 "rsqrt_two_toward_minus_inf");

        // The exact product is 1.0, but the minimum-subnormal accumulator is
        // below host-real precision. Cover all fused opcode sign variants and
        // directed modes.
        check_single_fma(OP_MADD, 2'b00, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'h3f800000, 5'b00001,
                         "madd_tiny_nearest");
        check_single_fma(OP_MADD, 2'b01, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'h3f800000, 5'b00001,
                         "madd_tiny_zero");
        check_single_fma(OP_MADD, 2'b10, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'h3f800001, 5'b00001,
                         "madd_tiny_plus_inf");
        check_single_fma(OP_MADD, 2'b11, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'h3f800000, 5'b00001,
                         "madd_tiny_minus_inf");
        check_single_fma(OP_MSUB, 2'b00, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'h3f800000, 5'b00001,
                         "msub_tiny_nearest");
        check_single_fma(OP_MSUB, 2'b01, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'h3f800000, 5'b00001,
                         "msub_tiny_zero");
        check_single_fma(OP_MSUB, 2'b10, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'h3f800001, 5'b00001,
                         "msub_tiny_plus_inf");
        check_single_fma(OP_MSUB, 2'b11, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'h3f800000, 5'b00001,
                         "msub_tiny_minus_inf");
        check_single_fma(OP_NMADD, 2'b00, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'hbf800000, 5'b00001,
                         "nmadd_tiny_nearest");
        check_single_fma(OP_NMADD, 2'b01, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'hbf800000, 5'b00001,
                         "nmadd_tiny_zero");
        check_single_fma(OP_NMADD, 2'b10, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'hbf800000, 5'b00001,
                         "nmadd_tiny_plus_inf");
        check_single_fma(OP_NMADD, 2'b11, 32'h3f800000, 32'h3f800000,
                         32'h00000001, 32'hbf800001, 5'b00001,
                         "nmadd_tiny_minus_inf");
        check_single_fma(OP_NMSUB, 2'b00, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'hbf800000, 5'b00001,
                         "nmsub_tiny_nearest");
        check_single_fma(OP_NMSUB, 2'b01, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'hbf800000, 5'b00001,
                         "nmsub_tiny_zero");
        check_single_fma(OP_NMSUB, 2'b10, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'hbf800000, 5'b00001,
                         "nmsub_tiny_plus_inf");
        check_single_fma(OP_NMSUB, 2'b11, 32'h3f800000, 32'h3f800000,
                         32'h80000001, 32'hbf800001, 5'b00001,
                         "nmsub_tiny_minus_inf");

        // Fused finite products report Overflow|Inexact even when a directed
        // mode returns the largest finite value instead of infinity.
        check_single_fma(OP_MADD, 2'b00, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'h7f800000, 5'b00101,
                         "madd_overflow_nearest");
        check_single_fma(OP_MADD, 2'b01, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'h7f7fffff, 5'b00101,
                         "madd_overflow_zero");
        check_single_fma(OP_MADD, 2'b10, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'h7f800000, 5'b00101,
                         "madd_overflow_plus_inf");
        check_single_fma(OP_MADD, 2'b11, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'h7f7fffff, 5'b00101,
                         "madd_overflow_minus_inf");
        check_single_fma(OP_NMADD, 2'b00, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'hff800000, 5'b00101,
                         "nmadd_overflow_nearest");
        check_single_fma(OP_NMADD, 2'b01, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'hff7fffff, 5'b00101,
                         "nmadd_overflow_zero");
        check_single_fma(OP_NMADD, 2'b10, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'hff7fffff, 5'b00101,
                         "nmadd_overflow_plus_inf");
        check_single_fma(OP_NMADD, 2'b11, 32'h7f7fffff, 32'h40000000,
                         32'h00000000, 32'hff800000, 5'b00101,
                         "nmadd_overflow_minus_inf");

        // A double value just above the single midpoint must follow RM when
        // converted to the single destination format.
        check_cvt_s_d(2'b00, 64'h3ff0000010000001,
                      32'h3f800001, "cvt_pos_nearest_even");
        check_cvt_s_d(2'b01, 64'h3ff0000010000001,
                      32'h3f800000, "cvt_pos_toward_zero");
        check_cvt_s_d(2'b10, 64'h3ff0000010000001,
                      32'h3f800001, "cvt_pos_toward_plus_inf");
        check_cvt_s_d(2'b11, 64'h3ff0000010000001,
                      32'h3f800000, "cvt_pos_toward_minus_inf");
        check_cvt_s_d(2'b00, 64'hbff0000010000001,
                      32'hbf800001, "cvt_neg_nearest_even");
        check_cvt_s_d(2'b01, 64'hbff0000010000001,
                      32'hbf800000, "cvt_neg_toward_zero");
        check_cvt_s_d(2'b10, 64'hbff0000010000001,
                      32'hbf800000, "cvt_neg_toward_plus_inf");
        check_cvt_s_d(2'b11, 64'hbff0000010000001,
                      32'hbf800001, "cvt_neg_toward_minus_inf");

        check_cvt_w_d(OP_CVT_W_D, 2'b11, 64'hbff4000000000000,
                      32'hfffffffe, 5'b00001, "cvt_w_d_neg_toward_minus_inf");

        // Conversion range is defined after rounding.  The exact halfway
        // value above INT_MAX rounds to 2^31 for nearest-even and nearest-away
        // but remains representable under toward-zero and toward -Inf.
        check_cvt_w_d(OP_CVT_W_D, 2'b00, 64'h41dfffffffe00000,
                      32'h80000000, 5'b10000, "cvt_w_d_pos_half_nearest_invalid");
        check_cvt_w_d(OP_CVT_W_D, 2'b01, 64'h41dfffffffe00000,
                      32'h7fffffff, 5'b00001, "cvt_w_d_pos_half_zero_valid");
        check_cvt_w_d(OP_CVT_W_D, 2'b10, 64'h41dfffffffe00000,
                      32'h80000000, 5'b10000, "cvt_w_d_pos_half_plus_invalid");
        check_cvt_w_d(OP_CVT_W_D, 2'b11, 64'h41dfffffffe00000,
                      32'h7fffffff, 5'b00001, "cvt_w_d_pos_half_minus_valid");
        check_cvt_w_d(OP_ROUND_W_D, 2'b00, 64'h41dfffffffe00000,
                      32'h80000000, 5'b10000, "round_w_d_pos_half_invalid");
        check_cvt_w_d(OP_CVT_W_D, 2'b00, 64'hc1e0000000100000,
                      32'h80000000, 5'b00001, "cvt_w_d_neg_half_nearest_valid");
        check_cvt_w_d(OP_TRUNC_W_D, 2'b00, 64'hc1e0000000100000,
                      32'h80000000, 5'b00001, "trunc_w_d_neg_half_valid");
        check_cvt_w_d(OP_CEIL_W_D, 2'b00, 64'hc1e0000000100000,
                      32'h80000000, 5'b00001, "ceil_w_d_neg_half_valid");
        check_cvt_w_d(OP_FLOOR_W_D, 2'b00, 64'hc1e0000000100000,
                      32'h80000000, 5'b10000, "floor_w_d_neg_half_invalid");

        // Binary64 halfway cases must retain the low operand bit that a host
        // real intermediate cannot represent.  1.0 +/- 2^-53 is exactly
        // halfway between adjacent binary64 values.
        check_double_add(2'b00, 64'h3ff0000000000000,
                         64'h3ca0000000000000,
                         64'h3ff0000000000000, "add_d_pos_nearest_even");
        check_double_add(2'b01, 64'h3ff0000000000000,
                         64'h3ca0000000000000,
                         64'h3ff0000000000000, "add_d_pos_toward_zero");
        check_double_add(2'b10, 64'h3ff0000000000000,
                         64'h3ca0000000000000,
                         64'h3ff0000000000001, "add_d_pos_toward_plus_inf");
        check_double_add(2'b11, 64'h3ff0000000000000,
                         64'h3ca0000000000000,
                         64'h3ff0000000000000, "add_d_pos_toward_minus_inf");
        check_double_add(2'b11, 64'hbff0000000000000,
                         64'hbca0000000000000,
                         64'hbff0000000000001, "add_d_neg_toward_minus_inf");
        check_double_sub(2'b11, 64'h3ff0000000000000,
                         64'h3c90000000000000,
                         64'h3fefffffffffffff, "sub_d_pos_toward_minus_inf");
        check_double_mul(2'b00, 64'h3ff0000000000001,
                         64'h3ff0000000000001,
                         64'h3ff0000000000002, "mul_d_nearest_even");
        check_double_mul(2'b01, 64'h3ff0000000000001,
                         64'h3ff0000000000001,
                         64'h3ff0000000000002, "mul_d_toward_zero");
        check_double_mul(2'b10, 64'h3ff0000000000001,
                         64'h3ff0000000000001,
                         64'h3ff0000000000003, "mul_d_toward_plus_inf");
        check_double_mul(2'b11, 64'h3ff0000000000001,
                         64'h3ff0000000000001,
                         64'h3ff0000000000002, "mul_d_toward_minus_inf");
        check_double_div(2'b00, 64'h3ff0000000000000,
                         64'h4008000000000000,
                         64'h3fd5555555555555, "div_d_nearest");
        check_double_div(2'b01, 64'h3ff0000000000000,
                         64'h4008000000000000,
                         64'h3fd5555555555555, "div_d_toward_zero");
        check_double_div(2'b10, 64'h3ff0000000000000,
                         64'h4008000000000000,
                         64'h3fd5555555555556, "div_d_toward_plus_inf");
        check_double_div(2'b11, 64'h3ff0000000000000,
                         64'h4008000000000000,
                         64'h3fd5555555555555, "div_d_toward_minus_inf");
        check_double_sqrt(2'b00, 64'h4000000000000000,
                          64'h3ff6a09e667f3bcd, "sqrt_d_nearest");
        check_double_sqrt(2'b01, 64'h4000000000000000,
                          64'h3ff6a09e667f3bcc, "sqrt_d_toward_zero");
        check_double_sqrt(2'b10, 64'h4000000000000000,
                          64'h3ff6a09e667f3bcd, "sqrt_d_toward_plus_inf");
        check_double_sqrt(2'b11, 64'h4000000000000000,
                          64'h3ff6a09e667f3bcc, "sqrt_d_toward_minus_inf");
        check_double_fma(OP_MADD, 2'b10, 64'h3ff0000000000000,
                         64'h3ff0000000000000, 64'h3ca0000000000000,
                         64'h3ff0000000000001, "madd_d_toward_plus_inf");
        check_double_fma(OP_MSUB, 2'b11, 64'h3ff0000000000000,
                         64'h3ff0000000000000, 64'h3c90000000000000,
                         64'h3fefffffffffffff, "msub_d_toward_minus_inf");
        check_double_fma(OP_NMADD, 2'b11, 64'h3ff0000000000000,
                         64'h3ff0000000000000, 64'h3ca0000000000000,
                         64'hbff0000000000001, "nmadd_d_toward_minus_inf");
        check_double_fma(OP_NMSUB, 2'b10, 64'h3ff0000000000000,
                         64'h3ff0000000000000, 64'h3c90000000000000,
                         64'hbfefffffffffffff, "nmsub_d_toward_plus_inf");
        check_double_fma_special(OP_MADD,
                                 64'h0000000000000000,
                                 64'h7ff0000000000000,
                                 64'h3ff0000000000000,
                                 64'h7ff7ffffffffffff,
                                 5'b10000, "madd_d_zero_inf_invalid");
        check_double_fma_special(OP_MADD,
                                 64'h7ff0000000000000,
                                 64'h4000000000000000,
                                 64'hfff0000000000000,
                                 64'h7ff7ffffffffffff,
                                 5'b10000, "madd_d_inf_opposite_inf_invalid");
        check_double_fma_special(OP_MADD,
                                 64'h7ff0000000000000,
                                 64'h4000000000000000,
                                 64'h3ff0000000000000,
                                 64'h7ff0000000000000,
                                 5'b00000, "madd_d_inf_propagates");
        check_double_fma_special(OP_NMADD,
                                 64'h7ff0000000000000,
                                 64'h4000000000000000,
                                 64'h3ff0000000000000,
                                 64'hfff0000000000000,
                                 5'b00000, "nmadd_d_inf_sign");
        check_double_fma_special(OP_MADD,
                                 64'h3ff0000000000000,
                                 64'h3ff0000000000000,
                                 64'h7ff8000000000001,
                                 64'h7ff7ffffffffffff,
                                 5'b10000, "madd_d_c_nan_invalid");

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_fpu_rounding arithmetic=28 single_fma=24 cvt_s_d=8 double_add_sub=6 double_mul=4 double_div_sqrt=8 double_fma=4 double_fma_special=5");
        else
            $display("REGRESSION_TEST_FAIL mips_fpu_rounding failures=%0d", failures);
        $finish;
    end
endmodule
