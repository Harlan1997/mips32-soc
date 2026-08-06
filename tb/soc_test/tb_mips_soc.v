// =============================================================================
// File Name: tb_mips_soc.v
// Design:    Testbench for MIPS32 SoC Top
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps
`include "soc_legacy_observation_if.sv"
`include "soc_legacy_observation_bind.sv"

module tb_mips_soc;


    reg tck_r = 0;
    reg tms_r = 1;
    reg tdi_r = 0;
    wire tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire uart_tx;
    wire uart_rts_n;
    wire uart_dtr_n;

    reg clk;
    reg rst_n;
    soc_legacy_observation_if legacy_obs_if(clk, rst_n);
    reg [1023:0] firmware_hex;
    integer cp0_interrupt_count;
    integer cp0_syscall_count;
    integer cp0_ri_count;
    integer cp0_adel_count;
    integer cp0_eret_count;
    integer dual_core_ipi_count;
    integer dual_core_reverse_ipi_count;
    integer dual_core_reset_count;
    integer dual_core_exception_count;
    
    wire [31:0] gpio_pins;
`ifdef SOC_UART_EXTERNAL_RX_WAVEFORM
    reg uart_rx = 1'b1;
`else
    wire uart_rx = 1'b1;
`endif
`ifdef SOC_UART_CTS_FLOW_CONTROL
    reg uart_cts_n = 1'b1;
`else
    wire uart_cts_n = 1'b0;
`endif
    wire uart_dsr_n = 1'b0;
    wire uart_dcd_n = 1'b0;
    wire uart_ri_n = 1'b1;
    reg uart_tx_seen_low;
`ifdef SOC_UART_CTS_FLOW_CONTROL
    reg uart_cts_release_seen;
    reg uart_tx_low_before_cts_release;
`endif
    
    // Pull down GPIOs weakly to avoid 'z' in simulation if not driven
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate
    
    mips_soc #(
