// CPU pipeline contract test for the implemented CACHE D-cache subset.
`timescale 1ns/1ps

module tb_mips_cpu_cacheop;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire        inst_req;
    wire [31:0] inst_addr;
    reg  [31:0] inst_rdata;
    wire        data_req, data_we;
    wire [31:0] data_addr, data_wdata;
    wire [3:0]  data_be;
    wire        cache_op_valid;
    wire [4:0]  cache_op;
    wire [31:0] cache_op_addr;
    reg         cache_op_done = 1'b0;
    wire        cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire [31:0] data_cache_tag_wdata;
    wire [31:0] data_rdata = 32'd0;

    wire inst_addr_ok = 1'b1;
    wire inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0;
    wire inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1;
    wire data_data_ok = 1'b1;
    wire data_bus_error = 1'b0;
    wire data_cache_error = 1'b0;
    wire data_uncacheable;
    wire debug_stall, debug_flush;

    reg [31:0] imem [0:255];
    reg [31:0] fetch_addr_q;
    reg        prev_op_valid;
    integer   op_count;
    integer   i;

    always @(*) inst_rdata = imem[fetch_addr_q[9:2]];

    // One-cycle completion makes the cache-maintenance bubble observable while
    // still modelling a downstream D-cache that accepted the request.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_addr_q <= 32'd0;
            cache_op_done <= 1'b0;
            prev_op_valid <= 1'b0;
            op_count <= 0;
        end else begin
            fetch_addr_q <= inst_addr;
            cache_op_done <= cache_op_valid;
            if (cache_op_valid && !prev_op_valid) begin
                if (data_req) $display("FAIL CACHE instruction also asserted data_req");
                if (cache_op !== 5'b10101) $display("FAIL CACHE op=%b", cache_op);
                op_count <= op_count + 1;
            end
            prev_op_valid <= cache_op_valid;
        end
    end

    mips_cpu u_cpu (
        .clk(clk), .rst_n(rst_n),
        .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
        .inst_bus_error(inst_bus_error), .inst_cache_error(inst_cache_error),
        .inst_rdata(inst_rdata),
        .data_req(data_req), .data_we(data_we), .data_addr(data_addr),
        .data_wdata(data_wdata), .data_be(data_be),
        .data_uncacheable(data_uncacheable),
        .data_cache_op_valid(cache_op_valid), .data_cache_op(cache_op),
        .data_cache_op_addr(cache_op_addr), .data_cache_op_done(cache_op_done),
        .data_cache_op_error(cache_op_error),
        .data_cache_tag_rdata(data_cache_tag_rdata),
        .data_cache_tag_wdata(data_cache_tag_wdata),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok),
        .data_bus_error(data_bus_error), .data_cache_error(data_cache_error),
        .data_rdata(data_rdata), .ext_int(6'd0),
        .debug_stall(debug_stall), .debug_flush(debug_flush)
    );

    initial begin
        for (i = 0; i < 256; i = i + 1) imem[i] = 32'd0;
        // CACHE Hit_Invalidate_D, $0, 0($0), followed by NOPs.
        imem[0] = 32'hBC15_0000;
        #17 rst_n = 1'b1;
        #300;
        if (op_count != 1)
            $display("REGRESSION_TEST_FAIL cacheop count=%0d", op_count);
        else
            $display("REGRESSION_TEST_SUCCESS mips_cpu_cacheop");
        $finish;
    end
endmodule
