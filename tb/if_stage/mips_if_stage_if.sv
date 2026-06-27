// =============================================================================
// File Name: mips_if_stage_if.sv
// Design:    MIPS32 IF Stage Verification Interface
// Author:    Antigravity
// Description:
//   SystemVerilog interface connecting the UVM driver/monitor to the IF stage.
// =============================================================================

interface mips_if_stage_if (input wire clk, input wire rst_n);

    // Inputs to DUT
    logic        stall;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        jump_taken;
    logic [31:0] jump_target;
    logic        exception_req;
    logic [31:0] exception_vector;

    // Outputs from DUT
    logic [31:0] inst_addr;
    logic [31:0] pc;
    logic [31:0] pc_plus_4;
    logic        adel_exception;

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output stall;
        output branch_taken;
        output branch_target;
        output jump_taken;
        output jump_target;
        output exception_req;
        output exception_vector;

        input  inst_addr;
        input  pc;
        input  pc_plus_4;
        input  adel_exception;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input  stall;
        input  branch_taken;
        input  branch_target;
        input  jump_taken;
        input  jump_target;
        input  exception_req;
        input  exception_vector;
        input  inst_addr;
        input  pc;
        input  pc_plus_4;
        input  adel_exception;
    endclocking

    modport drv (clocking drv_cb, input rst_n);
    modport mon (clocking mon_cb, input rst_n);

endinterface
