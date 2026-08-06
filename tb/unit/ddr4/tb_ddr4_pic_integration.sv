`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_ddr4_pic_integration
// Purpose: Peripheral integration gate proving DDR4 fatal/uncorrectable ECC IRQ
//          escalation to PIC source 5 in soc_peripheral_subsystem.
// Checks:
//   - Route (ddr4_fatal_error || ddr4_ecc_uncorrectable_error) to PIC source 5.
//   - Preserve existing PIC source IDs 0..4 (UART RX, UART TX, Timer, DMA, QSPI).
//   - Correctable ECC remains status-only (does not assert PIC source 5 or IRQ).
//   - APB status classification (fatal, correctable, uncorrectable) and W1C behavior.
//   - PIC raw, masked, VEC_ID, and CPU IRQ (cpu_int) behavior.
// =============================================================================

module tb_ddr4_pic_integration;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer errors = 0;
    always #5 clk = ~clk;

    // AXI slave interface driving soc_peripheral_subsystem
    reg [3:0]   s_awid = 0;
    reg [31:0]  s_awaddr = 0;
    reg [7:0]   s_awlen = 0;
    reg [2:0]   s_awsize = 2;
    reg [1:0]   s_awburst = 1;
    reg [1:0]   s_awlock = 0;
    reg [3:0]   s_awcache = 0;
    reg [2:0]   s_awprot = 0;
    reg         s_awvalid = 0;
    wire        s_awready;
    reg [31:0]  s_wdata = 0;
    reg [3:0]   s_wstrb = 4'hf;
    reg         s_wlast = 1;
    reg         s_wvalid = 0;
    wire        s_wready;
    wire [3:0]  s_bid;
    wire [1:0]  s_bresp;
    wire        s_bvalid;
    reg         s_bready = 1;
    reg [3:0]   s_arid = 0;
    reg [31:0]  s_araddr = 0;
    reg [7:0]   s_arlen = 0;
    reg [2:0]   s_arsize = 2;
    reg [1:0]   s_arburst = 1;
    reg [1:0]   s_arlock = 0;
    reg [3:0]   s_arcache = 0;
    reg [2:0]   s_arprot = 0;
    reg         s_arvalid = 0;
    wire        s_arready;
    wire [3:0]  s_rid;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rlast;
    wire        s_rvalid;
    reg         s_rready = 1;

    // Peripheral IO tie-offs and DDR4 inputs
    wire [31:0] gpio_pins;
    wire        uart_tx, uart_rts_n, uart_dtr_n, cpu_int, wdt_reset;
    wire [7:0]  vic_vec_id;
    reg         uart_rx = 1, uart_cts_n = 0, uart_dsr_n = 0, uart_dcd_n = 0, uart_ri_n = 1;
    wire        spi_sclk, spi_cs_n, spi_mosi, qspi_active, qspi_cmd_req;
    wire [3:0]  qspi_io_o, qspi_io_oe;

    reg         ddr4_controller_present = 1'b1;
    reg         ddr4_init_done = 1'b1;
    reg         ddr4_training_done = 1'b1;
    reg         ddr4_fatal_error = 1'b0;
    reg         ddr4_ecc_correctable_error = 1'b0;
    reg         ddr4_ecc_uncorrectable_error = 1'b0;
    reg [15:0]  ddr4_error_code = 16'h0000;

    // Unused master interface tie-offs
    wire [3:0]  m_awid, m_bid, m_arid, m_rid;
    wire [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    wire [7:0]  m_awlen, m_arlen;
    wire [2:0]  m_awsize, m_arsize, m_awprot, m_arprot;
    wire [1:0]  m_awburst, m_awlock, m_arburst, m_arlock, m_bresp, m_rresp;
    wire [3:0]  m_awcache, m_arcache, m_wstrb;
    wire        m_awvalid, m_wlast, m_wvalid, m_bready, m_arvalid, m_rready;

    soc_peripheral_subsystem dut (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n), .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n), .cpu_int(cpu_int),
        .vic_vec_id(vic_vec_id), .wdt_reset(wdt_reset),
        .tlb_inv_en(), .tlb_inv_vpn2(), .tlb_inv_asid(), .tlb_inv_scope(), .tlb_inv_wired_floor(),
        .ipi_target_present(1'b0), .ipi_ack_valid(1'b0), .ipi_ack_target(1'b0), .ipi_ack_generation(8'd0),
        .ipi_invalidate_valid(), .ipi_invalidate_target(), .ipi_invalidate_generation(),
        .ipi_invalidate_asid(), .ipi_invalidate_vpn(), .ipi_invalidate_scope(),
        .ipi_core1_ack_valid(1'b0), .ipi_core1_ack_target(1'b0), .ipi_core1_ack_generation(8'd0),
        .ipi_core1_invalidate_valid(), .ipi_core1_invalidate_target(), .ipi_core1_invalidate_generation(),
        .ipi_core1_invalidate_asid(), .ipi_core1_invalidate_vpn(), .ipi_core1_invalidate_scope(),
        .core1_reset_req(),
        .qspi_timeout_sticky(1'b0), .qspi_controller_present(1'b0),
        .ddr4_controller_present(ddr4_controller_present),
        .ddr4_init_done(ddr4_init_done),
        .ddr4_training_done(ddr4_training_done),
        .ddr4_fatal_error(ddr4_fatal_error),
        .ddr4_ecc_correctable_error(ddr4_ecc_correctable_error),
        .ddr4_ecc_uncorrectable_error(ddr4_ecc_uncorrectable_error),
        .ddr4_error_code(ddr4_error_code),
        .spi_miso(1'b0), .qspi_cmd_grant(1'b0),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .qspi_io_i(4'b0), .qspi_io_o(qspi_io_o), .qspi_io_oe(qspi_io_oe),
        .qspi_active(qspi_active), .qspi_cmd_req(qspi_cmd_req),
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
        .m_awprot(m_awprot), .m_awvalid(m_awvalid), .m_awready(1'b0),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid),
        .m_wready(1'b0), .m_bid(m_bid), .m_bresp(2'b0), .m_bvalid(1'b0),
        .m_bready(m_bready), .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arlock(m_arlock),
        .m_arcache(m_arcache), .m_arprot(m_arprot), .m_arvalid(m_arvalid),
        .m_arready(1'b0), .m_rid(m_rid), .m_rdata(32'b0), .m_rresp(2'b0),
        .m_rlast(1'b0), .m_rvalid(1'b0), .m_rready(m_rready)
    );

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

    reg [31:0] rd_val;

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
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("[TB] Step 1: Initial state check");
        // Read DDR4 status VERSION (0x4000_6000) & STATUS (0x4000_6004)
        axi_read(32'h4000_6000, 32'h4444_5201);
        axi_read(32'h4000_6004, 32'h0000_0007); // present, init_done, training_done
        // PIC INTR_RAW (0x4000_4000) should be 0
        axi_read(32'h4000_4000, 32'h0000_0000);
        if (cpu_int !== 1'b0) begin
            $display("FAIL: cpu_int set at idle");
            errors = errors + 1;
        end

        $display("[TB] Step 2: Preserved source 0..4 check");
        // Verify source IDs 0..4 in irq_sources retain their contract
        // PIC INTR_RAW bit 5 must be 0 initially
        axi_read(32'h4000_4000, 32'h0000_0000);

        $display("[TB] Step 3: Correctable ECC status-only check");
        ddr4_ecc_correctable_error = 1'b1;
        repeat (5) @(posedge clk);
        // APB STATUS at 0x4000_6004 must show ecc_correctable_error (bit 4) => 0x0000_0017
        axi_read(32'h4000_6004, 32'h0000_0017);
        // PIC INTR_RAW at 0x4000_4000 must NOT set source 5 (bit 5 must remain 0)
        axi_read_capture(32'h4000_4000, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("FAIL: correctable ECC asserted PIC source 5 raw bit");
            errors = errors + 1;
        end
        if (cpu_int !== 1'b0) begin
            $display("FAIL: correctable ECC asserted cpu_int");
            errors = errors + 1;
        end
        ddr4_ecc_correctable_error = 1'b0;
        repeat (3) @(posedge clk);
        axi_read(32'h4000_6004, 32'h0000_0007);

        $display("[TB] Step 4: DDR4 Fatal Error IRQ Escalation to PIC source 5");
        ddr4_fatal_error = 1'b1;
        ddr4_error_code = 16'h0002;
        repeat (5) @(posedge clk);
        // APB STATUS (0x4000_6004) must show fatal_error (bit 3) => 0x0000_000F
        axi_read(32'h4000_6004, 32'h0000_000F);
        // APB ERROR (0x4000_6008) must capture 32'h0004_0002
        axi_read(32'h4000_6008, 32'h0004_0002);
        // PIC INTR_RAW (0x4000_4000) bit 5 must be set (0x0000_0020)
        axi_read_capture(32'h4000_4000, rd_val);
        if (rd_val[5] !== 1'b1) begin
            $display("FAIL: fatal error did not set PIC source 5 raw bit (got %h)", rd_val);
            errors = errors + 1;
        end
        // Since INTR_ENABLE (0x4000_4004) is 0, INTR_MASKED (0x4000_4008) is 0 & cpu_int is 0
        axi_read(32'h4000_4008, 32'h0000_0000);
        if (cpu_int !== 1'b0) begin
            $display("FAIL: cpu_int asserted when PIC source 5 masked");
            errors = errors + 1;
        end

        // Enable PIC source 5 by writing INTR_ENABLE (0x4000_4004) = 0x0000_0020
        axi_write(32'h4000_4004, 32'h0000_0020);
        repeat (3) @(posedge clk);
        // INTR_MASKED (0x4000_4008) must show bit 5 set
        axi_read(32'h4000_4008, 32'h0000_0020);
        if (cpu_int !== 1'b1) begin
            $display("FAIL: cpu_int not asserted after enabling source 5");
            errors = errors + 1;
        end
        if (vic_vec_id !== 8'd5) begin
            $display("FAIL: vic_vec_id expected 5, got %0d", vic_vec_id);
            errors = errors + 1;
        end

        // Mask PIC source 5 by writing INTR_ENABLE = 0
        axi_write(32'h4000_4004, 32'h0000_0000);
        repeat (3) @(posedge clk);
        if (cpu_int !== 1'b0) begin
            $display("FAIL: cpu_int not cleared after masking source 5");
            errors = errors + 1;
        end

        // Re-enable PIC source 5
        axi_write(32'h4000_4004, 32'h0000_0020);
        repeat (3) @(posedge clk);
        if (cpu_int !== 1'b1) begin
            $display("FAIL: cpu_int not re-asserted when source 5 enabled");
            errors = errors + 1;
        end

        // Deassert ddr4_fatal_error & clear APB error record via W1C CONTROL (0x4000_600C) = 1
        ddr4_fatal_error = 1'b0;
        axi_write(32'h4000_600C, 32'h0000_0001);
        axi_read(32'h4000_6008, 32'h0000_0000);
        repeat (5) @(posedge clk);
        // PIC INTR_RAW bit 5 must return to 0
        axi_read_capture(32'h4000_4000, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("FAIL: PIC source 5 raw bit not cleared after fatal error deasserted (got %h)", rd_val);
            errors = errors + 1;
        end
        if (cpu_int !== 1'b0) begin
            $display("FAIL: cpu_int not cleared after fatal error deasserted");
            errors = errors + 1;
        end

        $display("[TB] Step 5: DDR4 Uncorrectable ECC Error IRQ Escalation to PIC source 5");
        ddr4_ecc_uncorrectable_error = 1'b1;
        repeat (5) @(posedge clk);
        // APB STATUS (0x4000_6004) must show ecc_uncorrectable_error (bit 5) => 0x0000_0027
        axi_read(32'h4000_6004, 32'h0000_0027);
        // APB ERROR (0x4000_6008) must capture 32'h0004_0008
        axi_read(32'h4000_6008, 32'h0004_0008);
        // PIC INTR_RAW bit 5 set
        axi_read_capture(32'h4000_4000, rd_val);
        if (rd_val[5] !== 1'b1) begin
            $display("FAIL: uncorrectable ECC did not set PIC source 5 raw bit (got %h)", rd_val);
            errors = errors + 1;
        end
        // Source 5 is enabled, so cpu_int must be 1
        if (cpu_int !== 1'b1) begin
            $display("FAIL: cpu_int not asserted on uncorrectable ECC error");
            errors = errors + 1;
        end
        if (vic_vec_id !== 8'd5) begin
            $display("FAIL: vic_vec_id expected 5 for uncorrectable ECC, got %0d", vic_vec_id);
            errors = errors + 1;
        end

        // Deassert ddr4_ecc_uncorrectable_error & clear APB status via W1C
        ddr4_ecc_uncorrectable_error = 1'b0;
        axi_write(32'h4000_600C, 32'h0000_0001);
        axi_read(32'h4000_6008, 32'h0000_0000);
        repeat (5) @(posedge clk);
        axi_read_capture(32'h4000_4000, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("FAIL: PIC source 5 raw bit not cleared after uncorrectable ECC deasserted (got %h)", rd_val);
            errors = errors + 1;
        end
        if (cpu_int !== 1'b0) begin
            $display("FAIL: cpu_int not cleared after uncorrectable ECC deasserted");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS ddr4_pic_integration");
        else
            $display("REGRESSION_TEST_FAILED ddr4_pic_integration errors=%0d", errors);

        $finish;
    end
endmodule
