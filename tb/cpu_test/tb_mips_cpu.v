// =============================================================================
// File Name: tb_mips_cpu.v
// Design:    Testbench for Full MIPS CPU Integration
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps

module tb_mips_cpu;

    reg clk;
    reg rst_n;
    
    wire [31:0] inst_addr;
    wire [31:0] inst_rdata;
    
    wire        data_req;
    wire        data_we;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire [31:0] data_rdata;
    
    wire        debug_stall;
    wire        debug_flush;
    
    // Mock handshake signals for ideal memory
    wire inst_addr_ok = 1'b1;
    wire inst_data_ok = 1'b1;
    wire data_addr_ok = 1'b1;
    wire data_data_ok = 1'b1;
    
    // Instantiate Full CPU
    mips_cpu u_cpu (
        .clk         (clk),
        .rst_n       (rst_n),
        .inst_req    (),
        .inst_addr   (inst_addr),
        .inst_addr_ok(inst_addr_ok),
        .inst_data_ok(inst_data_ok),
        .inst_rdata  (inst_rdata),
        
        .data_req    (data_req),
        .data_we     (data_we),
        .data_addr   (data_addr),
        .data_wdata  (data_wdata),
        .data_be     (data_be),
        .data_addr_ok(data_addr_ok),
        .data_data_ok(data_data_ok),
        .data_rdata  (data_rdata),
        
        .debug_stall (debug_stall),
        .debug_flush (debug_flush)
    );
    
    // Instruction Memory
    reg [31:0] imem [0:63];
    assign inst_rdata = imem[inst_addr[31:2]];
    
    // Data Memory
    reg [31:0] dmem [0:63];
    assign data_rdata = dmem[data_addr[31:2]];
    
    always @(posedge clk) begin
        if (data_req && data_we) begin
            if (data_be[0]) dmem[data_addr[31:2]][7:0]   <= data_wdata[7:0];
            if (data_be[1]) dmem[data_addr[31:2]][15:8]  <= data_wdata[15:8];
            if (data_be[2]) dmem[data_addr[31:2]][23:16] <= data_wdata[23:16];
            if (data_be[3]) dmem[data_addr[31:2]][31:24] <= data_wdata[31:24];
        end
    end
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end
    
    initial begin
        // Initialize memory with 0 (NOPs)
        for (int i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'd0;
            dmem[i] = 32'd0;
        end
        
        // Load program
        // PC=0x00: ADDI $1, $0, 5    (0x20010005)
        imem[0] = 32'h20010005;
        // PC=0x04: ADDI $2, $0, 10   (0x2002000a)
        imem[1] = 32'h2002000a;
        // PC=0x08: ADD $3, $1, $2    (0x00221820)   # $3 = 15
        imem[2] = 32'h00221820;
        // PC=0x0c: SW $3, 0($0)      (0xac030000)   # dmem[0] = 15
        imem[3] = 32'hac030000;
        // PC=0x10: LW $4, 0($0)      (0x8c040000)   # $4 = 15
        imem[4] = 32'h8c040000;
        
        // Reset sequence
        rst_n = 0;
        #15 rst_n = 1;
        
        // Let it run
        #250;
        
        $display("==================================================");
        $display("Simulation Finished");
        $display("DMEM[0] = %d", dmem[0]);
        $display("==================================================");
        $finish;
    end
    
    // Monitor WB stage (using hierarchical reference to internal signals)
    always @(posedge clk) begin
        if (rst_n && u_cpu.wb_reg_write && u_cpu.wb_waddr != 0) begin
            $display("Time=%0t | RegWrite: Reg[%d] <= %h", 
                     $time, u_cpu.wb_waddr, u_cpu.wb_wdata);
        end
    end

    // FSDB Dumping
    initial begin
        $fsdbDumpfile("pipeline.fsdb");
        $fsdbDumpvars(0, tb_mips_cpu);
    end

endmodule
