`timescale 1ns/1ps

module tb_wdt_peripheral;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg [3:0] s_awid = 0;
    reg [31:0] s_awaddr = 0;
    reg [7:0] s_awlen = 0;
    reg [2:0] s_awsize = 3'd2;
    reg [1:0] s_awburst = 2'b01;
    reg [1:0] s_awlock = 0;
    reg [3:0] s_awcache = 0;
    reg [2:0] s_awprot = 0;
    reg s_awvalid = 0;
    wire s_awready;
    reg [31:0] s_wdata = 0;
    reg [3:0] s_wstrb = 4'hf;
    reg s_wlast = 1'b1;
    reg s_wvalid = 0;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    reg s_bready = 1'b1;

    reg [3:0] s_arid = 0;
    reg [31:0] s_araddr = 0;
    reg [7:0] s_arlen = 0;
    reg [2:0] s_arsize = 3'd2;
    reg [1:0] s_arburst = 2'b01;
    reg [1:0] s_arlock = 0;
    reg [3:0] s_arcache = 0;
    reg [2:0] s_arprot = 0;
    reg s_arvalid = 0;
    wire s_arready;
    wire [3:0] s_rid;
    wire [31:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    reg s_rready = 1'b1;

    wire [3:0] m_awid;
    wire [31:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire [1:0] m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire m_awvalid;
    reg m_awready = 1'b1;
    wire [31:0] m_wdata;
    wire [3:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    reg m_wready = 1'b1;
    reg [3:0] m_bid = 0;
    reg [1:0] m_bresp = 0;
    reg m_bvalid = 0;
    wire m_bready;
    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire [1:0] m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire m_arvalid;
    reg m_arready = 1'b1;
    reg [3:0] m_rid = 0;
    reg [31:0] m_rdata = 0;
    reg [1:0] m_rresp = 0;
    reg m_rlast = 1'b1;
    reg m_rvalid = 0;
    wire m_rready;

    wire [31:0] gpio_pins;
    wire uart_tx, uart_rts_n, uart_dtr_n;
    reg uart_rx = 1'b1, uart_cts_n = 1'b0, uart_dsr_n = 1'b0;
    reg uart_dcd_n = 1'b0, uart_ri_n = 1'b1;
    wire cpu_int, wdt_reset;
    wire spi_sclk, spi_cs_n, spi_mosi;
    reg spi_miso = 1'b0;
    wire soc_rst_n = rst_n & ~wdt_reset;
    integer errors = 0;

    always #5 clk = ~clk;

    soc_peripheral_subsystem dut (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n), .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n), .cpu_int(cpu_int),
        .wdt_reset(wdt_reset), .qspi_timeout_sticky(1'b0),
        .qspi_controller_present(1'b0),
        .spi_miso(spi_miso), .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .qspi_active(),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(s_awsize),
        .s_awburst(s_awburst), .s_awlock(s_awlock), .s_awcache(s_awcache),
        .s_awprot(s_awprot), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid),
        .s_bready(s_bready), .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arlock(s_arlock),
        .s_arcache(s_arcache), .s_arprot(s_arprot), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awlock(m_awlock), .m_awcache(m_awcache),
        .m_awprot(m_awprot), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid),
        .m_wready(m_wready), .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid),
        .m_bready(m_bready), .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arlock(m_arlock),
        .m_arcache(m_arcache), .m_arprot(m_arprot), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            s_awaddr = addr; s_wdata = data; s_awvalid = 1'b1; s_wvalid = 1'b1;
            while (!(s_awready && s_wready)) @(posedge clk);
            @(negedge clk);
            s_awvalid = 1'b0; s_wvalid = 1'b0;
            timeout = 0;
            while (!s_bvalid && timeout < 20) begin @(posedge clk); timeout = timeout + 1; end
            if (!s_bvalid || s_bresp !== 2'b00) begin
                $display("FAIL: AXI write addr=%h resp=%b", addr, s_bresp);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    task axi_read;
        input [31:0] addr;
        input [31:0] expected;
        integer timeout;
        begin
            @(negedge clk);
            s_araddr = addr; s_arvalid = 1'b1;
            while (!s_arready) @(posedge clk);
            @(negedge clk);
            s_arvalid = 1'b0;
            timeout = 0;
            while (!s_rvalid && timeout < 20) begin @(posedge clk); timeout = timeout + 1; end
            if (!s_rvalid || s_rresp !== 2'b00 || s_rdata !== expected) begin
                $display("FAIL: AXI read addr=%h got=%h resp=%b expected=%h", addr, s_rdata, s_rresp, expected);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        axi_read(32'h4000_7000, 32'h0);
        axi_write(32'h4000_8000, 32'h70);
        axi_write(32'h4000_8004, 32'hDEAD_B007);
        axi_write(32'h4000_7004, 32'd3);
        axi_write(32'h4000_7000, 32'h1);
        wait (wdt_reset === 1'b1);
        if (soc_rst_n !== 1'b0) begin
            $display("FAIL: watchdog pulse did not assert aggregate reset");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (wdt_reset !== 1'b0 || soc_rst_n !== 1'b1) begin
            $display("FAIL: aggregate reset did not release after one cycle");
            errors = errors + 1;
        end
        axi_read(32'h4000_7010, 32'h1);
        axi_read(32'h4000_8000, 32'h70);
        axi_read(32'h4000_8004, 32'hDEAD_B007);
        axi_read(32'h4000_8008, 32'h3);
        axi_write(32'h4000_8008, 32'h2);
        axi_read(32'h4000_8008, 32'h1);
        axi_write(32'h4000_8004, 32'h0);
        axi_read(32'h4000_8004, 32'h0);
        axi_write(32'h4000_7010, 32'h1);
        axi_read(32'h4000_7010, 32'h0);

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS wdt_peripheral");
        else
            $display("REGRESSION_TEST_FAILED wdt_peripheral errors=%0d", errors);
        $finish;
    end
endmodule
