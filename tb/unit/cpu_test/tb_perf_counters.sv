`timescale 1ns/1ps

module tb_perf_counters;
    reg clk = 0;
    reg rst_n = 0;
    reg enable = 0;
    reg clear = 0;
    reg retire_event = 0;
    reg icache_miss_event = 0;
    reg dcache_miss_event = 0;
    reg branch_mispredict_event = 0;
    reg mdu_stall_event = 0;
    wire [31:0] cycle_count, retire_count, icache_miss_count;
    wire [31:0] dcache_miss_count, branch_mispredict_count, mdu_stall_count;
    integer errors = 0;

    always #5 clk = ~clk;

    mips_perf_counters dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .clear(clear),
        .retire_event(retire_event), .icache_miss_event(icache_miss_event),
        .dcache_miss_event(dcache_miss_event),
        .branch_mispredict_event(branch_mispredict_event),
        .mdu_stall_event(mdu_stall_event),
        .cycle_count(cycle_count), .retire_count(retire_count),
        .icache_miss_count(icache_miss_count),
        .dcache_miss_count(dcache_miss_count),
        .branch_mispredict_count(branch_mispredict_count),
        .mdu_stall_count(mdu_stall_count)
    );

    task tick;
    begin @(negedge clk); @(posedge clk); end
    endtask

    initial begin
        repeat (2) tick;
        rst_n = 1'b1;
        enable = 1'b1;
        retire_event = 1'b1;
        icache_miss_event = 1'b1;
        dcache_miss_event = 1'b1;
        branch_mispredict_event = 1'b1;
        mdu_stall_event = 1'b1;
        tick;
        retire_event = 1'b0;
        icache_miss_event = 1'b0;
        dcache_miss_event = 1'b0;
        branch_mispredict_event = 1'b0;
        mdu_stall_event = 1'b0;
        tick;
        enable = 1'b0;
        tick;
        if (cycle_count !== 32'd2 || retire_count !== 32'd1 ||
            icache_miss_count !== 32'd1 || dcache_miss_count !== 32'd1 ||
            branch_mispredict_count !== 32'd1 || mdu_stall_count !== 32'd1) begin
            $display("FAIL counter enable/event accounting: cyc=%0d ret=%0d i=%0d d=%0d b=%0d m=%0d",
                     cycle_count, retire_count, icache_miss_count,
                     dcache_miss_count, branch_mispredict_count, mdu_stall_count);
            errors = errors + 1;
        end
        clear = 1'b1;
        tick;
        clear = 1'b0;
        if (cycle_count !== 0 || retire_count !== 0 || icache_miss_count !== 0 ||
            dcache_miss_count !== 0 || branch_mispredict_count !== 0 ||
            mdu_stall_count !== 0) begin
            $display("FAIL counter clear");
            errors = errors + 1;
        end
        if (errors == 0) $display("REGRESSION_TEST_SUCCESS perf_counters");
        else $display("REGRESSION_TEST_FAIL perf_counters errors=%0d", errors);
        $finish;
    end
endmodule
