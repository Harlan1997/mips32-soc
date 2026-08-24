`timescale 1ns/1ps

module tb_mips_fpu_flags;
    localparam OP_MUL = 5'd2, OP_DIV = 5'd3, OP_SUB = 5'd1;
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

    mips_fpu dut (.*);

    task check_flags;
        input [4:0] expected;
        input [127:0] name;
        begin
            #1;
            if (exception_flags !== expected) begin
                $display("FPU_FLAGS_FAIL %0s got=%b expected=%b", name,
                         exception_flags, expected);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        op = OP_DIV; a = 0; b = 0; c = 0; compare_condition = 0;
        fmt_double = 1; rounding_mode = 0;
        a_double = 64'h7ff0000000000000;
        b_double = 64'h7ff0000000000000;
        c_double = 0;
        check_flags(5'b10000, "double_inf_div_inf_invalid");

        op = OP_MUL;
        a_double = 64'h0000000000000000;
        b_double = 64'h7ff0000000000000;
        check_flags(5'b10000, "double_zero_mul_inf_invalid");

        op = OP_MUL;
        a_double = 64'h0010000000000000;
        b_double = 64'h3fe0000000000000;
        check_flags(5'b00010, "double_subnormal_underflow");

        fmt_double = 0;
        op = OP_SUB;
        a = 32'h7f800000;
        b = 32'h7f800000;
        check_flags(5'b10000, "single_inf_sub_inf_invalid");

        // Conversion to signed 32-bit must classify NaN, infinity and both
        // out-of-range boundaries as Invalid with the MIPS indefinite result.
        fmt_double = 0;
        op = 5'd10; // CVT.W.S
        a = 32'h4f000000; // +2^31
        check_flags(5'b10000, "single_cvt_w_out_of_range");
        #1;
        if (result_word !== 32'h80000000) begin
            $display("FPU_FLAGS_FAIL single conversion result=%08h", result_word);
            failures = failures + 1;
        end
        a = 32'hcf000001; // less than -2^31
        check_flags(5'b10000, "single_cvt_w_negative_out_of_range");

        fmt_double = 1;
        op = 5'd18; // CVT.W.D
        a_double = 64'h7ff0000000000000; // +inf
        check_flags(5'b10000, "double_cvt_w_inf_invalid");
        #1;
        if (result_word !== 32'h80000000) begin
            $display("FPU_FLAGS_FAIL double conversion result=%08h", result_word);
            failures = failures + 1;
        end
        a_double = 64'h41e0000000000000; // +2^31
        check_flags(5'b10000, "double_cvt_w_out_of_range");

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_fpu_flags invalid=7 underflow=1 conversion=1");
        else
            $display("REGRESSION_TEST_FAIL mips_fpu_flags failures=%0d", failures);
        $finish;
    end
endmodule
