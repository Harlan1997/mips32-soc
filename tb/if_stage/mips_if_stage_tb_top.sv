// =============================================================================
// File Name: mips_if_stage_tb_top.sv
// Design:    MIPS32 IF Stage Testbench Top Level
// Author:    Antigravity
// Description:
//   Instantiates the mips_if_stage DUT and its interface. Generates clock/reset
//   signals, registers the interface with the uvm config db, and runs the UVM test.
// =============================================================================

`timescale 1ns/1ps

module mips_if_stage_tb_top;

    import uvm_pkg::*;
    import mips_if_stage_pkg::*;

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
    mips_if_stage_if u_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // DUT Instantiation
    mips_if_stage #(
        .RESET_ADDR(32'h0000_0000)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (u_if.stall),
        .branch_taken    (u_if.branch_taken),
        .branch_target   (u_if.branch_target),
        .jump_taken      (u_if.jump_taken),
        .jump_target     (u_if.jump_target),
        .exception_req   (u_if.exception_req),
        .exception_vector(u_if.exception_vector),
        .inst_addr       (u_if.inst_addr),
        .pc              (u_if.pc),
        .pc_plus_4       (u_if.pc_plus_4),
        .adel_exception  (u_if.adel_exception)
    );

    initial begin
        // Registration
        uvm_config_db#(virtual mips_if_stage_if)::set(null, "uvm_test_top.*", "vif", u_if);

        // Waveform dumping setup
        if ($test$plusargs("DUMP_FSDB")) begin
            $fsdbDumpfile("novas.fsdb");
            $fsdbDumpvars(0, mips_if_stage_tb_top);
            $fsdbDumpMDA();
        end

        // Run Test
        run_test();
    end

endmodule
