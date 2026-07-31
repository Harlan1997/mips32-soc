`timescale 1ns/1ps

module tb_axi_boot_rom;
    reg clk;
    reg rst_n;

    reg [3:0] awid;
    reg [31:0] awaddr;
    reg [7:0] awlen;
    reg [2:0] awsize;
    reg [1:0] awburst;
    reg [1:0] awlock;
    reg [3:0] awcache;
    reg [2:0] awprot;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wlast;
    reg wvalid;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;

    reg [3:0] arid;
    reg [31:0] araddr;
    reg [7:0] arlen;
    reg [2:0] arsize;
    reg [1:0] arburst;
    reg [1:0] arlock;
    reg [3:0] arcache;
    reg [2:0] arprot;
    reg arvalid;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    reg rready;

    integer errors;

    axi_boot_rom #(.ROM_BYTES(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(awid), .s_awaddr(awaddr), .s_awlen(awlen), .s_awsize(awsize),
        .s_awburst(awburst), .s_awlock(awlock), .s_awcache(awcache), .s_awprot(awprot),
        .s_awvalid(awvalid), .s_awready(awready), .s_wdata(wdata), .s_wstrb(wstrb),
        .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready), .s_bid(bid),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_arid(arid), .s_araddr(araddr), .s_arlen(arlen), .s_arsize(arsize),
        .s_arburst(arburst), .s_arlock(arlock), .s_arcache(arcache), .s_arprot(arprot),
        .s_arvalid(arvalid), .s_arready(arready), .s_rid(rid), .s_rdata(rdata),
        .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [255:0] label;
        begin
            if (!condition) begin
                $display("ERROR: %0s at %0t", label, $time);
                errors = errors + 1;
            end
        end
    endtask

    task read_beat;
        input [3:0] expected_id;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        input expected_last;
        begin
            while (!rvalid) @(negedge clk);
            check(rid == expected_id, "read ID");
            check(rdata == expected_data, "read data");
            check(rresp == expected_resp, "read response");
            check(rlast == expected_last, "read last");
            rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task issue_read;
        input [3:0] id;
        input [31:0] addr;
        input [7:0] len;
        input [2:0] size;
        begin
            @(negedge clk);
            arid = id;
            araddr = addr;
            arlen = len;
            arsize = size;
            arburst = 2'b01;
            arvalid = 1'b1;
            while (!arready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;
        end
    endtask

    task issue_write;
        input [3:0] id;
        input [31:0] addr;
        begin
            @(negedge clk);
            awid = id;
            awaddr = addr;
            awlen = 8'd0;
            awsize = 3'd2;
            awburst = 2'b01;
            awvalid = 1'b1;
            while (!awready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            awvalid = 1'b0;
            wdata = 32'hDEAD_BEEF;
            wstrb = 4'hF;
            wlast = 1'b1;
            wvalid = 1'b1;
            while (!wready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            wvalid = 1'b0;
            while (!bvalid) @(negedge clk);
            check(bid == id, "write ID");
            check(bresp == 2'b10, "ROM write SLVERR");
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        errors = 0;
        awid = 0; awaddr = 0; awlen = 0; awsize = 0; awburst = 0; awlock = 0; awcache = 0; awprot = 0; awvalid = 0;
        wdata = 0; wstrb = 0; wlast = 0; wvalid = 0; bready = 1'b1;
        arid = 0; araddr = 0; arlen = 0; arsize = 0; arburst = 0; arlock = 0; arcache = 0; arprot = 0; arvalid = 0; rready = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.rom[0] = 32'h3C08_1000;
        dut.rom[1] = 32'h4088_6000;
        dut.rom[2] = 32'h0000_0000;
        dut.rom[3] = 32'h0800_0000;

        issue_read(4'hA, 32'h1FC0_0000, 8'd3, 3'd2);
        read_beat(4'hA, 32'h3C08_1000, 2'b00, 1'b0);
        read_beat(4'hA, 32'h4088_6000, 2'b00, 1'b0);
        read_beat(4'hA, 32'h0000_0000, 2'b00, 1'b0);
        read_beat(4'hA, 32'h0800_0000, 2'b00, 1'b1);

        issue_read(4'h3, 32'h1FC0_0040, 8'd0, 3'd2);
        read_beat(4'h3, 32'd0, 2'b11, 1'b1);

        issue_write(4'h5, 32'h1FC0_0000);

        issue_read(4'h6, 32'h1FC0_0000, 8'd0, 3'd3);
        read_beat(4'h6, 32'h3C08_1000, 2'b11, 1'b1);

        if (errors == 0) begin
            $display("REGRESSION_TEST_SUCCESS axi_boot_rom");
        end else begin
            $display("REGRESSION_TEST_FAILED axi_boot_rom errors=%0d", errors);
        end
        $finish;
    end
endmodule