`ifdef SOC_ENABLE_DUAL_CORE
               .ENABLE_DUAL_CORE(1'b1),
`endif
               .ENABLE_UART_PINS(1'b1),
`ifdef SOC_ENABLE_DDR4_STATUS
               .ENABLE_DDR4_STATUS(1'b1)
`else
               .ENABLE_DDR4_STATUS(1'b0)
`endif
`ifdef SOC_DDR4_STATUS_FATAL
               ,.ENABLE_DDR4_STATUS_FATAL(1'b1)
`else
               ,.ENABLE_DDR4_STATUS_FATAL(1'b0)
`endif
    ) u_soc(
        .clk        (clk),
        .rst_n      (rst_n),
        .gpio_pins  (gpio_pins),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .uart_cts_n (uart_cts_n),
        .uart_rts_n (uart_rts_n),
        .uart_dsr_n (uart_dsr_n),
        .uart_dtr_n (uart_dtr_n),
        .uart_dcd_n (uart_dcd_n),
        .uart_ri_n  (uart_ri_n),
        .spi_sclk   (spi_sclk),
        .spi_cs_n   (spi_cs_n),
        .spi_mosi   (spi_mosi),
        .spi_miso   (1'b0),
        .tck        (tck_r),
        .tms        (tms_r),
        .tdi        (tdi_r),
        .tdo        (tdo)
    );

    wire        legacy_mailbox_valid = legacy_obs_if.mailbox_valid;
    wire [31:0] legacy_mailbox_wdata = legacy_obs_if.mailbox_wdata;
    wire [31:0] legacy_trace_pc = legacy_obs_if.trace_pc;
    wire        legacy_cp0_except_req = legacy_obs_if.cp0_except_req;
    wire [4:0]  legacy_cp0_except_code = legacy_obs_if.cp0_except_code;
    wire        legacy_cp0_intr_req = legacy_obs_if.cp0_intr_req;
    wire        legacy_cp0_exl = legacy_obs_if.cp0_exl;
    wire        legacy_cp0_eret = legacy_obs_if.cp0_eret;
    wire        legacy_uart_tx_valid = legacy_obs_if.uart_tx_valid;
    wire [7:0]  legacy_uart_tx_data = legacy_obs_if.uart_tx_data;
    wire        legacy_core_global_stall = legacy_obs_if.core_global_stall;
    wire [3:0]  legacy_dcache_state = legacy_obs_if.dcache_state;
    wire [3:0]  legacy_dcache_next_state = legacy_obs_if.dcache_next_state;
    wire [31:0] legacy_dcache_req_buf_addr = legacy_obs_if.dcache_req_buf_addr;
    wire        legacy_dcache_req_buf_we = legacy_obs_if.dcache_req_buf_we;
    wire        legacy_dcache_uncacheable = legacy_obs_if.dcache_uncacheable;
    wire        legacy_dcache_awvalid = legacy_obs_if.dcache_awvalid;
    wire        legacy_dcache_wvalid = legacy_obs_if.dcache_wvalid;
    wire        legacy_dcache_bready = legacy_obs_if.dcache_bready;
    
    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Sequence
    initial begin
        rst_n = 0;
        cp0_interrupt_count = 0;
        cp0_syscall_count = 0;
        cp0_ri_count = 0;
        cp0_adel_count = 0;
        cp0_eret_count = 0;
        dual_core_ipi_count = 0;
        dual_core_reverse_ipi_count = 0;
        dual_core_reset_count = 0;
        dual_core_exception_count = 0;
        uart_tx_seen_low = 1'b0;
`ifdef SOC_UART_CTS_FLOW_CONTROL
        uart_cts_release_seen = 1'b0;
        uart_tx_low_before_cts_release = 1'b0;
`endif

        // Initialize memory with an explicit firmware artifact before reset release.
        firmware_hex = "firmware.hex";
        if ($value$plusargs("FW_HEX=%s", firmware_hex)) begin
            $display("tb_mips_soc: loading firmware from %0s", firmware_hex);
        end else begin
            $display("tb_mips_soc: loading default firmware.hex");
        end
        u_soc.preload_sram_hex(firmware_hex);

        // Wait a few cycles
        #25;
        rst_n = 1;
        
        // We need to wait enough cycles for instruction fetch, cache miss, uncacheable writes
    end

`ifdef SOC_ENABLE_DUAL_CORE
    initial begin
        wait (rst_n === 1'b1);

`ifdef SOC_COHERENCY_FW_STRESS
        $display("COH_STRESS_CPUNUM core0=%0d core1=%0d",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.CPUNUM,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.CPUNUM);
`endif
        repeat (100) @(posedge clk);
        if (^u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc === 1'bx) begin
            $display("REGRESSION_TEST_FAILED dual-core core1 PC is unknown");
            $finish;
        end
        $display("DUAL_CORE_CORE1_ACTIVE pc=%08h", u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc);
    end

`ifndef SOC_COHERENCY_LL_SC
`ifndef SOC_COHERENCY_FW_STRESS
    initial begin
        wait (rst_n === 1'b1);
        repeat (200) @(posedge clk);
        @(negedge clk);
        force u_soc.u_impl.core1_sim_exception_req = 1'b1;
        @(negedge clk);
        release u_soc.u_impl.core1_sim_exception_req;
        $display("DUAL_CORE_CORE1_EXCEPTION_INJECTED code=0A");
    end
`endif
`endif

`endif

`ifdef SOC_COHERENCY_LL_SC
    reg llsc_coherency_injected;
    reg llsc_coherency_observed;
    integer ll_valid_rise_count;

    initial begin
        force u_soc.u_impl.core1_reset_req = 1'b1;
        llsc_coherency_injected = 0;
        llsc_coherency_observed = 0;
        ll_valid_rise_count = 0;

        wait (rst_n === 1'b1);

        while (ll_valid_rise_count < 3) begin
            @(posedge u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_valid);
            ll_valid_rise_count = ll_valid_rise_count + 1;
            $display("tb_mips_soc: Observed LL reservation rise #%0d at time=%0t", ll_valid_rise_count, $time);
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        $display("tb_mips_soc: Injecting peer store notification for address 0xA0002000");
        force u_soc.u_impl.core1_coh_store_valid = 1'b1;
        force u_soc.u_impl.core1_coh_store_addr = 32'ha0002000;
        llsc_coherency_injected = 1;
        $display("LLSC_COHERENCY_PEER_NOTIF_INJECTED addr=A0002000");

        @(negedge clk);
        release u_soc.u_impl.core1_coh_store_valid;
        release u_soc.u_impl.core1_coh_store_addr;

        @(posedge clk);
        #1;
        if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_valid === 1'b0) begin
            llsc_coherency_observed = 1;
            $display("tb_mips_soc: Observed core-0 reservation cleared by peer notification");
        end else begin
            $display("REGRESSION_TEST_FAILED core-0 reservation was not cleared by peer notification");
            $finish;
        end
    end
`endif

    initial begin
`ifdef SOC_COHERENCY_FW_STRESS
        #20000000;
`else
        #5000000;
`endif
`ifdef SOC_COHERENCY_FW_STRESS
        $display("COH_STRESS_TIMEOUT core0_pc=%08h core1_pc=%08h c1_pc=%08h c0_state=%0d c0_req=%b/%b/%08h c1_exc=%b/%0d c1_epc=%08h c1_cause=%08h c1_bad=%08h c1_state=%0d c1_req=%b c1_we=%b c1_addr=%08h c1_wdata=%08h c1_be=%h rd=%b/%b/%08h/%b/%b owner=%b s0=%0d/%08h/%b/%b xrd=%0d/%0d/%0d/%b/%b/%b seen0=%08h seen1=%08h start=%08h ready=%08h command=%08h ack_word=%08h ack_part=%08h done=%08h fail=%08h",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_dcache.state,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_req,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_code,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_epc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_cause,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_badvaddr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_dcache.state,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_req,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_we,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_addr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_dcache.req_buf_wdata,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_dcache.req_buf_be,
                 u_soc.u_impl.fx_arvalid, u_soc.u_impl.fx_arready,
                 u_soc.u_impl.fx_araddr, u_soc.u_impl.fx_rvalid,
                 u_soc.u_impl.fx_rready,
                 u_soc.u_impl.g_dual_core.u_core1.rd_owner,
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.r_state,
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.r_addr,
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rvalid,
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rready,
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_cnt[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_head[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_head_mid[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_occ[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.s_arvalid[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.s_rvalid[0],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2120/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2124/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2100/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2104/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2108/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h210c/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2110/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2114/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2118/4]);
`endif
        $display("\n==================================================");
        $display("SoC Simulation Timeout");
        $display("==================================================");
        $finish;
    end
    
    // Mailbox Monitor for Regression Tests
    always @(posedge clk) begin
        if (legacy_mailbox_valid) begin
            $display("CPU_CP0_SUMMARY intr=%0d syscall=%0d ri=%0d adel=%0d eret=%0d",
                     cp0_interrupt_count, cp0_syscall_count, cp0_ri_count, cp0_adel_count, cp0_eret_count);
            if (legacy_mailbox_wdata == 32'hdeadbeef) begin
`ifdef SOC_COHERENCY_LL_SC
                if (!llsc_coherency_injected || !llsc_coherency_observed) begin
                    $display("REGRESSION_TEST_FAILED LL/SC peer coherency notification not injected/observed");
                    $finish;
                end
`else
`ifdef SOC_ENABLE_DUAL_CORE
`ifndef SOC_COHERENCY_FW_STRESS
                if (dual_core_ipi_count == 0) begin
                    $display("REGRESSION_TEST_FAILED dual-core IPI invalidate not observed");
                    $finish;
                end
                if (dual_core_reverse_ipi_count == 0) begin
                    $display("REGRESSION_TEST_FAILED target-0 IPI invalidate not observed");
                    $finish;
                end
                if (dual_core_reset_count == 0) begin
                    $display("REGRESSION_TEST_FAILED core1 reset isolation not observed");
                    $finish;
                end
                if (dual_core_exception_count == 0) begin
                    $display("REGRESSION_TEST_FAILED core1 exception isolation not observed");
                    $finish;
                end
`endif
`endif
`endif
`ifdef SOC_UART_CTS_FLOW_CONTROL
                if (uart_tx_low_before_cts_release) begin
                    $display("REGRESSION_TEST_FAILED UART TX asserted before CTS release");
                    $finish;
                end
                if (!uart_cts_release_seen) begin
                    $display("REGRESSION_TEST_FAILED UART CTS release checkpoint not reached");
                    $finish;
                end
`endif
`ifndef SOC_ENABLE_DUAL_CORE
                if (!uart_tx_seen_low) begin
                    $display("REGRESSION_TEST_FAILED UART TX pin never asserted");
                    $finish;
                end
`endif
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (legacy_mailbox_wdata == 32'hdeaddead) begin
                $display("REGRESSION_TEST_FAILED");
                $finish;
            end
        end

`ifdef SOC_ENABLE_DUAL_CORE
        if (u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_req &&
            u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_code == 5'h0A)
            dual_core_exception_count = dual_core_exception_count + 1;
        if (u_soc.u_impl.core1_reset_req)
            dual_core_reset_count = dual_core_reset_count + 1;
        if (u_soc.u_impl.g_dual_core.u_core1.tlb_inv_en &&
            u_soc.u_impl.g_dual_core.u_core1.tlb_inv_vpn2 == 19'h12345) begin
            dual_core_ipi_count = dual_core_ipi_count + 1;
        end
        if (u_soc.u_impl.u_core_subsystem.tlb_inv_en &&
            u_soc.u_impl.u_core_subsystem.tlb_inv_vpn2 == 19'h12346) begin
            dual_core_reverse_ipi_count = dual_core_reverse_ipi_count + 1;
        end
`endif
        
        // Debug PC Trace
        if ($time % 5000000 == 0) begin
            $display("Time=%0t PC=%h", $time, legacy_trace_pc);
        end
    end

`ifdef SOC_UART_EXTERNAL_RX_WAVEFORM
    // Wait until firmware enables RX with loopback disabled, then inject one
    // asynchronous 8N1 frame at the DUT's divisor=1 (16 clocks/bit) rate.
    task automatic external_uart_bit(input bit value);
    begin
        uart_rx = value;
        repeat (16) @(posedge clk);
    end
    endtask

    task automatic external_uart_frame(input [7:0] value);
        integer b;
    begin
        external_uart_bit(1'b0);
        for (b = 0; b < 8; b = b + 1)
            external_uart_bit(value[b]);
        external_uart_bit(1'b1);
        external_uart_bit(1'b1);
    end
    endtask

    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.ier_r[0] === 1'b1 &&
              u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.mcr_r[4] === 1'b0);
        repeat (32) @(posedge clk);
        $display("tb_mips_soc: injecting external UART RX frame 0x5A");
        external_uart_frame(8'h5A);
    end
`endif

`ifdef SOC_UART_CTS_FLOW_CONTROL
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.mcr_r[5] === 1'b1 &&
              u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.tx_empty === 1'b0);
        repeat (512) @(posedge clk);
        if (uart_tx !== 1'b1) begin
            $display("REGRESSION_TEST_FAILED UART TX started while CTS inactive");
            $finish;
        end
        $display("tb_mips_soc: UART CTS inactive held TX idle");
        uart_cts_release_seen = 1'b1;
        uart_cts_n = 1'b0;
        wait (uart_tx === 1'b0);
        $display("tb_mips_soc: UART CTS release allowed TX frame");
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cp0_interrupt_count <= 0;
            cp0_syscall_count <= 0;
            cp0_ri_count <= 0;
            cp0_adel_count <= 0;
            cp0_eret_count <= 0;
        end else begin
            if (legacy_cp0_except_req && !legacy_cp0_exl) begin
                if (legacy_cp0_intr_req) begin
                    cp0_interrupt_count <= cp0_interrupt_count + 1;
                end else begin
                    case (legacy_cp0_except_code)
                        5'h08: cp0_syscall_count <= cp0_syscall_count + 1;
                        5'h0a: cp0_ri_count <= cp0_ri_count + 1;
                        5'h04: cp0_adel_count <= cp0_adel_count + 1;
                    endcase
                end
            end

            if (legacy_cp0_eret) begin
                cp0_eret_count <= cp0_eret_count + 1;
            end
        end
    end
    
    always @(posedge clk) begin
`ifdef SOC_UART_CTS_FLOW_CONTROL
        if (rst_n && !uart_cts_release_seen && !uart_tx)
            uart_tx_low_before_cts_release <= 1'b1;
`endif
        if (rst_n && !uart_tx)
            uart_tx_seen_low <= 1'b1;
        if (legacy_uart_tx_valid) begin
            $write("%c", legacy_uart_tx_data);
            $fflush();
        end
        if (rst_n && legacy_core_global_stall && $time > 20900000) begin
            $display("Time=%0t DCACHE: state=%0d next_state=%0d req_buf_addr=%x req_buf_we=%b uc_req=%b awv=%b wv=%b bready=%b", 
                $time, legacy_dcache_state, legacy_dcache_next_state, legacy_dcache_req_buf_addr, legacy_dcache_req_buf_we, legacy_dcache_uncacheable, legacy_dcache_awvalid, legacy_dcache_wvalid, legacy_dcache_bready);
        end
    end

    



    task jtag_reset;
        begin
            tms_r = 1;
            repeat(5) begin
                #10 tck_r = 1; #10 tck_r = 0;
            end
        end
    endtask

    task jtag_shift_ir;
        input [3:0] ir_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_IR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<4; i=i+1) begin
                tdi_r = ir_val[i];
                tms_r = (i==3) ? 1 : 0; // EXIT1_IR on last bit
                #10 tck_r = 1; #10 tck_r = 0;
            end
            
            // Go to PAUSE_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Go to EXIT2_IR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            
            // UPDATE_IR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

    task jtag_shift_dr;
        input [31:0] dr_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<32; i=i+1) begin
                tdi_r = dr_val[i];
                tms_r = (i==31) ? 1 : 0; // EXIT1_DR on last bit
                #10 tck_r = 1; 
                #10 tck_r = 0;
            end
            
            // Go to PAUSE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Stay in PAUSE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Go to EXIT2_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            
            // UPDATE_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

    task jtag_shift_dr_65;
        input [64:0] dr_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<65; i=i+1) begin
                tdi_r = dr_val[i];
                tms_r = (i==64) ? 1 : 0; // EXIT1_DR on last bit
                #10 tck_r = 1; 
                #10 tck_r = 0;
            end
            // UPDATE_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

`ifndef SOC_COHERENCY_FW_STRESS
    initial begin
        // Let system reset finish
        #1500;
        jtag_reset();
        jtag_shift_ir(4'h1); // IDCODE
        jtag_shift_dr(32'h00000000); // shift out IDCODE (dummy shift)
        
        // JTAG AXI Write to GPIO direction register (0x4000_2004)
        jtag_shift_ir(4'h8); // IR_AXI_CMD
        // CMD: Write (1) | Addr (0x4000_2004) | Data (0xFFFF_FFFF)
        jtag_shift_dr_65({1'b1, 32'h40002004, 32'hFFFFFFFF});
        #100; // wait for AXI transaction

        // JTAG AXI Write to GPIO data register (0x4000_2000)
        // CMD: Write (1) | Addr (0x4000_2000) | Data (0xDEADBEEF)
        jtag_shift_dr_65({1'b1, 32'h40002000, 32'hDEADBEEF});
        #100; // wait for AXI transaction
        
        // JTAG AXI Read from GPIO data register (0x4000_2000)
        // CMD: Read (0) | Addr (0x4000_2000) | Data (0x0)
        jtag_shift_dr_65({1'b0, 32'h40002000, 32'h00000000});
        #100; // wait for AXI transaction
        // Read out the result (shift again to capture)
        jtag_shift_dr_65({1'b0, 32'h40002000, 32'h00000000});
        
        // JTAG Toggle Coverage Boost
        $display("Testing JTAG Toggle Coverage...");
        jtag_shift_ir(4'hA); // dummy IR pattern
        jtag_shift_ir(4'h5); // dummy IR pattern
        jtag_shift_dr_65({1'b1, 32'hAAAAAAAA, 32'h55555555});
        jtag_shift_dr_65({1'b0, 32'h55555555, 32'hAAAAAAAA});
        jtag_shift_dr_65({1'b1, 32'hFFFFFFFF, 32'hFFFFFFFF});
        jtag_shift_dr_65({1'b0, 32'h00000000, 32'h00000000});
        
        
        // --- JTAG FSM Coverage Sequence ---
        $display("Running JTAG FSM Coverage Sequence...");
        // Currently in RUN_TEST_IDLE.
        // Go to SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_IR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR (length 0 shift)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_IR (Cover EXIT1_IR -> UPDATE_IR)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_DR_SCAN (Cover UPDATE_IR -> SELECT_DR_SCAN)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_DR (length 0 shift)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to PAUSE_DR (Cover EXIT1_DR -> PAUSE_DR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT2_DR 
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SHIFT_DR (Cover EXIT2_DR -> SHIFT_DR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_DR 
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_DR_SCAN (Cover UPDATE_DR -> SELECT_DR_SCAN)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Go to SELECT_IR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to PAUSE_IR (Cover EXIT1_IR -> PAUSE_IR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT2_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SHIFT_IR (Cover EXIT2_IR -> SHIFT_IR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Back to RUN_TEST_IDLE
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        
        $display("JTAG Test Completed");
        
`ifndef SOC_COHERENCY_FW_STRESS
        // Wait until almost the end of simulation (3ms) before asserting reset
        // to avoid interrupting the main CPU firmware tests.
        #3000000;
        
        $display("Testing Async Reset in middle of operations to boost FSM transition coverage...");
        // Start a JTAG shift
        // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // SHIFT_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        tdi_r = 1; #10 tck_r = 1; #5;
        
        // Assert System Reset while in SHIFT_DR!
        rst_n = 0;
        #5 tck_r = 0;
        #20 rst_n = 1; // Release reset
        
        // Let system reset finish
        #100;
        
        $display("Testing JTAG synchronous reset (5 TCKs with TMS=1)...");
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // Should now be in TEST_LOGIC_RESET
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // Stay in TEST_LOGIC_RESET
        
        $display("Testing JTAG asynchronous resets...");
        // From RUN_TEST_IDLE
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SHIFT_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From PAUSE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT2_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT2_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From UPDATE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // UPDATE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // Now do IR states
        // From SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SHIFT_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From PAUSE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT2_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT2_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From UPDATE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // UPDATE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        $display("Testing AXI mid-flight reset via JTAG...");
        // Start JTAG AXI transaction
        jtag_shift_ir(4'h8); // IR_AXI_CMD
        // Start shifting DR, but don't finish
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_DR
        
        // Shift a few bits
        tdi_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Assert system reset
        rst_n = 0;
        #50 rst_n = 1;
`endif
        
    end
`endif

endmodule

bind tb_mips_soc soc_legacy_observation_bind u_soc_legacy_observation_bind (
    .obs_if              (legacy_obs_if),
    // Phase B.3.c + Phase C.1 note: watch the pre-MMU virtual address
    // (mem_vaddr) rather than the post-translation PA (data_addr). Firmware
    // always writes the mailbox as VA 0xA000FFFC (kseg1 alias); the MMU may
    // later translate this to PA 0x0000FFFC once SOC_MMU_ENABLE=1 flips,
    // which would silently break the observation if we watched data_addr.
    .mailbox_valid       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                          u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'ha000fffc)),
    .mailbox_wdata       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata),
    .trace_pc            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc),
    .cp0_except_req      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req),
    .cp0_except_code     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code),
    .cp0_intr_req        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req),
    .cp0_exl             (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1]),
    .cp0_eret            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .uart_tx_valid       (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.psel &&
                          u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.penable &&
                          u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwrite &&
                          (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.paddr[4:0] == 5'h00)),
    .uart_tx_data        (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwdata[7:0]),
    .core_global_stall   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.global_stall),
    .dcache_state        (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.state),
    .dcache_next_state   (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.next_state),
    .dcache_req_buf_addr (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.req_buf_addr),
    .dcache_req_buf_we   (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.req_buf_we),
    .dcache_uncacheable  (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.uncacheable),
    .dcache_awvalid      (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.awvalid),
    .dcache_wvalid       (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.wvalid),
    .dcache_bready       (u_soc.u_impl.u_core_subsystem.u_core.u_dcache.bready)
);
