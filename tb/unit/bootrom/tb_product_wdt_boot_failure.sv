`timescale 1ns/1ps
`include "soc_config.vh"

module tb_product_wdt_boot_failure;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg tck = 1'b0;
    reg tms = 1'b1;
    reg tdi = 1'b0;
    wire tdo;
    wire spi_sclk, spi_cs_n, spi_mosi;
    wire [31:0] gpio_pins;
    integer cycles = 0;
    integer reset_count = 0;
    reg reset_seen = 1'b0;
    reg stage_write_seen = 1'b0;
    reg failure_write_seen = 1'b0;
    reg cause_read_seen = 1'b0;
    reg pass_seen = 1'b0;
    reg fail_seen = 1'b0;
    reg [4095:0] boot_hex;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate

    mips_soc #(.ENABLE_UART_PINS(1'b0)) u_soc (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(1'b0),
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
        end else begin
            cycles <= cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000) begin
                reset_seen <= 1'b1;
                reset_count <= reset_count + 1;
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) begin
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hC000_8000)
                        stage_write_seen <= 1'b1;
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hC000_8004)
                        failure_write_seen <= 1'b1;
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                        if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_BEEF)
                            pass_seen <= 1'b1;
                        else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_DEAD)
                            fail_seen <= 1'b1;
                    end
                end else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hC000_8008) begin
                    cause_read_seen <= 1'b1;
                end
            end
            if (fail_seen) begin
                $display("REGRESSION_TEST_FAILED product_wdt_boot_failure");
                $finish;
            end
            if (pass_seen) begin
                if (!reset_seen || reset_count < 2 || !stage_write_seen ||
                    !failure_write_seen || !cause_read_seen) begin
                    $display("ERROR: missing reset/status evidence reset_count=%0d stage=%b failure=%b cause_read=%b",
                             reset_count, stage_write_seen, failure_write_seen, cause_read_seen);
                    $display("REGRESSION_TEST_FAILED product_wdt_boot_failure");
                end else begin
                    $display("REGRESSION_TEST_SUCCESS product_wdt_boot_failure");
                end
                $finish;
            end
            if (cycles > 30000) begin
                $display("ERROR: Boot ROM watchdog failure gate timeout pc=%h status=%h cause=%h badv=%h epc=%h ctrl=%b val=%h expired=%b reset=%b",
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                         u_soc.u_impl.u_peripheral_subsystem.u_apb_wdt.ctrl_en,
                         u_soc.u_impl.u_peripheral_subsystem.u_apb_wdt.val_r,
                         u_soc.u_impl.u_peripheral_subsystem.u_apb_wdt.expired_r,
                         u_soc.u_impl.wdt_reset);
                $display("REGRESSION_TEST_FAILED product_wdt_boot_failure");
                $finish;
            end
        end
    end

    initial begin
        if (!$value$plusargs("BOOT_ROM_HEX=%s", boot_hex)) begin
            // The ROM model reads the same plusarg; this branch only supplies a
            // clear diagnostic before the simulation starts.
            $display("ERROR: BOOT_ROM_HEX is required");
            $finish;
        end
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
