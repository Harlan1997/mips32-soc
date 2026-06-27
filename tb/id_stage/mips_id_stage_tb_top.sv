// =============================================================================
// File Name: mips_id_stage_tb_top.sv
// Design:    MIPS32 ID Stage Testbench Top Level
// Author:    Antigravity
// Description:
//   Instantiates the mips_id_stage DUT and its interface. Generates clock/reset
//   signals, sets up the virtual interface config db, and runs the UVM test.
// =============================================================================

`timescale 1ns/1ps

module mips_id_stage_tb_top;

    import uvm_pkg::*;
    import mips_id_stage_pkg::*;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Clock generator (100 MHz)
    always #5 clk = ~clk;

    // Reset generator
    initial begin
        clk = 0;
        rst_n = 0;
        #45;
        rst_n = 1;
    end

    // Interface
    mips_id_stage_if u_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // DUT
    mips_id_stage u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .inst         (u_if.inst),
        .pc_plus_4    (u_if.pc_plus_4),
        .rf_waddr     (u_if.rf_waddr),
        .rf_wdata     (u_if.rf_wdata),
        .rf_we        (u_if.rf_we),
        .fw_ex_we     (u_if.fw_ex_we),
        .fw_ex_waddr  (u_if.fw_ex_waddr),
        .fw_ex_val    (u_if.fw_ex_val),
        .fw_mem_we    (u_if.fw_mem_we),
        .fw_mem_waddr (u_if.fw_mem_waddr),
        .fw_mem_val   (u_if.fw_mem_val),
        .fw_wb_we     (u_if.fw_wb_we),
        .fw_wb_waddr  (u_if.fw_wb_waddr),
        .fw_wb_val    (u_if.fw_wb_val),
        .ex_mem_read  (u_if.ex_mem_read),
        .ex_waddr     (u_if.ex_waddr),
        .stall_req    (u_if.stall_req),
        .branch_taken (u_if.branch_taken),
        .branch_target(u_if.branch_target),
        .jump_taken   (u_if.jump_taken),
        .jump_target  (u_if.jump_target),
        .val_rs       (u_if.val_rs),
        .val_rt       (u_if.val_rt),
        .imm_ext      (u_if.imm_ext),
        .waddr_out    (u_if.waddr_out),
        .sa_out       (u_if.sa_out),
        .rs_addr      (u_if.rs_addr),
        .rt_addr      (u_if.rt_addr),
        .rd_addr      (u_if.rd_addr),
        .alu_op       (u_if.alu_op),
        .mdu_op       (u_if.mdu_op),
        .mdu_start    (u_if.mdu_start),
        .sel_mdu_out  (u_if.sel_mdu_out),
        .alu_src      (u_if.alu_src),
        .reg_write    (u_if.reg_write),
        .mem_read     (u_if.mem_read),
        .mem_write    (u_if.mem_write),
        .mem_op       (u_if.mem_op),
        .mem_to_reg   (u_if.mem_to_reg),
        .illegal_inst (u_if.illegal_inst)
    );

    initial begin
        // Virtual interface registration
        uvm_config_db#(virtual mips_id_stage_if)::set(null, "uvm_test_top.*", "vif", u_if);
        
        // Waveform dumping setup
        if ($test$plusargs("DUMP_FSDB")) begin
            $fsdbDumpfile("novas.fsdb");
            $fsdbDumpvars(0, mips_id_stage_tb_top);
            $fsdbDumpMDA();
        end

        // Run the UVM Test
        run_test();
    end

endmodule
