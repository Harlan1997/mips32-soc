// =============================================================================
// File Name: mips_ex_stage_if.sv
// Design:    MIPS32 EX Stage Verification Interface
// Author:    Antigravity
// Description:
//   SystemVerilog interface connecting the UVM driver/monitor to the EX stage.
// =============================================================================

interface mips_ex_stage_if (input wire clk, input wire rst_n);

    // Inputs to DUT
    logic [31:0] op_a;
    logic [31:0] op_b;
    logic [4:0]  sa;
    logic [3:0]  alu_op;
    logic [2:0]  mdu_op;
    logic        mdu_start;
    logic        sel_mdu_out;

    // Outputs from DUT
    logic [31:0] ex_out;
    logic        overflow;
    logic        zero;
    logic        mdu_ready;
    logic [31:0] hi_val;
    logic [31:0] lo_val;

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output op_a;
        output op_b;
        output sa;
        output alu_op;
        output mdu_op;
        output mdu_start;
        output sel_mdu_out;
        input  ex_out;
        input  overflow;
        input  zero;
        input  mdu_ready;
        input  hi_val;
        input  lo_val;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input op_a;
        input op_b;
        input sa;
        input alu_op;
        input mdu_op;
        input mdu_start;
        input sel_mdu_out;
        input ex_out;
        input overflow;
        input zero;
        input mdu_ready;
        input hi_val;
        input lo_val;
    endclocking

    modport drv (clocking drv_cb, input rst_n);
    modport mon (clocking mon_cb, input rst_n);

endinterface
