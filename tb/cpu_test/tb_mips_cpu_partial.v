// =============================================================================
// File Name: tb_mips_cpu_partial.v
// Design:    Testbench for Partial MIPS CPU Integration
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps

module tb_mips_cpu_partial;

    reg clk;
    reg rst_n;
    
    wire [31:0] inst_addr;
    wire [31:0] inst_rdata;
    
    wire [31:0] debug_ex_out;
    wire [4:0]  debug_ex_waddr;
    wire        debug_ex_reg_write;
    wire        debug_stall;
    wire        debug_flush;
    
    // Instantiate Partial CPU
    mips_cpu u_cpu (
        .clk                (clk),
        .rst_n              (rst_n),
        .inst_addr          (inst_addr),
        .inst_rdata         (inst_rdata),
        .debug_ex_out       (debug_ex_out),
        .debug_ex_waddr     (debug_ex_waddr),
        .debug_ex_reg_write (debug_ex_reg_write),
        .debug_stall        (debug_stall),
        .debug_flush        (debug_flush)
    );
    
    // Instruction Memory
    reg [31:0] imem [0:63];
    
    // Word-aligned instruction read
    assign inst_rdata = imem[inst_addr[31:2]];
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end
    
    initial begin
        // Initialize memory with 0 (NOPs)
        for (int i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'd0;
        end
        
        // Load program
        // PC=0x00: ADDI $1, $0, 5    (0x20010005)
        imem[0] = 32'h20010005;
        // PC=0x04: ADDI $2, $0, 10   (0x2002000a)
        imem[1] = 32'h2002000a;
        // PC=0x08: ADD $3, $1, $2    (0x00221820)
        imem[2] = 32'h00221820;
        // PC=0x0c: SUB $4, $2, $1    (0x00412022)
        imem[3] = 32'h00412022;
        // PC=0x10: SLT $5, $1, $2    (0x0022282a)
        imem[4] = 32'h0022282a;
        
        // Reset sequence
        rst_n = 0;
        #15 rst_n = 1;
        
        // Let it run
        #150;
        
        $display("==================================================");
        $display("Simulation Finished");
        $display("==================================================");
        $finish;
    end
    
    // Monitor
    always @(posedge clk) begin
        if (rst_n) begin
            $display("Time=%0t | PC=%h | Inst=%h | EX_WAddr=%d | EX_WData=%d | EX_RegWe=%b", 
                     $time, inst_addr, inst_rdata, debug_ex_waddr, debug_ex_out, debug_ex_reg_write);
        end
    end

    // FSDB Dumping
    initial begin
        $fsdbDumpfile("pipeline.fsdb");
        $fsdbDumpvars(0, tb_mips_cpu_partial);
    end

endmodule
