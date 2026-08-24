`timescale 1ns/1ps
module tb_l1_cache_nb_errors;
    reg clk = 0, rst_n = 0;
    reg cpu_valid = 0, cpu_we = 0;
    reg [3:0] cpu_id = 0, cpu_be = 4'hf;
    reg [31:0] cpu_addr = 0, cpu_wdata = 0;
    reg cache_maint_invalidate = 0;
    wire cpu_ready, rsp_valid, rsp_error;
    wire [3:0] rsp_id;
    wire [31:0] rsp_rdata;
    reg rsp_ready = 0;
    wire mem_req_valid, mem_req_we;
    wire [31:0] mem_req_addr;
    wire [255:0] mem_req_wdata;
    reg mem_req_ready = 1, mem_rsp_valid = 0, mem_rsp_error = 0;
    reg [31:0] mem_rsp_addr = 0;
    reg [255:0] mem_rsp_data = 0;
    wire [3:0] mshr_occupancy, wb_occupancy;
    integer errors = 0;

    always #5 clk = ~clk;
    l1_cache_nb #(.MSHR_COUNT(2), .WB_DEPTH(4), .SETS(4)) dut (.*);

    task issue_read(input [3:0] id, input [31:0] addr);
        begin
            @(negedge clk);
            cpu_id = id; cpu_addr = addr; cpu_we = 1'b0; cpu_valid = 1'b1;
            while (!cpu_ready) @(negedge clk);
            @(negedge clk); cpu_valid = 1'b0;
        end
    endtask

    task return_line_error(input [31:0] addr);
        begin
            @(negedge clk);
            mem_rsp_addr = addr; mem_rsp_data = 256'd0;
            mem_rsp_error = 1'b1; mem_rsp_valid = 1'b1;
            @(negedge clk);
            mem_rsp_valid = 1'b0; mem_rsp_error = 1'b0;
        end
    endtask

    task pop_response(input [3:0] expected_id);
        begin
            #1;
            if (!rsp_valid || !rsp_error || rsp_id != expected_id) begin
                $display("FAIL error response id=%h expected=%h valid=%b error=%b",
                         rsp_id, expected_id, rsp_valid, rsp_error);
                errors = errors + 1;
            end
            @(negedge clk); rsp_ready = 1'b1;
            @(negedge clk); rsp_ready = 1'b0;
        end
    endtask

    task check_empty(input [127:0] tag);
        begin
            #1;
            if (rsp_valid || mshr_occupancy != 0 || wb_occupancy != 0) begin
                $display("FAIL %0s not empty rsp=%b mshr=%0d wb=%0d",
                         tag, rsp_valid, mshr_occupancy, wb_occupancy);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk); rst_n = 1'b1;

        // A failed refill must reach both the primary and merged secondary.
        issue_read(4'ha, 32'h00000040);
        issue_read(4'hb, 32'h00000044);
        return_line_error(32'h00000040);
        pop_response(4'ha); pop_response(4'hb);
        check_empty("merged_error");

        // Distinct failed refills complete out of order with IDs preserved.
        issue_read(4'hc, 32'h000000c0);
        issue_read(4'hd, 32'h00000100);
        return_line_error(32'h00000100);
        return_line_error(32'h000000c0);
        pop_response(4'hd); pop_response(4'hc);
        check_empty("distinct_error");

        // Reset while an error response is queued must flush all state.
        issue_read(4'he, 32'h00000140);
        return_line_error(32'h00000140);
        #1;
        if (!rsp_valid || !rsp_error) begin
            $display("FAIL queued error before reset"); errors = errors + 1;
        end
        rst_n = 1'b0; repeat (2) @(posedge clk);
        check_empty("reset_flush");
        rst_n = 1'b1; repeat (2) @(posedge clk);
        check_empty("post_reset");

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS l1nb_errors mshr=2 wb=4");
        else
            $display("REGRESSION_TEST_FAILED l1nb_errors errors=%0d", errors);
        $finish;
    end
endmodule
