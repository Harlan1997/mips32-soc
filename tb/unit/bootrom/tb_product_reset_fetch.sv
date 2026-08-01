`timescale 1ns/1ps

module tb_product_reset_fetch;
    reg clk;
    reg rst_n;
    reg tck;
    reg tms;
    reg tdi;
    reg spi_miso;
    wire tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire uart_tx, uart_rts_n, uart_dtr_n;
    wire uart_rx = 1'b1;
    wire uart_cts_n = 1'b1;
    wire uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1;
    wire uart_ri_n = 1'b1;
    wire [31:0] gpio_pins;

    integer cycles;
    reg pc_seen;
    reg bootrom_ar_seen;
    reg bootrom_accept_seen;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate

    mips_soc u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n),
        .uart_dsr_n(uart_dsr_n),
        .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n),
        .uart_ri_n (uart_ri_n),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo)
    );

    always #5 clk = ~clk;

    // Sample AXI at the clock edge at which the request is accepted.  Only
    // the first I-cache AR transaction is the reset-vector evidence; later
    // line fills are normal execution and must not affect this test.
    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            pc_seen = 1'b0;
            bootrom_ar_seen = 1'b0;
            bootrom_accept_seen = 1'b0;
        end else begin
            cycles = cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                pc_seen = 1'b1;

            if (!bootrom_ar_seen && u_soc.u_impl.m0_arvalid && u_soc.u_impl.m0_arready) begin
                bootrom_ar_seen = 1'b1;
                if (u_soc.u_impl.m0_araddr !== 32'h1FC0_0000) begin
                    $display("ERROR: first product I$ AR address was %h", u_soc.u_impl.m0_araddr);
                    $display("REGRESSION_TEST_FAILED product_reset_fetch");
                    $finish;
                end
                // m0_arready is asserted by the crossbar only when the
                // decoded S4 slave accepts this exact AR transaction.
                if (!(u_soc.u_impl.s4_arvalid && u_soc.u_impl.s4_arready)) begin
                    $display("ERROR: reset-vector AR was not accepted by Boot ROM S4");
                    $display("REGRESSION_TEST_FAILED product_reset_fetch");
                    $finish;
                end
                bootrom_accept_seen = 1'b1;
            end

            if (pc_seen && bootrom_ar_seen && bootrom_accept_seen) begin
                $display("REGRESSION_TEST_SUCCESS product_reset_fetch");
                $finish;
            end

            if (cycles > 1000) begin
                if (!pc_seen)
                    $display("ERROR: product reset PC never reached BFC0_0000");
                if (!bootrom_ar_seen)
                    $display("ERROR: product I$ never issued an AR transaction");
                if (!bootrom_accept_seen)
                    $display("ERROR: Boot ROM never accepted the reset-vector request");
                $display("REGRESSION_TEST_FAILED product_reset_fetch");
                $finish;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        spi_miso = 1'b0;
        cycles = 0;
        pc_seen = 1'b0;
        bootrom_ar_seen = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
