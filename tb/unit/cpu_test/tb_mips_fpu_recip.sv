`timescale 1ns/1ps

module tb_mips_fpu_recip;
    reg [4:0] op;
    reg [31:0] a, b, c;
    reg fmt_double;
    reg [1:0] rounding_mode;
    reg [63:0] a_double, b_double, c_double;
    wire [31:0] result;
    wire [63:0] result_double;
    wire [31:0] result_word;
    wire compare_true;
    wire [4:0] exception_flags;
    integer failures;

    mips_fpu dut (
        .op(op), .a(a), .b(b), .result(result), .compare_true(compare_true),
        .compare_condition(4'd0), .fmt_double(fmt_double),
        .rounding_mode(rounding_mode),
        .a_double(a_double), .b_double(b_double), .c(c), .c_double(c_double),
        .result_double(result_double), .result_word(result_word),
        .exception_flags(exception_flags)
    );

    task automatic check_single;
        input [4:0] want_op;
        input [31:0] value;
        input [31:0] expected;
        begin
            op = want_op; a = value; b = 32'd0; c = 32'd0; fmt_double = 1'b0; #1;
            if (result !== expected) begin
                $display("FAIL single op=%0d got=%08h want=%08h", want_op, result, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_single_flags;
        input [4:0] want_op;
        input [31:0] value;
        input [31:0] expected;
        input [4:0] expected_flags;
        begin
            op = want_op; a = value; b = 32'd0; c = 32'd0;
            fmt_double = 1'b0; #1;
            if (result !== expected || exception_flags !== expected_flags) begin
                $display("FAIL single boundary op=%0d got=%08h flags=%02h want=%08h flags=%02h",
                         want_op, result, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double;
        input [4:0] want_op;
        input [63:0] value;
        input [63:0] expected;
        begin
            op = want_op; a_double = value; b_double = 64'd0; c_double = 64'd0; fmt_double = 1'b1; #1;
            if (result_double !== expected) begin
                $display("FAIL double op=%0d got=%016h want=%016h", want_op, result_double, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_double_flags;
        input [4:0] want_op;
        input [63:0] value;
        input [63:0] expected;
        input [4:0] expected_flags;
        begin
            op = want_op; a_double = value; b_double = 64'd0;
            c_double = 64'd0; fmt_double = 1'b1; #1;
            if (result_double !== expected || exception_flags !== expected_flags) begin
                $display("FAIL double boundary op=%0d got=%016h flags=%02h want=%016h flags=%02h",
                         want_op, result_double, exception_flags, expected, expected_flags);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        rounding_mode = 2'b00;
        check_single(5'd23, 32'h40800000, 32'h3e800000);
        check_single(5'd24, 32'h40800000, 32'h3f000000);
        // Zero reciprocal/rsqrt returns signed infinity and raises Div0.
        check_single_flags(5'd23, 32'h00000000, 32'h7f800000, 5'b01000);
        check_single_flags(5'd24, 32'h80000000, 32'hff800000, 5'b01000);
        check_single_flags(5'd23, 32'h7f800000, 32'h00000000, 5'b00000);
        check_single_flags(5'd24, 32'h7f800000, 32'h00000000, 5'b00000);
        check_single_flags(5'd24, 32'hbf800000, 32'h7fbfffff, 5'b10000);
        check_double(5'd23, 64'h4010000000000000, 64'h3fd0000000000000);
        check_double(5'd24, 64'h4010000000000000, 64'h3fe0000000000000);
        check_double_flags(5'd23, 64'h0000000000000000,
                           64'h7ff0000000000000, 5'b01000);
        check_double_flags(5'd24, 64'h8000000000000000,
                           64'hfff0000000000000, 5'b01000);
        check_double_flags(5'd23, 64'h7ff0000000000000,
                           64'h0000000000000000, 5'b00000);
        check_double_flags(5'd24, 64'h7ff0000000000000,
                           64'h0000000000000000, 5'b00000);
        check_double_flags(5'd24, 64'hbff0000000000000,
                           64'h7ff7ffffffffffff, 5'b10000);
        // a*b +/- c using exact binary vectors: 2*3 +/- 1.
        op = 5'd25; a = 32'h40000000; b = 32'h40400000;
        c = 32'h3f800000; fmt_double = 1'b0; #1;
        if (result !== 32'h40e00000) failures = failures + 1;
        op = 5'd26; #1;
        if (result !== 32'h40a00000) failures = failures + 1;
        op = 5'd27; #1;
        if (result !== 32'hc0e00000) failures = failures + 1;
        op = 5'd28; #1;
        if (result !== 32'hc0a00000) failures = failures + 1;
        op = 5'd25; a_double = 64'h4000000000000000;
        b_double = 64'h4008000000000000; c_double = 64'h3ff0000000000000;
        fmt_double = 1'b1; #1;
        if (result_double !== 64'h401c000000000000) failures = failures + 1;
        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_fpu_recip finite=4");
        else
            $display("REGRESSION_TEST_FAIL mips_fpu_recip failures=%0d", failures);
        $finish;
    end
endmodule
