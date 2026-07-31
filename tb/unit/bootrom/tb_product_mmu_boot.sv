`timescale 1ns/1ps
`include "soc_config.vh"

module tb_product_mmu_boot;
    localparam [31:0] WIRED_LO0 = 32'h0100_0017;
    localparam [31:0] WIRED_LO1 = 32'h0100_0057;
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
    integer tlb_index;
    reg reset_seen;
    reg refill_vector_seen;
    reg wired_entry_seen;
    reg refill_entry_seen;
    reg apb_write_seen;
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
            $display("REGRESSION_TEST_FAILED product_mmu_boot");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_seen = 1'b0;
            refill_vector_seen = 1'b0;
            wired_entry_seen = 1'b0;
            refill_entry_seen = 1'b0;
            apb_write_seen = 1'b0;
            mailbox_request_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0200)
                refill_vector_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_wired == 6'd1 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[0] &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_vpn2[0] == 19'h60000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[0] == WIRED_LO0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[0] == WIRED_LO1)
                wired_entry_seen = 1'b1;

            for (tlb_index = 1; tlb_index < `SOC_CP0_TLB_ENTRIES; tlb_index = tlb_index + 1) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[tlb_index] &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_vpn2[tlb_index] == DDR_VPN2)
                    refill_entry_seen = 1'b1;
            end

            if (u_soc.u_impl.s1_awvalid && u_soc.u_impl.s1_awready &&
                u_soc.u_impl.s1_awaddr == 32'h4000_0000)
                apb_write_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hDEAD_BEEF)
                    fail("product boot firmware reported a failure mailbox");
                mailbox_request_seen = 1'b1;
            end

            if (mailbox_request_seen &&
                !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (!reset_seen)
                    fail("reset PC was not observed in Boot ROM");
                if (!refill_vector_seen)
                    fail("useg access did not execute the BEV refill vector");
                if (!wired_entry_seen)
                    fail("wired kseg2 to APB TLB entry was not installed");
                if (!refill_entry_seen)
                    fail("TLBWR did not install the useg DDR refill entry");
                if (!apb_write_seen)
                    fail("wired kseg2 mapping did not reach the APB UART address");
                $display("REGRESSION_TEST_SUCCESS product_mmu_boot");
                $finish;
            end

            if (cycles > 5000)
                fail("product MMU boot did not reach its completion mailbox");
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
