`timescale 1ns/1ps
`include "soc_config.vh"
`ifdef TB_RETIRE_TRACE
`include "soc_observation_if.sv"
`include "soc_observation_bind.sv"
`include "retire_trace_capture.sv"
`endif

module tb_product_mmu_pagemask;
    localparam [15:0] PAGE_MASK_4K   = 16'h0000;
    localparam [15:0] PAGE_MASK_16K  = 16'h0003;
    localparam [15:0] PAGE_MASK_64K  = 16'h000f;
    localparam [15:0] PAGE_MASK_256K = 16'h003f;
    localparam [31:0] MARK_CONTEXT = 32'hC003_0001;
    localparam [31:0] MARK_ACCESS  = 32'hC003_0002;
    reg clk, rst_n, tck, tms, tdi;
    wire tdo, spi_sclk, spi_cs_n, spi_mosi, uart_tx;
    wire uart_rx = 1'b1, uart_cts_n = 1'b1, uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1, uart_ri_n = 1'b1, spi_miso = 1'b0;
    wire uart_rts_n, uart_dtr_n;
    wire [31:0] gpio_pins;
`ifdef TB_RETIRE_TRACE
    soc_observation_if retire_obs_if(clk, rst_n);
    retire_trace_capture u_retire_trace_capture(.clk(clk), .rst_n(rst_n),
                                                 .obs_if(retire_obs_if));
`endif
    integer cycles, refill_count;
    reg reset_seen, refill_vector_active;
    reg mask4_seen, mask16_seen, mask64_seen, mask256_seen;
    reg pfn4_seen, pfn16_seen, pfn64_seen, pfn256_seen;
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
            mask4_seen = 0; mask16_seen = 0; mask64_seen = 0; mask256_seen = 0;
            pfn4_seen = 0; pfn16_seen = 0; pfn64_seen = 0; pfn256_seen = 0;
            context_seen = 0;
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
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[ti]) begin
                    case (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[ti])
                        8'd4: begin
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[ti] == PAGE_MASK_4K)
                                mask4_seen = 1'b1;
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == 20'h08010 &&
                                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[ti][25:6] == 20'h08020)
                                pfn4_seen = 1'b1;
                        end
                        8'd5: begin
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[ti] == PAGE_MASK_16K)
                                mask16_seen = 1'b1;
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == 20'h08030 &&
                                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[ti][25:6] == 20'h08040)
                                pfn16_seen = 1'b1;
                        end
                        8'd6: begin
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[ti] == PAGE_MASK_64K)
                                mask64_seen = 1'b1;
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == 20'h08050 &&
                                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[ti][25:6] == 20'h08060)
                                pfn64_seen = 1'b1;
                        end
                        8'd7: begin
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[ti] == PAGE_MASK_256K)
                                mask256_seen = 1'b1;
                            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[ti][25:6] == 20'h08000 &&
                                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo1[ti][25:6] == 20'h08040)
                                pfn256_seen = 1'b1;
                        end
                        default: ;
                    endcase
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
                if (refill_count != 3) fail("page-size mappings did not use three expected refills");
                if (!mask4_seen || !mask16_seen || !mask64_seen || !mask256_seen) begin
                    fail("one or more PageMask encodings were not observed");
                end
                if (!pfn4_seen || !pfn16_seen || !pfn64_seen || !pfn256_seen)
                    fail("one or more even/odd PFN pairs were not observed");
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

`ifdef TB_RETIRE_TRACE
bind tb_product_mmu_pagemask soc_observation_bind u_soc_retire_observation_bind (
    .obs_if               (retire_obs_if),
    .retire_schema        (32'h00010000),
    .retire_valid         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_valid),
    .retire_pc            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc),
    .retire_instr         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst),
    .retire_next_pc       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_next_pc),
    .retire_gpr_we        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr != 5'd0)),
    .retire_gpr_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr),
    .retire_gpr_data      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata),
    .retire_cp0_we        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_we &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'h10) &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst[25:21] == 5'h04)),
    .retire_cp0_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr),
    .retire_cp0_sel       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_sel),
    .retire_cp0_data      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_fpr_state     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_save_fpr),
    .retire_fcsr_state    (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_save_fcsr),
    .retire_mem_valid     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace ||
                           u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_read      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace),
    .retire_mem_write     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_mem_wdata     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_val_rt),
    .retire_mem_be        (4'b1111),
    .retire_mem_rdata     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rdata_selected),
    .retire_except        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req),
    .retire_except_code   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code),
    .retire_bd            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_bd),
    .retire_eret          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .mailbox_valid        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                           u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'ha000fffc)),
    .mailbox_wdata        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata),
    .ex_reg_write         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_reg_write),
    .ex_pc                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_pc_plus_8 - 32'd8),
    .jtag_axi_state       (u_soc.u_impl.u_debug_subsystem.u_jtag_debug_top.axi_state),
    .cpu_cp0_except_req   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req),
    .cpu_cp0_except_code  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code),
    .cpu_cp0_intr_req     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req),
    .cpu_cp0_eret         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .cpu_cp0_exl          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1]),
    .cpu_cp0_epc          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc)
);
`endif
