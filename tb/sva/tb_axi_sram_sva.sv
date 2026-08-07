`timescale 1ns/1ps
module tb_axi_sram_sva;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [3:0] awid = 0;
    reg [31:0] awaddr = 0;
    reg [7:0] awlen = 0;
    reg [2:0] awsize = 3'd2;
    reg [1:0] awburst = 2'b01;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 4'hf;
    reg wlast = 0;
    reg wvalid = 0;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    reg [3:0] arid = 0;
    reg [31:0] araddr = 0;
    reg [7:0] arlen = 0;
    reg [2:0] arsize = 3'd2;
    reg [1:0] arburst = 2'b01;
    reg arvalid = 0;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    reg rready = 0;
    integer errors = 0;

    axi_sram #(.MEM_DEPTH_WORDS(256)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(awid), .s_awaddr(awaddr), .s_awlen(awlen),
        .s_awsize(awsize), .s_awburst(awburst), .s_awvalid(awvalid),
        .s_awready(awready), .s_wdata(wdata), .s_wstrb(wstrb),
        .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bid(bid), .s_bresp(bresp), .s_bvalid(bvalid),
        .s_bready(bready), .s_arid(arid), .s_araddr(araddr),
        .s_arlen(arlen), .s_arsize(arsize), .s_arburst(arburst),
        .s_arvalid(arvalid), .s_arready(arready), .s_rid(rid),
        .s_rdata(rdata), .s_rresp(rresp), .s_rlast(rlast),
        .s_rvalid(rvalid), .s_rready(rready)
    );

    task automatic write_word(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            @(posedge clk); while (!awready) @(posedge clk);
            @(negedge clk); awvalid = 1'b0;
            wdata = data; wlast = 1'b1; wvalid = 1'b1;
            @(posedge clk); while (!wready) @(posedge clk);
            @(negedge clk); wvalid = 1'b0; wlast = 1'b0;
            bready = 1'b0;
            @(negedge clk); bready = 1'b1;
            while (!bvalid) @(posedge clk);
            @(negedge clk); bready = 1'b0;
        end
    endtask

    task automatic read_word(input [31:0] addr, input [31:0] expected);
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1'b1;
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 1'b0; rready = 1'b0;
            @(posedge clk);
            @(negedge clk); rready = 1'b1;
            while (!rvalid) @(posedge clk);
            if (rdata !== expected || !rlast || rresp !== 2'b00) begin
                $display("FAIL: AXI SRAM read data=%h last=%b resp=%b", rdata, rlast, rresp);
                errors = errors + 1;
            end
            @(posedge clk);
            @(negedge clk); rready = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        write_word(32'h20, 32'hcafe_1234);
        read_word(32'h20, 32'hcafe_1234);
        if (errors == 0) $display("REGRESSION_TEST_SUCCESS axi_sram_sva");
        else             $display("REGRESSION_TEST_FAIL axi_sram_sva errors=%0d", errors);
        $finish;
    end
endmodule
