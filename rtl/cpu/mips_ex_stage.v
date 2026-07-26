// =============================================================================
// File Name: mips_ex_stage.v
// Design:    MIPS32 EX (Execute) Stage Wrapper
// Author:    Antigravity
// Description:
//   Ties together the combinational ALU and multi-cycle MDU.
//   Exposes status flags and arbitration for pipeline stalling.
// =============================================================================

module mips_ex_stage (
    input  wire        clk,
    input  wire        rst_n,
    
    // Operands and Control
    input  wire [31:0] op_a,        // Operand A
    input  wire [31:0] op_b,        // Operand B
    input  wire [4:0]  sa,          // Shift amount
    input  wire [4:0]  alu_op,      // ALU control (Phase B ISA R2: 5-bit)
    input  wire [2:0]  mdu_op,      // MDU control
    input  wire        mdu_start,   // Start multi-cycle MDU op
    input  wire        sel_mdu_out, // 1: Output MDU read data (MFHI/MFLO); 0: Output ALU result
    
    // Outputs
    output wire [31:0] ex_out,      // EX stage output result
    output wire        overflow,    // Signed overflow flag from ALU
    output wire        zero,        // Zero flag from ALU
    output wire        mdu_ready,   // MDU busy/ready state
    output wire [31:0] hi_val,      // Current HI value
    output wire [31:0] lo_val       // Current LO value
);

    wire [31:0] alu_out;
    wire [31:0] mdu_out;

    // Instantiate ALU
    mips_alu u_mips_alu (
        .op_a    (op_a),
        .op_b    (op_b),
        .sa      (sa),
        .alu_op  (alu_op),
        .alu_out (alu_out),
        .overflow(overflow),
        .zero    (zero)
    );

    // Instantiate Multiplier-Divider Unit (MDU)
    mips_mdu u_mips_mdu (
        .clk    (clk),
        .rst_n  (rst_n),
        .op_a   (op_a),
        .op_b   (op_b),
        .mdu_op (mdu_op),
        .start  (mdu_start),
        .hi     (hi_val),
        .lo     (lo_val),
        .ready  (mdu_ready),
        .mdu_out(mdu_out)
    );

    // Output Selection: ALU vs MDU
    assign ex_out = sel_mdu_out ? mdu_out : alu_out;

endmodule
