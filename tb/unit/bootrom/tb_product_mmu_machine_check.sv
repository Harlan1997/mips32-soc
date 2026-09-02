`timescale 1ns/1ps
`include "soc_config.vh"

module tb_product_mmu_machine_check;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg tck = 1'b0, tms = 1'b1, tdi = 1'b0, spi_miso = 1'b0;
    wire tdo, spi_sclk, spi_cs_n, spi_mosi;
    wire uart_tx, uart_rts_n, uart_dtr_n;
    wire uart_rx = 1'b1, uart_cts_n = 1'b1, uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1, uart_ri_n = 1'b1;
    wire [31:0] gpio_pins;
    genvar i;
    generate for (i = 0; i < 32; i = i + 1) begin : gpio_pull
        pullup(gpio_pins[i]);
    end endgenerate

    mips_soc u_soc (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n),
        .uart_dtr_n(uart_dtr_n), .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo)
    );
    always #5 clk = ~clk;

    integer cycles = 0;
    reg stale_forced = 1'b0;
    reg multi_hit_seen = 1'b0;
    reg mcheck_fault_seen = 1'b0;
    reg vector_seen = 1'b0;
    reg cp0_seen = 1'b0;

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED product_mmu_machine_check");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
        end else begin
            cycles = cycles + 1;
            if (!stale_forced &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[2]) begin
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.valid_d[0] = 1'b1;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.vpn_d[0] = 19'h04000;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.asid_d[0] = 8'h00;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.mask_d[0] = 16'h0000;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.global_d[0] = 1'b0;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.lo0_d[0] = 32'h0020_001F;
                force u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.u_micro_tlb.lo1_d[0] = 32'h0020_005F;
                stale_forced = 1'b1;
                $display("MMU_MCHECK: stale D micro-TLB entry forced");
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_multi_hit)
                multi_hit_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type == 3'b110)
                mcheck_fault_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0180)
                vector_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] == 5'h18)
                cp0_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hCAFE_1818) begin
                    $display("MMU_MCHECK_DEBUG pc=%h cause=%h badv=%h epc=%h status=%h dmulti=%b dfault=%b dreq=%b forced=%b vector=%b cp0=%b",
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_multi_hit,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                             stale_forced, vector_seen, cp0_seen);
                    fail("Machine Check handler reported failure");
                end
                if (!stale_forced) fail("stale micro-TLB was not injected");
                if (!multi_hit_seen) fail("CPU did not observe duplicate TLB match");
                if (!mcheck_fault_seen) fail("MMU did not classify duplicate match as MCheck");
                if (!vector_seen) fail("MCheck did not enter general exception vector");
                if (!cp0_seen) fail("CP0 did not capture MCheck state");
                $display("REGRESSION_TEST_SUCCESS product_mmu_machine_check");
                $finish;
            end
            if (cycles > 12000)
                fail("Machine Check firmware did not reach completion mailbox");
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
