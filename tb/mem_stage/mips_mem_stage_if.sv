// =============================================================================
// File Name: mips_mem_stage_if.sv
// Design:    Interface for MEM Stage Verification
// Author:    Antigravity
// =============================================================================

interface mips_mem_stage_if(input logic clk, input logic rst_n);
    // Inputs
    logic [31:0] mem_ex_out;
    logic [31:0] mem_val_rt;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  mem_op;
    logic [31:0] dmem_rdata;
    
    // Outputs
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_we;
    logic        dmem_en;
    logic [31:0] mem_rdata_ext;
    logic        adel_exception;
    logic        ades_exception;
endinterface
