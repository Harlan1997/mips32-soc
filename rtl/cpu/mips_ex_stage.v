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

    // ------------------------------------------------------------------
    // MDU v2: adapts 3-bit legacy op → 4-bit mips_mdu_v2 op, muxes
    // MFHI/MFLO output. v1 mips_mdu was deleted after signoff #12
    // validated the cutover.
    // ------------------------------------------------------------------
    reg [3:0] mdu_v2_op;
    always @(*) begin
        case (mdu_op)
            3'b000: mdu_v2_op = 4'd0;  // MULT
            3'b001: mdu_v2_op = 4'd1;  // MULTU
            3'b010: mdu_v2_op = 4'd2;  // DIV
            3'b011: mdu_v2_op = 4'd3;  // DIVU
            3'b100: mdu_v2_op = 4'd6;  // MTHI
            3'b101: mdu_v2_op = 4'd7;  // MTLO
            3'b110: mdu_v2_op = 4'd4;  // MFHI
            3'b111: mdu_v2_op = 4'd5;  // MFLO
            default: mdu_v2_op = 4'd0;
        endcase
    end
    wire mdu_v2_busy, mdu_v2_done;
    mips_mdu_v2 u_mips_mdu (
        .clk        (clk),
        .rst_n      (rst_n),
        .issue_valid(mdu_start),
        .op         (mdu_v2_op),
        .rs_val     (op_a),
        .rt_val     (op_b),
        .hi_out     (hi_val),
        .lo_out     (lo_val),
        .busy       (mdu_v2_busy),
        .done_pulse (mdu_v2_done)
    );
    assign mdu_ready = ~mdu_v2_busy;
    reg [31:0] mdu_out_r;
    always @(*) begin
        case (mdu_op)
            3'b110:  mdu_out_r = hi_val;
            3'b111:  mdu_out_r = lo_val;
            default: mdu_out_r = 32'd0;
        endcase
    end
    assign mdu_out = mdu_out_r;

    // Output Selection: ALU vs MDU
    assign ex_out = sel_mdu_out ? mdu_out : alu_out;

endmodule
