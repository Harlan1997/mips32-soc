`timescale 1ns/1ps

module tb_mips_fpu_compare;
    reg [3:0] op;
    reg [3:0] condition;
    reg [31:0] a, b;
    reg fmt_double;
    reg [1:0] rounding_mode;
    reg [63:0] a_double, b_double;
    wire [31:0] result;
    wire compare_true;
    wire [63:0] result_double;
    wire [31:0] result_word;
    wire [4:0] exception_flags;
    integer failures;
    integer i;

    mips_fpu dut (
        .op(op), .a(a), .b(b), .result(result),
        .compare_true(compare_true), .compare_condition(condition),
        .fmt_double(fmt_double), .rounding_mode(rounding_mode),
        .a_double(a_double), .b_double(b_double),
        .result_double(result_double), .result_word(result_word),
        .exception_flags(exception_flags)
    );

    task automatic check_vector;
        input [31:0] lhs;
        input [31:0] rhs;
        input [15:0] expected;
        input want_invalid;
        begin
            a = lhs;
            b = rhs;
            fmt_double = 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                condition = i[3:0];
                #1;
                if (compare_true !== expected[i]) begin
                    $display("FAIL compare a=%08h b=%08h cond=%0d got=%b want=%b",
                             lhs, rhs, i, compare_true, expected[i]);
                    failures = failures + 1;
                end
                if (exception_flags[4] !== want_invalid) begin
                    $display("FAIL invalid a=%08h b=%08h cond=%0d got=%b want=%b",
                             lhs, rhs, i, exception_flags[4], want_invalid);
                    failures = failures + 1;
                end
            end
        end
    endtask

    task automatic check_double_vector;
        input [63:0] lhs;
        input [63:0] rhs;
        input [15:0] expected;
        input want_invalid;
        begin
            a_double = lhs;
            b_double = rhs;
            fmt_double = 1'b1;
            for (i = 0; i < 16; i = i + 1) begin
                condition = i[3:0];
                #1;
                if (compare_true !== expected[i]) begin
                    $display("FAIL double compare a=%016h b=%016h cond=%0d got=%b want=%b",
                             lhs, rhs, i, compare_true, expected[i]);
                    failures = failures + 1;
                end
                if (exception_flags[4] !== want_invalid) begin
                    $display("FAIL double invalid a=%016h b=%016h cond=%0d got=%b want=%b",
                             lhs, rhs, i, exception_flags[4], want_invalid);
                    failures = failures + 1;
                end
            end
        end
    endtask

    initial begin
        failures = 0;
        rounding_mode = 2'b00;
        op = 4'h8;
        // 1.0 < 2.0: ordered less predicates and their unordered-inclusive
        // counterparts are true; equality and unordered-only predicates false.
        check_vector(32'h3f800000, 32'h40000000,
                     16'b1111000011110000, 1'b0);
        // Equal finite operands.
        check_vector(32'h3f800000, 32'h3f800000,
                     16'b1100110011001100, 1'b0);
        // Quiet NaN: only unordered-inclusive predicates are true. The
        // behavioral primitive reports the existing sticky invalid flag.
        check_vector(32'h7fc00001, 32'h3f800000,
                     16'b1010101010101010, 1'b1);

        check_double_vector(64'h3ff0000000000000, 64'h4000000000000000,
                            16'b1111000011110000, 1'b0);
        check_double_vector(64'h3ff0000000000000, 64'h3ff0000000000000,
                            16'b1100110011001100, 1'b0);
        check_double_vector(64'h7ff8000000000001, 64'h3ff0000000000000,
                            16'b1010101010101010, 1'b1);

        // MIPS32 W/S conversion and rounding primitives.
        fmt_double = 1'b0;
        op = 4'd9; a = 32'd3; #1;
        if (result !== 32'h40400000) begin
            $display("FAIL cvt.s.w got=%08h want=40400000", result);
            failures = failures + 1;
        end
        op = 4'd10; a = 32'h40600000; #1;
        if (result_word !== 32'd4) begin
            $display("FAIL cvt.w.s got=%08h want=00000004", result_word);
            failures = failures + 1;
        end
        op = 4'd11; #1;
        if (result_word !== 32'd4) begin
            $display("FAIL round.w.s got=%08h want=00000004", result_word);
            failures = failures + 1;
        end
        op = 4'd12; #1;
        if (result_word !== 32'd3) begin
            $display("FAIL trunc.w.s got=%08h want=00000003", result_word);
            failures = failures + 1;
        end
        op = 4'd13; #1;
        if (result_word !== 32'd4) begin
            $display("FAIL ceil.w.s got=%08h want=00000004", result_word);
            failures = failures + 1;
        end
        op = 4'd14; #1;
        if (result_word !== 32'd3) begin
            $display("FAIL floor.w.s got=%08h want=00000003", result_word);
            failures = failures + 1;
        end

        // Minimum subnormal multiplied by 0.5 rounds to zero and must
        // report both underflow and inexact in the behavioral flag vector.
        op = 4'd2;
        a = 32'h00000001;
        b = 32'h3f000000;
        fmt_double = 1'b0;
        #1;
        if (exception_flags[1:0] !== 2'b11) begin
            $display("FAIL underflow/inexact flags=%b want=11", exception_flags[1:0]);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_fpu_compare predicates=16 nan=1");
        else
            $display("REGRESSION_TEST_FAIL mips_fpu_compare failures=%0d", failures);
        $finish;
    end
endmodule
