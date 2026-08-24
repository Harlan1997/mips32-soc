`timescale 1ns/1ps

module tb_l1_cache_nb_axi_bridge;
    reg clk = 0, rst_n = 0;
    reg line_req_valid = 0, line_req_we = 0;
    reg [31:0] line_req_addr = 0;
    reg [255:0] line_req_wdata = 0;
    wire line_req_ready;
    wire line_rsp_valid, line_rsp_error;
    wire [31:0] line_rsp_addr;
    wire [255:0] line_rsp_data;

    wire [3:0] awid, arid, bid;
    wire [31:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, awlock, bresp;
    wire [1:0] arburst, arlock;
    wire [3:0] awcache, arcache;
    wire [2:0] awprot, arprot;
    wire awvalid, wvalid, wlast, bready, arvalid, rready;
    wire [31:0] wdata, rdata;
    wire [3:0] wstrb;
    reg awready = 0, wready = 0, bvalid = 0;
    reg arready = 1, rvalid = 0, rlast = 0;
    reg [3:0] rid = 0;
    reg [1:0] rresp = 2'b00;
    reg [31:0] rdata_q = 0;
    integer errors = 0;
    integer ar_count = 0;
    reg [3:0] seen_id0 = 0, seen_id1 = 0;
    reg seen0 = 0, seen1 = 0;

    assign rdata = rdata_q;
    assign bid = 4'd0;
    assign bresp = 2'b00;
    always #5 clk = ~clk;

    l1_cache_nb_axi_bridge dut (.*);

    always @(posedge clk) begin
        if (arvalid && arready) begin
            ar_count <= ar_count + 1;
            if (arid == 4'd0) begin seen0 <= 1'b1; seen_id0 <= arid; end
            if (arid == 4'd1) begin seen1 <= 1'b1; seen_id1 <= arid; end
        end
    end

    task issue_read(input [31:0] addr);
        integer cycles;
        begin
            @(negedge clk);
            line_req_addr = addr; line_req_we = 1'b0; line_req_valid = 1'b1;
            cycles = 0;
            while (!line_req_ready && cycles < 20) begin @(negedge clk); cycles = cycles + 1; end
            if (!line_req_ready) begin
                $display("FAIL request timeout addr=%h", addr); errors = errors + 1;
            end
            @(negedge clk); line_req_valid = 1'b0;
        end
    endtask

    task send_burst(input [3:0] id, input [31:0] first_word,
                    input [1:0] resp_code);
        integer beat;
        begin
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(negedge clk);
                rid = id; rresp = resp_code; rlast = (beat == 7);
                rdata_q = (beat == 0) ? first_word : 32'd0;
                rvalid = 1'b1;
                // The bridge consumes one beat on the next rising edge.  On
                // the final beat rready drops immediately after that edge as
                // the slot is retired, so do not poll it at the following
                // falling edge.
                @(posedge clk);
                if (!rready) begin
                    $display("FAIL R timeout id=%0d beat=%0d", id, beat);
                    errors = errors + 1;
                end
                @(negedge clk); rvalid = 1'b0; rlast = 1'b0;
            end
        end
    endtask

    task check_response(input [31:0] expected_addr,
                        input [31:0] expected_word,
                        input expected_error);
        begin
            #1;
            if (!line_rsp_valid || line_rsp_addr != expected_addr ||
                line_rsp_data[31:0] != expected_word ||
                line_rsp_error != expected_error) begin
                $display("FAIL response valid=%b addr=%h data=%h err=%b expected addr=%h data=%h err=%b",
                         line_rsp_valid, line_rsp_addr, line_rsp_data[31:0],
                         line_rsp_error, expected_addr, expected_word, expected_error);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Two independent reads must be accepted before either response.
        issue_read(32'h00000040);
        issue_read(32'h00000100);
        repeat (2) @(posedge clk);
        #1;
        if (ar_count != 2 || !seen0 || !seen1 || seen_id0 != 0 || seen_id1 != 1) begin
            $display("FAIL AR issue count=%0d seen0=%b seen1=%b ids=%h/%h",
                     ar_count, seen0, seen1, seen_id0, seen_id1);
            errors = errors + 1;
        end

        // Return ID 1 first, with an error, then ID 0 without an error.
        send_burst(4'd1, 32'h11110001, 2'b10);
        check_response(32'h00000100, 32'h11110001, 1'b1);
        send_burst(4'd0, 32'h00000040, 2'b00);
        check_response(32'h00000040, 32'h00000040, 1'b0);

        // Reset must remove both read slots and suppress further responses.
        issue_read(32'h00000200);
        @(negedge clk); rst_n = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (arvalid || line_rsp_valid || dut.rd_active[0] || dut.rd_active[1]) begin
            $display("FAIL reset did not flush bridge arvalid=%b rsp=%b active=%b/%b",
                     arvalid, line_rsp_valid, dut.rd_active[0], dut.rd_active[1]);
            errors = errors + 1;
        end
        rst_n = 1'b1;

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS l1nb_axi_bridge slots=2 ooo=1 reset=1");
        else
            $display("REGRESSION_TEST_FAILED l1nb_axi_bridge errors=%0d", errors);
        $finish;
    end
endmodule
