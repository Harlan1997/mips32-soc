`timescale 1ns/1ps
`include "soc_config.vh"
`ifdef TB_RETIRE_TRACE
`include "soc_observation_if.sv"
`include "soc_observation_bind.sv"
`include "retire_trace_capture.sv"
`define RETIRE_BIND_TARGET tb_product_mmu_process_pressure
`include "standalone_retire_trace_bind.sv"
`endif

module tb_product_mmu_process_pressure;
    localparam [19:0] PFN_ASID1 = 20'h08003;
    localparam [19:0] PFN_ASID2 = 20'h08004;
    localparam [19:0] PFN_ASID3 = 20'h08005;
    localparam [19:0] PFN_ASID4 = 20'h08006;
    localparam [31:0] PROCESS_MARK = 32'hC002_0001;
    localparam [31:0] SHOOTDOWN_MARK = 32'hC002_0002;

    reg clk;
    reg rst_n;
    reg tck;
    reg tms;
    reg tdi;
    wire tdo;
    wire spi_sclk, spi_cs_n, spi_mosi;
    wire uart_tx, uart_rts_n, uart_dtr_n;
    wire uart_rx = 1'b1;
    wire uart_cts_n = 1'b1;
    wire uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1;
    wire uart_ri_n = 1'b1;
    wire spi_miso = 1'b0;
    wire [31:0] gpio_pins;
`ifdef TB_RETIRE_TRACE
    soc_observation_if retire_obs_if(clk, rst_n);
    retire_trace_capture u_retire_trace_capture(.clk(clk), .rst_n(rst_n),
                                                 .obs_if(retire_obs_if));
`endif

    integer cycles;
    integer refill_count;
    reg refill_vector_active;
    reg reset_seen;
    reg asid1_mapping_seen;
    reg asid2_mapping_seen;
    reg asid3_mapping_seen;
    reg asid4_mapping_seen;
    reg process_marker_seen;
    reg shootdown_marker_seen;
    reg mailbox_seen;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate

    mips_soc u_soc (
        .clk(clk), .rst_n(rst_n), .gpio_pins(gpio_pins),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n), .uart_dsr_n(uart_dsr_n),
        .uart_dtr_n(uart_dtr_n), .uart_dcd_n(uart_dcd_n), .uart_ri_n(uart_ri_n),
        .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo)
    );

    always #5 clk = ~clk;

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED product_mmu_process_pressure");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        integer ti;
        if (!rst_n) begin
            cycles = 0;
            refill_count = 0;
            refill_vector_active = 1'b0;
            reset_seen = 1'b0;
            asid1_mapping_seen = 1'b0;
            asid2_mapping_seen = 1'b0;
            asid3_mapping_seen = 1'b0;
            asid4_mapping_seen = 1'b0;
            process_marker_seen = 1'b0;
            shootdown_marker_seen = 1'b0;
            mailbox_seen = 1'b0;
        end else begin
            cycles = cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0200) begin
                if (!refill_vector_active)
                    refill_count = refill_count + 1;
                refill_vector_active = 1'b1;
            end else begin
                refill_vector_active = 1'b0;
            end

            for (ti = 1; ti < `SOC_CP0_TLB_ENTRIES; ti = ti + 1) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti] == 8'd1 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == PFN_ASID1)
                    asid1_mapping_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti] == 8'd2 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == PFN_ASID2)
                    asid2_mapping_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti] == 8'd3 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == PFN_ASID3)
                    asid3_mapping_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti] == 8'd4 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == PFN_ASID4)
                    asid4_mapping_seen = 1'b1;
            end

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF0) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == PROCESS_MARK)
                    process_marker_seen = 1'b1;
                else
                    fail("process marker was incorrect");
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF4) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == SHOOTDOWN_MARK)
                    shootdown_marker_seen = 1'b1;
                else
                    fail("shootdown marker was incorrect");
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hDEAD_BEEF)
                    fail("process pressure firmware reported failure");
                mailbox_seen = 1'b1;
            end

            if (mailbox_seen && !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (!reset_seen) fail("reset PC was not observed");
                if (refill_count < 8) fail("four ASIDs did not refill before and after shootdown");
                if (!asid1_mapping_seen || !asid2_mapping_seen ||
                    !asid3_mapping_seen || !asid4_mapping_seen)
                    fail("all four ASID-specific PFN mappings were not observed");
                if (!process_marker_seen || !shootdown_marker_seen)
                    fail("process and shootdown phase markers were not observed");
                $display("REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=%0d", refill_count);
                $finish;
            end
            if (cycles > 20000)
                fail("product ASID process pressure firmware timed out");
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
