// =============================================================================
// File Name: tb_mips_soc.v
// Design:    Testbench for MIPS32 SoC Top
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps

module tb_mips_soc;


    reg tck_r = 0;
    reg tms_r = 1;
    reg tdi_r = 0;
    wire tdo;

    reg clk;
    reg rst_n;
    
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
        .spi_miso   (1'b0),
        .tck        (tck_r),
        .tms        (tms_r),
        .tdi        (tdi_r),
        .tdo        (tdo)
    );
    
    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Sequence
    initial begin
        rst_n = 0;
        
        // Wait a few cycles
        #25;
        rst_n = 1;
        
        // Pre-load SRAM (Memory address is byte-aligned, ram[] is word-aligned)
        // Program: Print "Hi!\n" to UART at 0x4000_0000
        
        // Initialize memory with firmware.hex
        $readmemh("firmware.hex", u_soc.u_impl.u_axi_sram.ram);
        
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
        if (u_soc.u_impl.u_core.u_cpu.data_req && u_soc.u_impl.u_core.u_cpu.data_we && u_soc.u_impl.u_core.u_cpu.data_addr == 32'ha000fffc) begin
            if (u_soc.u_impl.u_core.u_cpu.data_wdata == 32'hdeadbeef) begin
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (u_soc.u_impl.u_core.u_cpu.data_wdata == 32'hdeaddead) begin
                $display("REGRESSION_TEST_FAILED");
                $finish;
            end
        end
        
        // Debug PC Trace
        if ($time % 5000000 == 0) begin
            $display("Time=%0t PC=%h", $time, u_soc.u_impl.u_core.u_cpu.u_mips_if_stage.pc);
        end
    end
    
    always @(posedge clk) begin
        if (u_soc.u_impl.u_apb_uart.psel && u_soc.u_impl.u_apb_uart.penable && u_soc.u_impl.u_apb_uart.pwrite && u_soc.u_impl.u_apb_uart.paddr[7:0] == 8'h00) begin
            $write("%c", u_soc.u_impl.u_apb_uart.pwdata[7:0]);
            $fflush();
        end
        if (rst_n && u_soc.u_impl.u_core.u_cpu.global_stall && $time > 20900000) begin
            $display("Time=%0t DCACHE: state=%0d next_state=%0d req_buf_addr=%x req_buf_we=%b uc_req=%b awv=%b wv=%b bready=%b", 
                $time, u_soc.u_impl.u_core.u_dcache.state, u_soc.u_impl.u_core.u_dcache.next_state, u_soc.u_impl.u_core.u_dcache.req_buf_addr, u_soc.u_impl.u_core.u_dcache.req_buf_we, u_soc.u_impl.u_core.u_dcache.uncacheable, u_soc.u_impl.u_core.u_dcache.awvalid, u_soc.u_impl.u_core.u_dcache.wvalid, u_soc.u_impl.u_core.u_dcache.bready);
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
