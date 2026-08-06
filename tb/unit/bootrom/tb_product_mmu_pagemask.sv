`timescale 1ns/1ps
`include "soc_config.vh"

module tb_product_mmu_pagemask;
    localparam [15:0] PAGE_MASK_16K = 16'h0003;
    localparam [19:0] PFN_EVEN = 20'h08010;
    localparam [19:0] PFN_ODD  = 20'h08020;
    localparam [31:0] MARK_CONTEXT = 32'hC003_0001;
    localparam [31:0] MARK_ACCESS  = 32'hC003_0002;
    reg clk, rst_n, tck, tms, tdi;
    wire tdo, spi_sclk, spi_cs_n, spi_mosi, uart_tx;
    wire uart_rx = 1'b1, uart_cts_n = 1'b1, uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1, uart_ri_n = 1'b1, spi_miso = 1'b0;
    wire uart_rts_n, uart_dtr_n;
    wire [31:0] gpio_pins;
    integer cycles, refill_count;
    reg reset_seen, refill_vector_active, mask_seen, even_seen, odd_seen;
    reg context_seen, access_seen, mailbox_seen;

    genvar i;
    generate for (i = 0; i < 32; i = i + 1) begin : gpio_pull
        pullup(gpio_pins[i]);
    end endgenerate

    mips_soc u_soc (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n), .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n), .spi_sclk(spi_sclk),
        .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo)
    );
    always #5 clk = ~clk;

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED product_mmu_pagemask");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        integer ti;
        if (!rst_n) begin
            cycles = 0; refill_count = 0; reset_seen = 0; refill_vector_active = 0;
            mask_seen = 0; even_seen = 0; odd_seen = 0; context_seen = 0;
            access_seen = 0; mailbox_seen = 0;
        end else begin
            cycles = cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0200) begin
                if (!refill_vector_active) refill_count = refill_count + 1;
                refill_vector_active = 1'b1;
            end else refill_vector_active = 1'b0;

            for (ti = 1; ti < `SOC_CP0_TLB_ENTRIES; ti = ti + 1) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti] == 8'd7 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[ti] == PAGE_MASK_16K) begin
                    mask_seen = 1'b1;
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == PFN_EVEN)
                        even_seen = 1'b1;
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[ti][25:6] == PFN_ODD)
                        odd_seen = 1'b1;
                end
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF0) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == MARK_CONTEXT) context_seen = 1'b1;
                else fail("PageMask context marker was incorrect");
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF4) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == MARK_ACCESS) access_seen = 1'b1;
                else fail("PageMask access marker was incorrect");
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hDEAD_BEEF)
                    fail("PageMask firmware reported failure");
                mailbox_seen = 1'b1;
            end

            if (mailbox_seen && !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (!reset_seen) fail("reset PC was not observed");
                if (refill_count != 1) fail("16KB mapping did not use one refill");
                if (!mask_seen || !even_seen || !odd_seen) fail("16KB mask or PFN was not observed");
                if (!context_seen || !access_seen) fail("PageMask phase markers were not observed");
                $display("REGRESSION_TEST_SUCCESS product_mmu_pagemask refills=%0d", refill_count);
                $finish;
            end
            if (cycles > 12000) fail("PageMask firmware timed out");
        end
    end

    initial begin
        clk = 0; rst_n = 0; tck = 0; tms = 1; tdi = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
    end
endmodule
