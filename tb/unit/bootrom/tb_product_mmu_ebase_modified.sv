`timescale 1ns/1ps
`include "soc_config.vh"

// Product MMU exception contract: Boot ROM relocates an EBase handler to SRAM,
// then a useg store to a valid non-dirty TLB entry must raise Mod, be repaired,
// and complete after ERET.
module tb_product_mmu_ebase_modified;
    localparam [31:0] ENTRYLO0_CLEAN = 32'h0020_001B;
    localparam [31:0] ENTRYLO0_DIRTY = 32'h0020_001F;
    localparam [31:0] ENTRYLO1_DIRTY = 32'h0020_005F;
    localparam [18:0] DDR_VPN2 = 19'h04000;

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
    reg reset_seen;
    reg handler_relocated_seen;
    reg clean_entry_seen;
    reg mod_fault_seen;
    reg ebase_mode_seen;
    reg ebase_general_seen;
    reg cp0_state_seen;
    reg dirty_entry_seen;
    reg retry_seen;
    reg mailbox_request_seen;

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
            $display("REGRESSION_TEST_FAILED product_mmu_ebase_modified");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_seen = 1'b0;
            handler_relocated_seen = 1'b0;
            clean_entry_seen = 1'b0;
            mod_fault_seen = 1'b0;
            ebase_mode_seen = 1'b0;
            ebase_general_seen = 1'b0;
            cp0_state_seen = 1'b0;
            dirty_entry_seen = 1'b0;
            retry_seen = 1'b0;
            mailbox_request_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_0180)
                handler_relocated_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[1] &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_vpn2[1] == DDR_VPN2 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[1] == ENTRYLO0_CLEAN)
                clean_entry_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h0800_0000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_hit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_v &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_d &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type == 3'b011)
                mod_fault_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b0)
                ebase_mode_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0180)
                ebase_general_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] == 5'h01 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr == 32'h0800_0000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc[31:16] == 16'hBFC0)
                cp0_state_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[1] &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_vpn2[1] == DDR_VPN2 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[1] == ENTRYLO0_DIRTY &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[1] == ENTRYLO1_DIRTY)
                dirty_entry_seen = 1'b1;

            if (mod_fault_seen && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h0800_0000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok)
                retry_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hDEAD_BEEF) begin
                    $display("DEBUG: failure mailbox pc=%h cause=%h badvaddr=%h epc=%h status=%h entrylo0=%h",
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                             u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[1]);
                    fail("firmware rejected the EBase Modified exception state");
                end
                mailbox_request_seen = 1'b1;
            end

            if (mailbox_request_seen && !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (!reset_seen) fail("reset PC was not observed in Boot ROM");
                if (!handler_relocated_seen) fail("Boot ROM did not write the EBase handler to SRAM");
                if (!clean_entry_seen) fail("valid non-dirty TLB entry was not installed");
                if (!ebase_mode_seen) fail("firmware did not leave bootstrap vector mode");
                if (!mod_fault_seen) fail("store did not raise a DTLB Modified fault");
                if (!ebase_general_seen) fail("Modified fault did not fetch EBase general vector");
                if (!cp0_state_seen) fail("Modified fault did not preserve CP0 Cause/BadVAddr/EPC");
                if (!dirty_entry_seen) fail("EBase handler did not make the TLB entry dirty");
                if (!retry_seen) fail("ERET did not retry the repaired store");
                $display("REGRESSION_TEST_SUCCESS product_mmu_ebase_modified");
                $finish;
            end

            if (cycles > 7000)
                fail("EBase Modified firmware did not reach its completion mailbox");
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        spi_miso = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
