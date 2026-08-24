// Vendor-neutral APB view of the CPU performance counters.
// The counters are owned by the CPU and are intentionally read-only here.
// APB offsets: cycle, retire, I-miss, D-miss, branch-mispredict, MDU-stall,
// and VERSION at 0x18.
module apb_perf_counters (
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    input  wire [31:0] cycle_count,
    input  wire [31:0] retire_count,
    input  wire [31:0] icache_miss_count,
    input  wire [31:0] dcache_miss_count,
    input  wire [31:0] branch_mispredict_count,
    input  wire [31:0] mdu_stall_count
);
    localparam [31:0] VERSION = 32'h5043_0001;
    wire rd = psel & penable & ~pwrite;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    always @(*) begin
        prdata = 32'd0;
        if (rd) begin
            case (paddr[5:2])
                4'h0: prdata = cycle_count;
                4'h1: prdata = retire_count;
                4'h2: prdata = icache_miss_count;
                4'h3: prdata = dcache_miss_count;
                4'h4: prdata = branch_mispredict_count;
                4'h5: prdata = mdu_stall_count;
                4'h6: prdata = VERSION;
                default: prdata = 32'd0;
            endcase
        end
    end
endmodule
