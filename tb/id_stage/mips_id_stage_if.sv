// =============================================================================
// File Name: mips_id_stage_if.sv
// Design:    MIPS32 ID Stage Verification Interface
// Author:    Antigravity
// Description:
//   SystemVerilog interface connecting the UVM driver/monitor to the ID stage.
// =============================================================================

interface mips_id_stage_if (input wire clk, input wire rst_n);

    // Inputs to DUT
    logic [31:0] inst;
    logic [31:0] pc_plus_4;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    logic        rf_we;
    
    logic        fw_ex_we;
    logic [4:0]  fw_ex_waddr;
    logic [31:0] fw_ex_val;
    
    logic        fw_mem_we;
    logic [4:0]  fw_mem_waddr;
    logic [31:0] fw_mem_val;
    
    logic        fw_wb_we;
    logic [4:0]  fw_wb_waddr;
    logic [31:0] fw_wb_val;
    
    logic        ex_mem_read;
    logic [4:0]  ex_waddr;

    // Outputs from DUT
    logic        stall_req;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        jump_taken;
    logic [31:0] jump_target;
    
    logic [31:0] val_rs;
    logic [31:0] val_rt;
    logic [31:0] imm_ext;
    logic [4:0]  waddr_out;
    logic [4:0]  sa_out;
    logic [4:0]  rs_addr;
    logic [4:0]  rt_addr;
    logic [4:0]  rd_addr;
    
    logic [3:0]  alu_op;
    logic [2:0]  mdu_op;
    logic        mdu_start;
    logic        sel_mdu_out;
    logic        alu_src;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  mem_op;
    logic [1:0]  mem_to_reg;
    logic        illegal_inst;

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output inst;
        output pc_plus_4;
        output rf_waddr;
        output rf_wdata;
        output rf_we;
        output fw_ex_we;
        output fw_ex_waddr;
        output fw_ex_val;
        output fw_mem_we;
        output fw_mem_waddr;
        output fw_mem_val;
        output fw_wb_we;
        output fw_wb_waddr;
        output fw_wb_val;
        output ex_mem_read;
        output ex_waddr;
        
        input stall_req;
        input branch_taken;
        input branch_target;
        input jump_taken;
        input jump_target;
        input val_rs;
        input val_rt;
        input imm_ext;
        input waddr_out;
        input sa_out;
        input rs_addr;
        input rt_addr;
        input rd_addr;
        input alu_op;
        input mdu_op;
        input mdu_start;
        input sel_mdu_out;
        input alu_src;
        input reg_write;
        input mem_read;
        input mem_write;
        input mem_op;
        input mem_to_reg;
        input illegal_inst;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input inst;
        input pc_plus_4;
        input rf_waddr;
        input rf_wdata;
        input rf_we;
        input fw_ex_we;
        input fw_ex_waddr;
        input fw_ex_val;
        input fw_mem_we;
        input fw_mem_waddr;
        input fw_mem_val;
        input fw_wb_we;
        input fw_wb_waddr;
        input fw_wb_val;
        input ex_mem_read;
        input ex_waddr;
        
        input stall_req;
        input branch_taken;
        input branch_target;
        input jump_taken;
        input jump_target;
        input val_rs;
        input val_rt;
        input imm_ext;
        input waddr_out;
        input sa_out;
        input rs_addr;
        input rt_addr;
        input rd_addr;
        input alu_op;
        input mdu_op;
        input mdu_start;
        input sel_mdu_out;
        input alu_src;
        input reg_write;
        input mem_read;
        input mem_write;
        input mem_op;
        input mem_to_reg;
        input illegal_inst;
    endclocking

    modport drv (clocking drv_cb, input rst_n);
    modport mon (clocking mon_cb, input rst_n);

endinterface
