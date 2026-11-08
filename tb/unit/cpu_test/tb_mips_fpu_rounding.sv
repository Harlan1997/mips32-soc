`timescale 1ns/1ps

module tb_mips_fpu_rounding;
    localparam OP_ADD = 5'd0;
    localparam OP_SUB = 5'd1;
    localparam OP_MUL = 5'd2;
    localparam OP_CVT_S_D = 5'd15;
    localparam OP_CVT_W_D = 5'd18;

    reg [4:0] op;
    reg [31:0] a, b, c;
    reg [3:0] compare_condition;
    reg fmt_double;
    reg [1:0] rounding_mode;
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
        input [1:0] mode;
        input [63:0] value;
        input [31:0] expected;
        input [127:0] name;
        begin
            op = OP_CVT_W_D;
            a = 32'd0;
            b = 32'd0;
            c = 32'd0;
            fmt_double = 1'b1;
            rounding_mode = mode;
            a_double = value;
            b_double = 64'd0;
            c_double = 64'd0;
            #1;
            if (result_word !== expected) begin
                $display("FPU_CVT_WORD_FAIL %0s got=%08h expected=%08h",
                         name, result_word, expected);
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

    initial begin
        failures = 0;
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

        check_cvt_w_d(2'b11, 64'hbff4000000000000,
                      32'hfffffffe, "cvt_w_d_neg_toward_minus_inf");

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

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_fpu_rounding arithmetic=8 cvt_s_d=8 double_add_sub=6 double_mul=4");
        else
            $display("REGRESSION_TEST_FAIL mips_fpu_rounding failures=%0d", failures);
        $finish;
    end
endmodule
