`timescale 1ns/1ps

// Integrates the real AXI timeout guard with the product peripheral APB
// decode. A stalled downstream read must become an observable QSPI status
// record, and software must be able to clear it through the mapped register.
module tb_qspi_status_integration;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer errors = 0;
    always #5 clk = ~clk;

    reg [3:0]  g_s_arid = 0;
    reg [31:0] g_s_araddr = 0;
    reg [7:0]  g_s_arlen = 0;
    reg [2:0]  g_s_arsize = 2;
    reg [1:0]  g_s_arburst = 1;
    reg [1:0]  g_s_arlock = 0;
    reg [3:0]  g_s_arcache = 0;
    reg [2:0]  g_s_arprot = 0;
    reg        g_s_arvalid = 0;
    wire       g_s_arready;
    wire [3:0] g_s_rid;
    wire [31:0] g_s_rdata;
    wire [1:0] g_s_rresp;
    wire       g_s_rlast;
    wire       g_s_rvalid;
    reg        g_s_rready = 1'b1;
    wire [3:0]  g_m_arid;
    wire [31:0] g_m_araddr;
    wire [7:0]  g_m_arlen;
    wire [2:0]  g_m_arsize;
    wire [1:0]  g_m_arburst;
    wire [1:0]  g_m_arlock;
    wire [3:0]  g_m_arcache;
    wire [2:0]  g_m_arprot;
    wire        g_m_arvalid;
    reg         g_m_arready = 1'b0;
    reg [3:0]   g_m_rid = 0;
    reg [31:0]  g_m_rdata = 0;
    reg [1:0]   g_m_rresp = 0;
    reg         g_m_rlast = 1'b1;
    reg         g_m_rvalid = 1'b0;
    wire        g_m_rready;
    wire        timeout_sticky;

    axi_read_timeout_guard #(.TIMEOUT_CYCLES(3)) u_guard (
        .clk(clk), .rst_n(rst_n),
        .s_arid(g_s_arid), .s_araddr(g_s_araddr), .s_arlen(g_s_arlen),
        .s_arsize(g_s_arsize), .s_arburst(g_s_arburst), .s_arlock(g_s_arlock),
        .s_arcache(g_s_arcache), .s_arprot(g_s_arprot), .s_arvalid(g_s_arvalid),
        .s_arready(g_s_arready), .s_rid(g_s_rid), .s_rdata(g_s_rdata),
        .s_rresp(g_s_rresp), .s_rlast(g_s_rlast), .s_rvalid(g_s_rvalid),
        .s_rready(g_s_rready), .m_arid(g_m_arid), .m_araddr(g_m_araddr),
        .m_arlen(g_m_arlen), .m_arsize(g_m_arsize), .m_arburst(g_m_arburst),
        .m_arlock(g_m_arlock), .m_arcache(g_m_arcache), .m_arprot(g_m_arprot),
        .m_arvalid(g_m_arvalid), .m_arready(g_m_arready), .m_rid(g_m_rid),
        .m_rdata(g_m_rdata), .m_rresp(g_m_rresp), .m_rlast(g_m_rlast),
        .m_rvalid(g_m_rvalid), .m_rready(g_m_rready),
        .timeout_sticky(timeout_sticky)
    );

    reg [3:0] s_awid = 0;
    reg [31:0] s_awaddr = 0;
    reg [7:0] s_awlen = 0;
    reg [2:0] s_awsize = 2;
    reg [1:0] s_awburst = 1;
    reg [1:0] s_awlock = 0;
    reg [3:0] s_awcache = 0;
    reg [2:0] s_awprot = 0;
    reg s_awvalid = 0;
    wire s_awready;
    reg [31:0] s_wdata = 0;
    reg [3:0] s_wstrb = 4'hf;
    reg s_wlast = 1;
    reg s_wvalid = 0;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    reg s_bready = 1;
    reg [3:0] s_arid = 0;
    reg [31:0] s_araddr = 0;
    reg [7:0] s_arlen = 0;
    reg [2:0] s_arsize = 2;
    reg [1:0] s_arburst = 1;
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
    reg s_rready = 1;
    wire [31:0] gpio_pins;
    wire uart_tx, uart_rts_n, uart_dtr_n, cpu_int, wdt_reset;
    reg uart_rx = 1, uart_cts_n = 0, uart_dsr_n = 0, uart_dcd_n = 0, uart_ri_n = 1;
    wire cmd_spi_sclk, cmd_spi_cs_n, cmd_spi_mosi;
    wire spi_sclk, spi_cs_n, spi_mosi, qspi_active, qspi_cmd_req;
    wire qspi_cmd_grant;
    wire [3:0] qspi_cmd_io_o, qspi_cmd_io_oe;
    tri [3:0] qspi_io;
    wire spi_miso = qspi_io[0];
    integer qspi_sclk_edges = 0;
    integer qspi_cmd_bits = 0;
    integer qspi_guard = 0;
    reg [31:0] rd_value;
    reg [7:0] qspi_cmd_capture = 8'h0;
    reg qspi_cs_seen = 1'b0;
    integer qspi_quad_groups = 0;
    reg [31:0] qspi_quad_capture = 32'h0;

    wire [3:0] m_awid, m_bid, m_arid, m_rid;
    wire [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    wire [7:0] m_awlen, m_arlen;
    wire [2:0] m_awsize, m_arsize, m_awprot, m_arprot;
    wire [1:0] m_awburst, m_awlock, m_arburst, m_arlock, m_bresp, m_rresp;
    wire [3:0] m_awcache, m_arcache, m_wstrb;
    wire m_awvalid, m_awready = 1'b0, m_wlast, m_wvalid, m_wready = 1'b0;
    wire m_bvalid = 1'b0, m_bready, m_arvalid, m_arready = 1'b0;
    wire m_rlast, m_rvalid = 1'b0, m_rready;

    wire qspi_flash_read_active = !spi_cs_n &&
        dut.u_qspi_apb_integration.u_cmd.state == 3'd5 &&
        !dut.u_qspi_apb_integration.u_cmd.data_write &&
        dut.u_qspi_apb_integration.u_cmd.phase_lane_r == 3'd4;
    wire [3:0] qspi_flash_read_nibble =
        (dut.u_qspi_apb_integration.u_cmd.phase_bits_left == 7'd8) ?
        4'hC : 4'h3;
    assign qspi_io = qspi_flash_read_active ? qspi_flash_read_nibble : 4'bz;

    soc_peripheral_subsystem #(
        .ENABLE_QSPI_SHARED_ARB(1'b1),
        .ENABLE_QSPI_QUAD(1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n), .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n), .cpu_int(cpu_int),
        .wdt_reset(wdt_reset), .qspi_controller_present(1'b1),
        .qspi_timeout_sticky(timeout_sticky),
        .spi_miso(spi_miso), .spi_sclk(cmd_spi_sclk), .spi_cs_n(cmd_spi_cs_n),
        .spi_mosi(cmd_spi_mosi), .qspi_io_i(qspi_io),
        .qspi_io_o(qspi_cmd_io_o), .qspi_io_oe(qspi_cmd_io_oe),
        .qspi_cmd_grant(qspi_cmd_grant), .qspi_active(qspi_active),
        .qspi_cmd_req(qspi_cmd_req),
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

    qspi_shared_pin_arbiter u_qspi_arbiter (
        .clk(clk), .rst_n(rst_n),
        .cmd_req(qspi_cmd_req), .cmd_active(qspi_active),
        .cmd_sclk(cmd_spi_sclk), .cmd_cs_n(cmd_spi_cs_n),
        .cmd_mosi(cmd_spi_mosi),
        .mem_req(1'b0), .mem_active(1'b0), .mem_sclk(1'b0),
        .mem_cs_n(1'b1), .mem_mosi(1'b0),
        .cmd_grant(qspi_cmd_grant), .mem_grant(),
        .spi_sclk(), .spi_cs_n(), .spi_mosi(), .busy(), .conflict()
    );

    qspi_soc_pad_mux #(.ENABLE_QUAD_IO(1'b1)) u_qspi_pad_mux (
        .cmd_grant(qspi_cmd_grant), .cmd_sclk(cmd_spi_sclk),
        .cmd_cs_n(cmd_spi_cs_n), .cmd_io_o(qspi_cmd_io_o),
        .cmd_io_oe(qspi_cmd_io_oe), .mem_grant(1'b0), .mem_sclk(1'b0),
        .mem_cs_n(1'b1), .mem_mosi(1'b0), .spi_sclk(spi_sclk),
        .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .qspi_io_o(),
        .qspi_io_oe(), .qspi_io(qspi_io)
    );

    always @(negedge spi_cs_n) begin
        qspi_cs_seen = 1'b1;
        qspi_cmd_bits = 0;
        qspi_cmd_capture = 8'h0;
    end

    always @(posedge spi_sclk) begin
        if (!spi_cs_n) begin
            qspi_sclk_edges = qspi_sclk_edges + 1;
            if (qspi_cmd_bits < 8)
                qspi_cmd_capture = {qspi_cmd_capture[6:0], spi_mosi};
            qspi_cmd_bits = qspi_cmd_bits + 1;
            if (qspi_cmd_io_oe === 4'hf) begin
                qspi_quad_capture = {qspi_quad_capture[27:0], qspi_io};
                qspi_quad_groups = qspi_quad_groups + 1;
            end
        end
    end

    task axi_read;
        input [31:0] addr;
        input [31:0] expected;
        integer guard;
        begin
            @(negedge clk); s_araddr = addr; s_arvalid = 1'b1;
            guard = 0;
            while (!s_arready && guard < 40) begin @(posedge clk); guard = guard + 1; end
            @(negedge clk); s_arvalid = 1'b0;
            guard = 0;
            while (!s_rvalid && guard < 40) begin @(posedge clk); guard = guard + 1; end
            if (!s_rvalid || s_rresp !== 2'b00 || s_rdata !== expected) begin
                $display("FAIL: read %h got=%h resp=%b expected=%h", addr, s_rdata, s_rresp, expected);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        integer guard;
        begin
            @(negedge clk); s_awaddr = addr; s_wdata = data; s_awvalid = 1'b1; s_wvalid = 1'b1;
            guard = 0;
            while (!(s_awready && s_wready) && guard < 40) begin @(posedge clk); guard = guard + 1; end
            @(negedge clk); s_awvalid = 1'b0; s_wvalid = 1'b0;
            guard = 0;
            while (!s_bvalid && guard < 40) begin @(posedge clk); guard = guard + 1; end
            if (!s_bvalid || s_bresp !== 2'b00) begin
                $display("FAIL: write %h resp=%b", addr, s_bresp);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    task axi_read_capture;
        input [31:0] addr;
        output [31:0] data;
        integer guard;
        begin
            @(negedge clk); s_araddr = addr; s_arvalid = 1'b1;
            guard = 0;
            while (!s_arready && guard < 40) begin @(posedge clk); guard = guard + 1; end
            @(negedge clk); s_arvalid = 1'b0;
            guard = 0;
            while (!s_rvalid && guard < 40) begin @(posedge clk); guard = guard + 1; end
            data = s_rdata;
            if (!s_rvalid || s_rresp !== 2'b00) begin
                $display("FAIL: capture read %h resp=%b", addr, s_rresp);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        axi_read(32'h4000_5000, 32'h5153_5001);
        axi_read(32'h4000_5004, 32'h0000_0002);

        // A normal downstream acceptance/response must not set the fault
        // record before the deliberately stalled transaction below.
        g_m_arready = 1'b1;
        @(negedge clk); g_s_arvalid = 1'b1;
        while (!g_s_arready) @(posedge clk);
        while (!g_m_arvalid) @(posedge clk);
        @(negedge clk); g_m_rvalid = 1'b1; g_m_rdata = 32'h1234_5678;
        while (!g_s_rvalid) @(posedge clk);
        if (g_s_rresp !== 2'b00 || g_s_rdata !== 32'h1234_5678) begin
            $display("FAIL: normal guard read did not complete cleanly");
            errors = errors + 1;
        end
        @(negedge clk); g_s_arvalid = 1'b0; g_m_rvalid = 1'b0; g_m_arready = 1'b0;
        axi_read(32'h4000_5004, 32'h0000_0002);

        // A downstream AR stall must trip the real guard and set status.
        @(negedge clk); g_s_arvalid = 1'b1;
        while (!g_s_arready) @(posedge clk);
        @(negedge clk); g_s_arvalid = 1'b0;
        while (!g_s_rvalid) @(posedge clk);
        if (g_s_rresp !== 2'b10 || !timeout_sticky) begin
            $display("FAIL: guard did not produce sticky SLVERR timeout");
            errors = errors + 1;
        end
        @(negedge clk);

        axi_read(32'h4000_5004, 32'h0000_0003);
        axi_read(32'h4000_5008, 32'h0001_0001);
        axi_write(32'h4000_500C, 32'h1);
        axi_read(32'h4000_5004, 32'h0000_0002);
        axi_read(32'h4000_5008, 32'h0000_0000);

        // Command controller window: legacy status remains at +0x00, while
        // command-controller registers are exposed at +0x20.
        axi_write(32'h4000_5020, 32'h1);          // CTRL.enable
        axi_write(32'h4000_5040, 32'h0000_0006); // LUT0: Write Enable
        axi_write(32'h4000_5128, 32'h0);          // CMD_DATA_LEN = 0
        axi_write(32'h4000_5120, 32'h0);          // CMD_TRIGGER LUT0
        qspi_guard = 0;
        while (qspi_guard < 80) begin
            axi_read_capture(32'h4000_5024, rd_value);
            if (!rd_value[0])
                qspi_guard = 80;
            else
                qspi_guard = qspi_guard + 1;
        end
        if (!qspi_cs_seen || qspi_sclk_edges == 0 || qspi_cmd_bits < 8 ||
            qspi_cmd_capture !== 8'h06) begin
            $display("FAIL: APB QSPI command pins cs=%b edges=%0d bits=%0d cmd=%h",
                     qspi_cs_seen, qspi_sclk_edges, qspi_cmd_bits,
                     qspi_cmd_capture);
            errors = errors + 1;
        end
        axi_read_capture(32'h4000_5024, rd_value);
        if (rd_value !== 32'h0000_000C) begin
            $display("FAIL: QSPI command status got=%h expected=0000000c", rd_value);
            errors = errors + 1;
        end
        axi_write(32'h4000_5034, 32'h1);          // command IRQ_STATUS W1C
        axi_read_capture(32'h4000_5024, rd_value);
        if (rd_value !== 32'h0000_0004) begin
            $display("FAIL: QSPI command IRQ W1C got=%h expected=00000004", rd_value);
            errors = errors + 1;
        end

        // Integrated four-lane read: command/address remain x1 while the
        // data phase samples two external nibbles from qspi_io[3:0].
        axi_write(32'h4000_5020, 32'h1);          // CTRL.enable
        axi_write(32'h4000_5040, 32'h0080_0005); // LUT0: x4 data, status read
        axi_write(32'h4000_5128, 32'd1);         // one RX byte
        axi_write(32'h4000_5120, 32'h0);         // trigger LUT0
        qspi_guard = 0;
        while (qspi_guard < 80) begin
            axi_read_capture(32'h4000_5024, rd_value);
            if (!rd_value[0])
                qspi_guard = 80;
            else
                qspi_guard = qspi_guard + 1;
        end
        axi_read_capture(32'h4000_5134, rd_value); // RX_DATA
        if (rd_value[7:0] !== 8'hc3) begin
            $display("FAIL: integrated x4 read got=%h expected=000000c3", rd_value);
            errors = errors + 1;
        end
        axi_write(32'h4000_5034, 32'h7);         // clear done/timeout/abort

        // Integrated four-lane write: capture eight data nibbles after the
        // x1 command/address phase and verify direction/data ordering.
        qspi_quad_groups = 0;
        qspi_quad_capture = 32'h0;
        axi_write(32'h4000_5044, (2 << 22) | (1 << 17) | (1 << 8) | 32'h32);
        axi_write(32'h4000_5124, 32'h0012_3456);
        axi_write(32'h4000_5128, 32'd4);
        axi_write(32'h4000_5130, 32'hA1B2_C3D4);
        axi_write(32'h4000_5120, 32'h1);         // trigger LUT1
        qspi_guard = 0;
        while (qspi_guard < 100) begin
            axi_read_capture(32'h4000_5024, rd_value);
            if (!rd_value[0])
                qspi_guard = 100;
            else
                qspi_guard = qspi_guard + 1;
        end
        if (qspi_quad_groups !== 8 || qspi_quad_capture !== 32'hA1B2_C3D4) begin
            $display("FAIL: integrated x4 write groups=%0d data=%h expected groups=8 data=A1B2C3D4",
                     qspi_quad_groups, qspi_quad_capture);
            errors = errors + 1;
        end
        axi_write(32'h4000_5034, 32'h7);

        // The integrated command window must bound a stalled command and
        // expose the timeout event without leaving the shared pins asserted.
        axi_write(32'h4000_5028, 32'h0000_FFFF); // CLK_DIV
        axi_write(32'h4000_5038, 32'd4);         // command timeout
        axi_write(32'h4000_5040, 32'h0000_0005); // status-read opcode
        axi_write(32'h4000_5128, 32'd1);         // one RX byte
        axi_write(32'h4000_5120, 32'h0);         // trigger LUT0
        qspi_guard = 0;
        while (qspi_active && qspi_guard < 40) begin
            @(posedge clk);
            qspi_guard = qspi_guard + 1;
        end
        axi_read_capture(32'h4000_5024, rd_value);
        if (rd_value[0] || !rd_value[3] || !rd_value[4] ||
            !rd_value[5] || rd_value[6] || !spi_cs_n || spi_sclk) begin
            $display("FAIL: integrated QSPI timeout status=%h active=%b cs_n=%b sclk=%b",
                     rd_value, qspi_active, spi_cs_n, spi_sclk);
            errors = errors + 1;
        end
        axi_write(32'h4000_5034, 32'h7);         // W1C done/timeout/abort

        // Arm the always-on watchdog while a command owns the pins.  The WDT
        // reset must cancel the command at the peripheral reset boundary and
        // leave the sticky WDT cause readable after restart.
        axi_write(32'h4000_5028, 32'h0000_FFFF);
        axi_write(32'h4000_5038, 32'd1000);
        axi_write(32'h4000_5020, 32'h1);
        axi_write(32'h4000_5128, 32'd1);
        axi_write(32'h4000_5120, 32'h0);
        qspi_guard = 0;
        while (!qspi_active && qspi_guard < 20) begin
            @(posedge clk);
            qspi_guard = qspi_guard + 1;
        end
        if (!qspi_active) begin
            $display("FAIL: QSPI command was not active before WDT reset");
            errors = errors + 1;
        end
        axi_write(32'h4000_7004, 32'd5);         // WDT load
        axi_write(32'h4000_7000, 32'h1);         // arm
        qspi_guard = 0;
        while (!wdt_reset && qspi_guard < 30) begin
            @(posedge clk);
            qspi_guard = qspi_guard + 1;
        end
        if (!wdt_reset || qspi_active || !spi_cs_n || spi_sclk) begin
            $display("FAIL: WDT reset did not cancel QSPI command reset=%b active=%b cs_n=%b sclk=%b",
                     wdt_reset, qspi_active, spi_cs_n, spi_sclk);
            errors = errors + 1;
        end
        repeat (3) @(posedge clk);
        axi_read_capture(32'h4000_5024, rd_value);
        if (rd_value[0] || rd_value[3] || rd_value[4] ||
            rd_value[5] || rd_value[6]) begin
            $display("FAIL: QSPI command status was not reset after WDT: %h", rd_value);
            errors = errors + 1;
        end
        axi_read(32'h4000_7010, 32'h0000_0001); // sticky WDT expiry

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS qspi_status_integration");
        else
            $display("REGRESSION_TEST_FAILED qspi_status_integration errors=%0d", errors);
        $finish;
    end
endmodule
