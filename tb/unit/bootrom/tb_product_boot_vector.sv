`timescale 1ns/1ps

module tb_product_boot_vector;
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

    integer cycles;
    reg reset_state_seen;
    reg reset_fetch_seen;
    reg bootstrap_exception_seen;
    reg bootstrap_vector_pc_seen;
    reg bootstrap_vector_fetch_seen;
    reg ebase_mode_seen;
    reg ebase_vector_pc_seen;
    reg ebase_vector_fetch_seen;

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
            $display("REGRESSION_TEST_FAILED product_boot_vector");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_state_seen = 1'b0;
            reset_fetch_seen = 1'b0;
            bootstrap_exception_seen = 1'b0;
            bootstrap_vector_pc_seen = 1'b0;
            bootstrap_vector_fetch_seen = 1'b0;
            ebase_mode_seen = 1'b0;
            ebase_vector_pc_seen = 1'b0;
            ebase_vector_fetch_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (!reset_state_seen) begin
                reset_state_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] !== 1'b1)
                    fail("product reset did not set Status.BEV");
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] !== 1'b1)
                    fail("product reset did not set Status.ERL");
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.ebase_out !== 32'h8000_0000)
                    fail("product reset did not initialize EBase to 80000000");
            end

            if (!reset_fetch_seen && u_soc.u_impl.m0_arvalid && u_soc.u_impl.m0_arready) begin
                reset_fetch_seen = 1'b1;
                if (u_soc.u_impl.m0_araddr !== 32'h1FC0_0000)
                    fail("first I-cache fill was not the Boot ROM reset vector");
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1] && !bootstrap_exception_seen)
                bootstrap_exception_seen = 1'b1;

            if (bootstrap_exception_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0380)
                bootstrap_vector_pc_seen = 1'b1;

            if (bootstrap_exception_seen && u_soc.u_impl.m0_arvalid && u_soc.u_impl.m0_arready &&
                u_soc.u_impl.m0_araddr == 32'h1FC0_0380) begin
                if (!(u_soc.u_impl.s4_arvalid && u_soc.u_impl.s4_arready))
                    fail("bootstrap exception fetch was not accepted by Boot ROM S4");
                bootstrap_vector_fetch_seen = 1'b1;
            end

            // The bootstrap vector clears Status to leave BEV/ERL/EXL before
            // its second syscall. That exception must use EBase, not Boot ROM.
            if (bootstrap_vector_fetch_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1] == 1'b0)
                ebase_mode_seen = 1'b1;

            if (ebase_mode_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0180)
                ebase_vector_pc_seen = 1'b1;

            if (ebase_mode_seen && u_soc.u_impl.m0_arvalid && u_soc.u_impl.m0_arready &&
                u_soc.u_impl.m0_araddr == 32'h0000_0180) begin
                if (!(u_soc.u_impl.s0_arvalid && u_soc.u_impl.s0_arready))
                    fail("EBase exception fetch was not accepted by SRAM S0");
                ebase_vector_fetch_seen = 1'b1;
            end

            if (reset_state_seen && reset_fetch_seen && bootstrap_exception_seen &&
                bootstrap_vector_pc_seen && bootstrap_vector_fetch_seen &&
                ebase_mode_seen && ebase_vector_pc_seen && ebase_vector_fetch_seen) begin
                $display("REGRESSION_TEST_SUCCESS product_boot_vector");
                $finish;
            end

            if (cycles > 1500) begin
                if (!reset_fetch_seen)
                    $display("ERROR: reset vector was never fetched");
                if (!bootstrap_exception_seen)
                    $display("ERROR: ROM syscall never raised an exception");
                if (!bootstrap_vector_pc_seen)
                    $display("ERROR: PC never reached bootstrap general-exception vector");
                if (!bootstrap_vector_fetch_seen)
                    $display("ERROR: bootstrap general-exception vector was never fetched from ROM");
                if (!ebase_mode_seen)
                    $display("ERROR: bootstrap vector never cleared BEV/ERL/EXL");
                if (!ebase_vector_pc_seen)
                    $display("ERROR: PC never reached EBase general-exception vector");
                if (!ebase_vector_fetch_seen)
                    $display("ERROR: EBase general-exception vector was never fetched from SRAM");
                $display("REGRESSION_TEST_FAILED product_boot_vector");
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
        reset_state_seen = 1'b0;
        reset_fetch_seen = 1'b0;
        bootstrap_exception_seen = 1'b0;
        bootstrap_vector_pc_seen = 1'b0;
        bootstrap_vector_fetch_seen = 1'b0;
        ebase_mode_seen = 1'b0;
        ebase_vector_pc_seen = 1'b0;
        ebase_vector_fetch_seen = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
