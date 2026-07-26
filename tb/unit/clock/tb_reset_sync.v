// Unit test: reset_sync — async assert, sync deassert (STAGES=3 cycles)
module tb_reset_sync;
    reg  clk = 0;
    reg  rst_pre_n = 0;
    wire rst_n;
    integer errs = 0;

    always #5 clk = ~clk;

    reset_sync #(.STAGES(3)) dut (
        .clk(clk), .rst_pre_n(rst_pre_n), .rst_n(rst_n));

    initial begin
        // Async assert should hold rst_n low immediately
        #2;
        if (rst_n !== 1'b0) begin
            $display("FAIL: rst_n should be low during reset"); errs = errs + 1;
        end

        // Deassert rst_pre_n; rst_n must rise exactly STAGES cycles later
        @(negedge clk); rst_pre_n = 1;
        @(posedge clk); // stage 1 shifts in 1
        @(posedge clk); // stage 2
        @(posedge clk); // stage 3 — rst_n goes high now
        #1;
        if (rst_n !== 1'b1) begin
            $display("FAIL: rst_n should be high after 3 posedges"); errs = errs + 1;
        end

        // Async reassert should drop rst_n immediately
        rst_pre_n = 0;
        #1;
        if (rst_n !== 1'b0) begin
            $display("FAIL: rst_n should drop immediately on async assert"); errs = errs + 1;
        end

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS reset_sync");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
