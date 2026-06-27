// =============================================================================
// File Name: mips_ex_stage_tb_top.sv
// Design:    MIPS32 EX Stage Testbench Top Level
// Author:    Antigravity
// Description:
//   SystemVerilog testbench top instantiating the DUT, interface,
//   generating clock/reset, setting up waveform dumping, and running UVM.
// =============================================================================

`timescale 1ns/1ps

module mips_ex_stage_tb_top;

    import uvm_pkg::*;
    import mips_ex_stage_pkg::*;

    // Clock and Reset signals
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

    // Interface instantiation
    mips_ex_stage_if u_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // DUT instantiation
    mips_ex_stage u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .op_a        (u_if.op_a),
        .op_b        (u_if.op_b),
        .sa          (u_if.sa),
        .alu_op      (u_if.alu_op),
        .mdu_op      (u_if.mdu_op),
        .mdu_start   (u_if.mdu_start),
        .sel_mdu_out (u_if.sel_mdu_out),
        .ex_out      (u_if.ex_out),
        .overflow    (u_if.overflow),
        .zero        (u_if.zero),
        .mdu_ready   (u_if.mdu_ready),
        .hi_val      (u_if.hi_val),
        .lo_val      (u_if.lo_val)
    );

    // Run UVM Test and Setup Waveform Dumping
    initial begin
        // Setup configuration database for virtual interface
        uvm_config_db#(virtual mips_ex_stage_if)::set(null, "uvm_test_top.*", "vif", u_if);
        
        // Verdi / FSDB Waveform dumping (checked via plusargs or compile options)
        if ($test$plusargs("DUMP_FSDB")) begin
            $fsdbDumpfile("novas.fsdb");
            $fsdbDumpvars(0, mips_ex_stage_tb_top);
            // Dump multi-dimensional arrays as well
            $fsdbDumpMDA();
        end

        // Run UVM
        run_test();
    end

endmodule
