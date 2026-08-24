// Optional CPU performance counters. Counters are simulation/debug-facing in
// this phase; they do not change the architectural CP0 ABI.
module mips_perf_counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        clear,
    input  wire        retire_event,
    input  wire        icache_miss_event,
    input  wire        dcache_miss_event,
    input  wire        branch_mispredict_event,
    input  wire        mdu_stall_event,
    output reg [31:0]  cycle_count,
    output reg [31:0]  retire_count,
    output reg [31:0]  icache_miss_count,
    output reg [31:0]  dcache_miss_count,
    output reg [31:0]  branch_mispredict_count,
    output reg [31:0]  mdu_stall_count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            cycle_count            <= 32'd0;
            retire_count           <= 32'd0;
            icache_miss_count      <= 32'd0;
            dcache_miss_count      <= 32'd0;
            branch_mispredict_count <= 32'd0;
            mdu_stall_count        <= 32'd0;
        end else if (enable) begin
            cycle_count <= cycle_count + 32'd1;
            if (retire_event)
                retire_count <= retire_count + 32'd1;
            if (icache_miss_event)
                icache_miss_count <= icache_miss_count + 32'd1;
            if (dcache_miss_event)
                dcache_miss_count <= dcache_miss_count + 32'd1;
            if (branch_mispredict_event)
                branch_mispredict_count <= branch_mispredict_count + 32'd1;
            if (mdu_stall_event)
                mdu_stall_count <= mdu_stall_count + 32'd1;
        end
    end
endmodule
