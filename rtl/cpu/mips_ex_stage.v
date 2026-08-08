// =============================================================================
// File Name: mips_ex_stage.v
// Design:    MIPS32 EX (Execute) Stage Wrapper
// Author:    Antigravity
// Description:
//   Ties together the combinational ALU and multi-cycle MDU.
//   Exposes status flags and arbitration for pipeline stalling.
// =============================================================================

`include "soc_config.vh"

module mips_ex_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    
    // Operands and Control
    input  wire [31:0] op_a,        // Operand A
    input  wire [31:0] op_b,        // Operand B
    input  wire [4:0]  sa,          // Shift amount
    input  wire [4:0]  alu_op,      // ALU control (Phase B ISA R2: 5-bit)
    input  wire [3:0]  mdu_op,      // MDU control (Phase 4B: 4-bit)
    input  wire        mdu_start,   // Start multi-cycle MDU op
    input  wire        sel_mdu_out, // 1: Output MDU read data (MFHI/MFLO/MUL); 0: Output ALU result
    
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

    // ------------------------------------------------------------------
    // MDU: receives a one-cycle issue pulse. The wrapper reports not-ready
    // during the launch cycle so GPR-writing MUL cannot leave EX before LO is
    // updated.
    // ------------------------------------------------------------------
    wire mdu_busy, mdu_done;
    mips_mdu u_mips_mdu (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),
        .issue_valid(mdu_start),
        .op         (mdu_op),
        .rs_val     (op_a),
        .rt_val     (op_b),
        .hi_out     (hi_val),
        .lo_out     (lo_val),
        .busy       (mdu_busy),
        .done_pulse (mdu_done)
    );
    assign mdu_ready = ~(mdu_busy | mdu_start);
    reg [31:0] mdu_out_r;
    always @(*) begin
        case (mdu_op)
            4'd4:    mdu_out_r = hi_val; // MFHI
            4'd5:    mdu_out_r = lo_val; // MFLO
            4'd12:   mdu_out_r = lo_val; // MUL (low 32 bits)
            default: mdu_out_r = 32'd0;
        endcase
    end
    assign mdu_out = mdu_out_r;

    // Output Selection: ALU vs MDU
    assign ex_out = sel_mdu_out ? mdu_out : alu_out;

endmodule
