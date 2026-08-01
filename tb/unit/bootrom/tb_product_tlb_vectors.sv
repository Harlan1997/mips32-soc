`timescale 1ns/1ps

// Product MMU vector contract: exercise both causes that share TLBL/TLBS.
// The ROM first sends an unmapped fetch to the BEV refill vector, installs a
// matching invalid entry, and retries it. The general handler clears BEV/EXL
// and sends a second unmapped fetch through the EBase refill/general pair.
module tb_product_tlb_vectors;
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

    reg [1023:0] sram_hex;
    integer cycles;
    reg bev_refill_seen;
    reg bev_refill_fetch_seen;
    reg bev_invalid_seen;
    reg bev_general_fetch_seen;
    reg ebase_mode_seen;
    reg ebase_refill_seen;
    reg ebase_refill_fetch_seen;
    reg ebase_invalid_seen;
    reg ebase_general_fetch_seen;

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

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            bev_refill_seen = 1'b0;
            bev_refill_fetch_seen = 1'b0;
            bev_invalid_seen = 1'b0;
            bev_general_fetch_seen = 1'b0;
            ebase_mode_seen = 1'b0;
            ebase_refill_seen = 1'b0;
            ebase_refill_fetch_seen = 1'b0;
            ebase_invalid_seen = 1'b0;
            ebase_general_fetch_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            // A hit with V=0 is deliberately kept separate from a true miss.
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr == 32'h0000_0000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_ok) begin
                if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_hit)
                    bev_refill_seen = 1'b1;
                else if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_v)
                    bev_invalid_seen = 1'b1;
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0200)
                bev_refill_fetch_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0380)
                bev_general_fetch_seen = 1'b1;

            // The ROM general handler clears BEV/ERL/EXL before the second
            // useg jump, so the next miss must use EBase rather than Boot ROM.
            if (!ebase_mode_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1] == 1'b0)
                ebase_mode_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr == 32'h0000_2000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_ok) begin
                if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_hit)
                    ebase_refill_seen = 1'b1;
                else if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_v)
                    ebase_invalid_seen = 1'b1;
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0000)
                ebase_refill_fetch_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0180)
                ebase_general_fetch_seen = 1'b1;

            if (bev_refill_seen && bev_refill_fetch_seen && bev_invalid_seen &&
                bev_general_fetch_seen && ebase_mode_seen && ebase_refill_seen &&
                ebase_refill_fetch_seen && ebase_invalid_seen && ebase_general_fetch_seen) begin
                $display("REGRESSION_TEST_SUCCESS product_tlb_vectors");
                $finish;
            end

            if (cycles > 4000) begin
                $display("DEBUG: pc=%h if_va=%h i_ok=%b i_hit=%b i_v=%b status=%h",
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_ok,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_hit,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_v,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status);
                if (!bev_refill_seen) $display("ERROR: BEV miss was not classified as refill");
                if (!bev_refill_fetch_seen) $display("ERROR: BEV refill vector was not fetched");
                if (!bev_invalid_seen) $display("ERROR: BEV invalid was not classified as invalid");
                if (!bev_general_fetch_seen) $display("ERROR: BEV general vector was not fetched");
                if (!ebase_mode_seen) $display("ERROR: handler never cleared BEV/ERL/EXL");
                if (!ebase_refill_seen) $display("ERROR: EBase miss was not classified as refill");
                if (!ebase_refill_fetch_seen) $display("ERROR: EBase refill vector was not fetched");
                if (!ebase_invalid_seen) $display("ERROR: EBase invalid was not classified as invalid");
                if (!ebase_general_fetch_seen) $display("ERROR: EBase general vector was not fetched");
                $display("REGRESSION_TEST_FAILED product_tlb_vectors");
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
        bev_refill_seen = 1'b0;
        bev_refill_fetch_seen = 1'b0;
        bev_invalid_seen = 1'b0;
        bev_general_fetch_seen = 1'b0;
        ebase_mode_seen = 1'b0;
        ebase_refill_seen = 1'b0;
        ebase_refill_fetch_seen = 1'b0;
        ebase_invalid_seen = 1'b0;
        ebase_general_fetch_seen = 1'b0;
        sram_hex = "";
        if (!$value$plusargs("SRAM_HEX=%s", sram_hex)) begin
            $display("ERROR: SRAM_HEX is required");
            $finish;
        end
        u_soc.preload_sram_hex(sram_hex);
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
