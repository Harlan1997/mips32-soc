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
    logic        mem_done;
    logic        enable_nonblocking_load;
    logic        mem_cache_op_valid;
    logic [4:0]  mem_cache_op;
    logic        dmem_addr_ok;
    logic        dmem_data_ok;
    logic        translation_fault;
    logic        cache_op_done;
    logic        cache_op_error;
    
    // Outputs
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_we;
    logic [3:0]  dmem_be;
    logic        dmem_en;
    logic [31:0] mem_rdata_ext;
    logic        adel_exception;
    logic        ades_exception;
    logic        stall_req_mem;
    logic        cache_op_valid;
    logic [4:0]  cache_op;
    logic [31:0] cache_op_addr;
    logic        cache_op_fault;
endinterface
