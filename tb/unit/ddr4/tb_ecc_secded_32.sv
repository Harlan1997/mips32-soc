`timescale 1ns/1ps
module tb_ecc_secded_32;
    reg [31:0] data_in; reg [38:0] code_in;
    wire [38:0] code_out; wire [31:0] data_out;
    wire corr, uncorr; integer errors;
    ecc_secded_32 dut(.data_in(data_in), .code_in(code_in), .code_out(code_out), .data_out(data_out), .correctable_error(corr), .uncorrectable_error(uncorr));
    task check; input condition; input [127:0] name; begin if (!condition) begin $display("FAIL %0s", name); errors=errors+1; end else $display("PASS %0s", name); end endtask
    initial begin
        errors=0; data_in=32'hA5C3_19E7; #1; code_in=code_out; #1;
        check(data_out==data_in && !corr && !uncorr, "clean");
        code_in=code_out ^ 39'd1; #1; check(data_out==data_in && corr && !uncorr, "single bit correction");
        code_in=code_out ^ 39'h3; #1; check(uncorr, "double bit detection");
        if (errors==0) $display("REGRESSION_TEST_SUCCESS ecc_secded_32"); else $display("REGRESSION_TEST_FAILED ecc_secded_32"); $finish;
    end
endmodule
