// =============================================================================
// File Name: mips_mem_stage_tb_top.sv
// Design:    TB Top for MEM Stage
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps

module mips_mem_stage_tb_top;
    import uvm_pkg::*;
    import mips_mem_stage_pkg::*;

    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #15 rst_n = 1;
    end

    mips_mem_stage_if vif(clk, rst_n);

    mips_mem_stage dut (
        .mem_ex_out     (vif.mem_ex_out),
        .mem_val_rt     (vif.mem_val_rt),
        .mem_read       (vif.mem_read),
        .mem_write      (vif.mem_write),
        .mem_op         (vif.mem_op),
        .mem_done       (vif.mem_done),
        .enable_nonblocking_load(vif.enable_nonblocking_load),
        .mem_cache_op_valid(vif.mem_cache_op_valid),
        .mem_cache_op   (vif.mem_cache_op),
        .dmem_rdata     (vif.dmem_rdata),
        
        .dmem_addr      (vif.dmem_addr),
        .dmem_wdata     (vif.dmem_wdata),
        .dmem_we        (vif.dmem_we),
        .dmem_be        (vif.dmem_be),
        .dmem_en        (vif.dmem_en),
        .dmem_addr_ok   (vif.dmem_addr_ok),
        .dmem_data_ok   (vif.dmem_data_ok),
        .translation_fault(vif.translation_fault),
        .cache_op_done  (vif.cache_op_done),
        .cache_op_error (vif.cache_op_error),
        .mem_rdata_ext  (vif.mem_rdata_ext),
        .adel_exception (vif.adel_exception),
        .ades_exception (vif.ades_exception),
        .stall_req_mem  (vif.stall_req_mem),
        .cache_op_valid (vif.cache_op_valid),
        .cache_op       (vif.cache_op),
        .cache_op_addr  (vif.cache_op_addr),
        .cache_op_fault (vif.cache_op_fault)
    );

    initial begin
        uvm_config_db#(virtual mips_mem_stage_if)::set(null, "uvm_test_top.env.agt.*", "vif", vif);
        run_test("mem_test");
    end

    initial begin
        $fsdbDumpfile("novas.fsdb");
        $fsdbDumpvars(0, mips_mem_stage_tb_top);
    end
endmodule
