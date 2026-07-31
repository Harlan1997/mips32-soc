`timescale 1ns/1ps
`include "soc_config.vh"

module tb_fetch_pc_alignment;
    localparam [31:0] RESET_PC = (`SOC_PRODUCT_BOOT_ENABLE != 0) ?
                                 32'hBFC0_0000 : 32'h0000_0000;
    localparam [31:0] RESET_AR = (`SOC_PRODUCT_BOOT_ENABLE != 0) ?
                                 32'h1FC0_0000 : 32'h0000_0000;
    localparam [31:0] TARGET_PC = RESET_PC + 32'h0000_0010;

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
    wire [31:0] gpio_pins;
    reg [1023:0] sram_hex;

    integer cycles;
    reg reset_pc_seen;
    reg reset_ar_seen;
    reg branch_seen;
    reg delay_slot_seen;
    reg t0_write_seen;
    reg t1_write_seen;

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

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED fetch_pc_alignment");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles         = 0;
            reset_pc_seen  = 1'b0;
            reset_ar_seen  = 1'b0;
            branch_seen    = 1'b0;
            delay_slot_seen = 1'b0;
            t0_write_seen  = 1'b0;
            t1_write_seen  = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == RESET_PC)
                reset_pc_seen = 1'b1;

            if (!reset_ar_seen && u_soc.u_impl.m0_arvalid && u_soc.u_impl.m0_arready) begin
                reset_ar_seen = 1'b1;
                if (u_soc.u_impl.m0_araddr !== RESET_AR)
                    fail("first I-cache refill did not use the reset instruction address");
            end

            // The ROM/SRAM program is:
            //   addiu $t0, $zero, 1
            //   bne   $t0, $zero, reset+0x10
            //   addiu $t1, $zero, 0x55   (delay slot)
            // A response-PC shift by one word redirects the branch to +0x14.
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h1500_0002 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_pc_plus_4 == RESET_PC + 32'h0000_0008)
                branch_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h2409_0055 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_pc_plus_4 == RESET_PC + 32'h0000_000C)
                delay_slot_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr == 5'd8 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata == 32'h0000_0001)
                t0_write_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr == 5'd9 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata == 32'h0000_0055)
                t1_write_seen = 1'b1;

            if (reset_pc_seen && reset_ar_seen && branch_seen && delay_slot_seen &&
                t0_write_seen && t1_write_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == TARGET_PC) begin
                $display("REGRESSION_TEST_SUCCESS fetch_pc_alignment");
                $finish;
            end

            if (cycles > 500)
                fail("did not complete the reset-branch fetch and execution sequence");
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        spi_miso = 1'b0;
        sram_hex = "";

        if (`SOC_PRODUCT_BOOT_ENABLE == 0) begin
            if (!$value$plusargs("SRAM_HEX=%s", sram_hex))
                fail("SRAM_HEX is required for the prototype fetch test");
            u_soc.preload_sram_hex(sram_hex);
        end

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
