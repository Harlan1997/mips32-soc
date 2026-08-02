`timescale 1ns/1ps

// S2 AXI-facing SoC memory integration gate for the vendor-neutral quad XIP
// path. The CPU/fabric is represented by the same AXI slave boundary used by
// soc_memory_subsystem; the pad boundary and quad flash endpoint remain
// behavioral RTL models.
module tb_soc_memory_quad_xip;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
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

    wire spi_sclk, spi_cs_n, spi_mosi, spi_miso;
    wire [3:0] qspi_io_o, qspi_io_oe;
    tri [3:0] qspi_io;
    wire [3:0] qspi_io_i = qspi_io;
    wire spi_req;
    wire qspi_timeout_sticky;
    wire qspi_controller_present;
    integer guard;

    // The memory subsystem exposes a source-side quad output contract. This
    // tri-state boundary mirrors qspi_soc_pad_mux for the focused gate.
    assign qspi_io[0] = qspi_io_oe[0] ? qspi_io_o[0] : 1'bz;
    assign qspi_io[1] = qspi_io_oe[1] ? qspi_io_o[1] : 1'bz;
    assign qspi_io[2] = qspi_io_oe[2] ? qspi_io_o[2] : 1'bz;
    assign qspi_io[3] = qspi_io_oe[3] ? qspi_io_o[3] : 1'bz;

    soc_memory_subsystem #(
        .SPI_READ_TIMEOUT_CYCLES (4096),
        .ENABLE_SHARED_ARB       (1'b1),
        .ENABLE_QSPI_QUAD        (1'b1)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .spi_sclk     (spi_sclk),
        .spi_cs_n     (spi_cs_n),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso),
        .qspi_io_i    (qspi_io_i),
        .qspi_io_o    (qspi_io_o),
        .qspi_io_oe   (qspi_io_oe),
        .spi_arb_grant(1'b1),
        .spi_req      (spi_req),
        .qspi_timeout_sticky(qspi_timeout_sticky),
        .qspi_controller_present(qspi_controller_present),
        .s2_awid      (awid), .s2_awaddr(awaddr), .s2_awlen(awlen),
        .s2_awsize    (awsize), .s2_awburst(awburst), .s2_awlock(awlock),
        .s2_awcache   (awcache), .s2_awprot(awprot), .s2_awvalid(awvalid),
        .s2_awready   (awready), .s2_wdata(wdata), .s2_wstrb(wstrb),
        .s2_wlast     (wlast), .s2_wvalid(wvalid), .s2_wready(wready),
        .s2_bid       (bid), .s2_bresp(bresp), .s2_bvalid(bvalid),
        .s2_bready    (bready), .s2_arid(arid), .s2_araddr(araddr),
        .s2_arlen     (arlen), .s2_arsize(arsize), .s2_arburst(arburst),
        .s2_arlock    (arlock), .s2_arcache(arcache), .s2_arprot(arprot),
        .s2_arvalid   (arvalid), .s2_arready(arready), .s2_rid(rid),
        .s2_rdata     (rdata), .s2_rresp(rresp), .s2_rlast(rlast),
        .s2_rvalid    (rvalid), .s2_rready(rready)
    );

    qspi_flash_quad_behavioral #(.MEM_BYTES(65536)) flash (
        .clk(clk), .rst_n(rst_n), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_io(qspi_io)
    );

    task automatic fail(input [255:0] message);
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED soc_memory_quad_xip");
            $finish;
        end
    endtask

    task automatic axi_read_burst(input [31:0] address, input [7:0] length,
                                   input [3:0] id, input [31:0] expected0,
                                   input [31:0] expected1);
        integer n;
        begin
            @(negedge clk);
            araddr = address; arlen = length; arid = id; arvalid = 1'b1;
            guard = 0;
            while (!arready && guard < 1000) begin @(posedge clk); guard = guard + 1; end
            if (!arready) fail("quad memory AR was not accepted");
            @(negedge clk); arvalid = 1'b0;
            for (n = 0; n <= length; n = n + 1) begin
                guard = 0;
                while (!rvalid && guard < 10000) begin @(posedge clk); guard = guard + 1; end
                if (!rvalid) fail("quad memory response timed out");
                if (rid !== id || rresp !== 2'b00 ||
                    (n == 0 && rdata !== expected0) ||
                    (n == 1 && rdata !== expected1) ||
                    rlast !== (n == length)) begin
                    $display("DEBUG: beat=%0d rid=%h data=%h resp=%b last=%b",
                             n, rid, rdata, rresp, rlast);
                    fail("quad memory AXI response mismatch");
                end
                @(posedge clk);
            end
        end
    endtask

    task automatic axi_write_error;
        begin
            @(negedge clk);
            awid = 4'h6; awaddr = 32'h1000_0020; awvalid = 1'b1;
            wdata = 32'h1234_5678; wlast = 1'b1; wvalid = 1'b1;
            guard = 0;
            while (!awready && guard < 1000) begin @(posedge clk); guard = guard + 1; end
            if (!awready) fail("quad memory AW was not accepted");
            @(negedge clk); awvalid = 1'b0;
            guard = 0;
            while (!wready && guard < 1000) begin @(posedge clk); guard = guard + 1; end
            if (!wready) fail("quad memory W was not accepted");
            @(negedge clk); wvalid = 1'b0;
            guard = 0;
            while (!bvalid && guard < 1000) begin @(posedge clk); guard = guard + 1; end
            if (!bvalid || bid !== 4'h6 || bresp !== 2'b10)
                fail("quad memory write did not return SLVERR");
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

        if (!qspi_controller_present)
            fail("quad memory controller-present status was not asserted");
        axi_read_burst(32'h0000_0010, 0, 4'hC, 32'hDEAD_BEEF, 0);
        axi_read_burst(32'h0000_0010, 1, 4'hD, 32'hDEAD_BEEF, 32'h1122_3344);
        axi_write_error();
        if (spi_cs_n !== 1'b1 || spi_sclk !== 1'b0 || spi_mosi !== 1'b0 ||
            qspi_io_oe !== 4'h0 || spi_req)
            fail("quad memory pins did not return idle");
        $display("REGRESSION_TEST_SUCCESS soc_memory_quad_xip");
        $finish;
    end
endmodule
