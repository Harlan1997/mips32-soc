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

    reg clk;
    reg rst_n;
    soc_legacy_observation_if legacy_obs_if(clk, rst_n);
    reg [1023:0] firmware_hex;
    integer cp0_interrupt_count;
    integer cp0_syscall_count;
    integer cp0_ri_count;
    integer cp0_adel_count;
    integer cp0_eret_count;
    
    wire [31:0] gpio_pins;
    
    // Pull down GPIOs weakly to avoid 'z' in simulation if not driven
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate
    
    mips_soc u_soc(
        .clk        (clk),
        .rst_n      (rst_n),
        .gpio_pins  (gpio_pins),
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

    initial begin
        #5000000;
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
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (legacy_mailbox_wdata == 32'hdeaddead) begin
                $display("REGRESSION_TEST_FAILED");
                $finish;
            end
        end
        
        // Debug PC Trace
        if ($time % 5000000 == 0) begin
            $display("Time=%0t PC=%h", $time, legacy_trace_pc);
        end
    end

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
        
    end

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
