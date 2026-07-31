`timescale 1ns/1ps

// Exercise the MEM-side half of the refill classification. The ROM issues a
// useg load, then its refill handler creates a matching V=0 entry and retries
// the same load. Both cases report TLBL, but only the true miss may use +0x000.
module tb_product_tlb_data_vectors;
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
    reg data_refill_seen;
    reg data_refill_fetch_seen;
    reg data_invalid_seen;
    reg data_general_fetch_seen;

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

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            data_refill_seen = 1'b0;
            data_refill_fetch_seen = 1'b0;
            data_invalid_seen = 1'b0;
            data_general_fetch_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h0000_0000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok) begin
                if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_hit)
                    data_refill_seen = 1'b1;
                else if (!u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_v)
                    data_invalid_seen = 1'b1;
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0200)
                data_refill_fetch_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0380)
                data_general_fetch_seen = 1'b1;

            if (data_refill_seen && data_refill_fetch_seen && data_invalid_seen &&
                data_general_fetch_seen) begin
                $display("REGRESSION_TEST_SUCCESS product_tlb_data_vectors");
                $finish;
            end

            if (cycles > 2500) begin
                $display("DEBUG: pc=%h d_va=%h d_ok=%b d_hit=%b d_v=%b",
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_hit,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_v);
                if (!data_refill_seen) $display("ERROR: DTLB miss was not classified as refill");
                if (!data_refill_fetch_seen) $display("ERROR: DTLB refill vector was not fetched");
                if (!data_invalid_seen) $display("ERROR: DTLB invalid was not classified as invalid");
                if (!data_general_fetch_seen) $display("ERROR: DTLB general vector was not fetched");
                $display("REGRESSION_TEST_FAILED product_tlb_data_vectors");
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
        data_refill_seen = 1'b0;
        data_refill_fetch_seen = 1'b0;
        data_invalid_seen = 1'b0;
        data_general_fetch_seen = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
