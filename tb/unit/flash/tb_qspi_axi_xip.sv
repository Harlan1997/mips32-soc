`timescale 1ns/1ps

// AXI -> internal APB QSPI command -> SPI flash endpoint contract.
module tb_qspi_axi_xip;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [3:0] arid = 0;
    reg [31:0] araddr = 0;
    reg [7:0] arlen = 0;
    reg [2:0] arsize = 2;
    reg [1:0] arburst = 1;
    reg [1:0] arlock = 0;
    reg [3:0] arcache = 0;
    reg [2:0] arprot = 0;
    reg arvalid = 0;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast, rvalid;
    reg rready = 1;

    reg [3:0] awid = 0;
    reg [31:0] awaddr = 0;
    reg [7:0] awlen = 0;
    reg [2:0] awsize = 2;
    reg [1:0] awburst = 1;
    reg [1:0] awlock = 0;
    reg [3:0] awcache = 0;
    reg [2:0] awprot = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 4'hf;
    reg wlast = 1;
    reg wvalid = 0;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1;

    wire spi_sclk, spi_cs_n, spi_mosi, spi_miso, active;
    tri [3:0] qspi_io;
    wire [3:0] qspi_io_o, qspi_io_oe;
    integer errors = 0;
    integer guard;

    qspi_axi_xip #(
`ifdef QSPI_AXI_XIP_QUAD
        .ENABLE_QUAD_IO(1'b1)
`else
        .ENABLE_QUAD_IO(1'b0)
`endif
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_arid(arid), .s_araddr(araddr), .s_arlen(arlen),
        .s_arsize(arsize), .s_arburst(arburst), .s_arlock(arlock),
        .s_arcache(arcache), .s_arprot(arprot), .s_arvalid(arvalid),
        .s_arready(arready), .s_rid(rid), .s_rdata(rdata),
        .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid),
        .s_rready(rready),
        .s_awid(awid), .s_awaddr(awaddr), .s_awlen(awlen),
        .s_awsize(awsize), .s_awburst(awburst), .s_awlock(awlock),
        .s_awcache(awcache), .s_awprot(awprot), .s_awvalid(awvalid),
        .s_awready(awready), .s_wdata(wdata), .s_wstrb(wstrb),
        .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bid(bid), .s_bresp(bresp), .s_bvalid(bvalid),
        .s_bready(bready), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso), .qspi_io_o(qspi_io_o),
        .qspi_io_oe(qspi_io_oe), .qspi_io(qspi_io), .active(active)
    );

`ifdef QSPI_AXI_XIP_QUAD
    qspi_flash_quad_behavioral #(.MEM_BYTES(65536)) flash (
        .clk(clk), .rst_n(rst_n), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_io(qspi_io)
    );
`else
    spi_flash_behavioral #(.MEM_BYTES(65536)) flash (
        .clk(clk), .rst_n(rst_n), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );
`endif

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED qspi_axi_xip");
            $finish;
        end
    endtask

    task automatic axi_read_burst(input [31:0] address, input [7:0] length,
                                   input [3:0] id,
                                   input [31:0] expected0,
                                   input [31:0] expected1);
        integer n;
        begin
            @(negedge clk);
            araddr = address; arlen = length; arid = id; arvalid = 1'b1;
            guard = 0;
            while (!arready && guard < 200) begin @(posedge clk); guard = guard + 1; end
            if (!arready) fail("AXI AR was not accepted");
            @(negedge clk); arvalid = 1'b0;
            for (n = 0; n <= length; n = n + 1) begin
                guard = 0;
                while (!rvalid && guard < 5000) begin @(posedge clk); guard = guard + 1; end
                if (!rvalid) fail("QSPI XIP response timed out");
                if (rid !== id || rresp !== 2'b00 ||
                    (n == 0 && rdata !== expected0) ||
                    (n == 1 && rdata !== expected1) ||
                    rlast !== (n == length)) begin
                    $display("DEBUG: beat=%0d rid=%h data=%h resp=%b last=%b",
                             n, rid, rdata, rresp, rlast);
                    fail("AXI XIP response mismatch");
                end
                @(posedge clk);
            end
        end
    endtask

    task automatic axi_write_error;
        begin
            @(negedge clk);
            awid = 4'h5; awaddr = 32'h1000_0020; awvalid = 1'b1;
            wdata = 32'h1234_5678; wlast = 1'b1; wvalid = 1'b1;
            guard = 0;
            while (!awready && guard < 100) begin @(posedge clk); guard = guard + 1; end
            if (!awready) fail("AXI write address was not accepted");
            @(negedge clk); awvalid = 1'b0;
            guard = 0;
            while (!wready && guard < 100) begin @(posedge clk); guard = guard + 1; end
            if (!wready) fail("AXI write data was not accepted");
            @(negedge clk); wvalid = 1'b0;
            guard = 0;
            while (!bvalid && guard < 100) begin @(posedge clk); guard = guard + 1; end
            if (!bvalid || bid !== 4'h5 || bresp !== 2'b10)
                fail("QSPI XIP write did not return SLVERR");
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        flash.mem[16'h0010] = 8'hDE;
        flash.mem[16'h0011] = 8'hAD;
        flash.mem[16'h0012] = 8'hBE;
        flash.mem[16'h0013] = 8'hEF;
        flash.mem[16'h0014] = 8'h11;
        flash.mem[16'h0015] = 8'h22;
        flash.mem[16'h0016] = 8'h33;
        flash.mem[16'h0017] = 8'h44;

        axi_read_burst(32'h0000_0010, 0, 4'hA, 32'hDEAD_BEEF, 0);
        axi_read_burst(32'h0000_0010, 1, 4'hB, 32'hDEAD_BEEF, 32'h1122_3344);
        axi_write_error();

        if (active || spi_cs_n !== 1'b1)
            fail("QSPI XIP pins did not return idle");
        if (errors != 0)
            fail("QSPI XIP checks failed");
        $display("REGRESSION_TEST_SUCCESS qspi_axi_xip");
        $finish;
    end
endmodule
