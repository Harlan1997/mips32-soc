// =============================================================================
// File Name: tb_mips_soc.v
// Design:    Testbench for MIPS32 SoC Top
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps

module tb_mips_soc;

    reg clk;
    reg rst_n;
    
    wire [31:0] gpio_pins;

    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    reg  spi_miso;
    
    initial spi_miso = 1'b0;

    
    // Pull down GPIOs weakly to avoid 'z' in simulation if not driven
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate
    
    // Instantiate Full SoC
    mips_soc u_soc (
        .clk   (clk),
        .rst_n (rst_n),
        
        .gpio_pins (gpio_pins),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)

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
        $readmemh("firmware.hex", u_soc.u_axi_sram.ram);
        
        // We need to wait enough cycles for instruction fetch, cache miss, uncacheable writes
        #5000;
        
        $display("==================================================");
        $display("SoC Simulation Finished");
        $display("==================================================");
        $finish;
    end
    
    // Monitor Register Writes
    always @(posedge clk) begin
        if (rst_n && !u_soc.u_core.u_cpu.global_stall) begin
            $display("Time=%0t | Fetch PC=%08x Inst=%08x", $time, u_soc.u_core.u_cpu.u_mips_if_stage.pc, u_soc.u_core.u_cpu.inst_rdata);
        end else if (rst_n && u_soc.u_core.u_cpu.global_stall) begin
            $display("Time=%0t | STALL! mem=%b dcache_state=%d bvalid=%b bready=%b", $time, 
                     u_soc.u_core.u_cpu.stall_req_mem,
                     u_soc.u_core.u_dcache.state,
                     u_soc.u_core.u_dcache.bvalid,
                     u_soc.u_core.u_dcache.bready);
        end
    end

    always @(posedge clk) begin
        if (u_soc.u_core.u_cpu.wb_reg_write && u_soc.u_core.u_cpu.wb_waddr != 0) begin
            $display("Time=%0t | RegWrite: Reg[%2d] <= %08x", 
                     $time, 
                     u_soc.u_core.u_cpu.wb_waddr, 
                     u_soc.u_core.u_cpu.wb_wdata);
        end
    end
    
    // Dump waves
    initial begin
        $fsdbDumpfile("soc_pipeline.fsdb");
        $fsdbDumpvars(0, tb_mips_soc);
    end

endmodule
