// =============================================================================
// File Name: mips_alu.v
// Design:    MIPS32 32-bit Arithmetic Logic Unit (ALU)
// Author:    Antigravity
// Description:
//   Production-grade combinational ALU supporting MIPS32 R1 standard integer
//   instructions including arithmetic, logical, shift, comparison, and overflow.
// =============================================================================

module mips_alu (
    input  wire [31:0] op_a,      // Operand A
    input  wire [31:0] op_b,      // Operand B
    input  wire [4:0]  sa,        // Shift amount (from instruction[10:6])
    input  wire [3:0]  alu_op,    // ALU operation control
    output reg  [31:0] alu_out,   // ALU result output
    output wire        overflow,  // Signed overflow flag
    output wire        zero       // Zero flag (for branches)
);

    // ALU Operation Codes
    localparam OP_ADD  = 4'b0000;
    localparam OP_ADDU = 4'b0001;
    localparam OP_SUB  = 4'b0010;
    localparam OP_SUBU = 4'b0011;
    localparam OP_AND  = 4'b0100;
    localparam OP_OR   = 4'b0101;
    localparam OP_XOR  = 4'b0110;
    localparam OP_NOR  = 4'b0111;
    localparam OP_SLL  = 4'b1000;
    localparam OP_SRL  = 4'b1001;
    localparam OP_SRA  = 4'b1010;
    localparam OP_SLT  = 4'b1011;
    localparam OP_SLTU = 4'b1100;
    localparam OP_LUI  = 4'b1101;

    // Internal signals for adder/subtractor and overflow detection
    wire [31:0] sub_b;
    wire [32:0] adder_sum;
    wire        is_sub;

    assign is_sub = (alu_op == OP_SUB || alu_op == OP_SUBU || alu_op == OP_SLT || alu_op == OP_SLTU);
    assign sub_b = is_sub ? (~op_b + 32'd1) : op_b;
    assign adder_sum = {op_a[31], op_a} + {sub_b[31], sub_b};

    // Overflow detection (for signed ADD and SUB)
    // Overflow occurs when the operands have the same sign (for addition)
    // or opposite signs (for subtraction), and the result sign differs from expected.
    wire sign_a = op_a[31];
    wire sign_b = op_b[31];
    wire sign_r = adder_sum[31];
    
    assign overflow = (alu_op == OP_ADD) ? ((sign_a == sign_b) && (sign_r != sign_a)) :
                      (alu_op == OP_SUB) ? ((sign_a != sign_b) && (sign_r != sign_a)) : 1'b0;

    // Zero detection
    assign zero = (alu_out == 32'd0);

    // Main ALU mux
    always @(*) begin
        case (alu_op)
            OP_ADD, OP_ADDU, OP_SUB, OP_SUBU: begin
                alu_out = adder_sum[31:0];
            end
            OP_AND: begin
                alu_out = op_a & op_b;
            end
            OP_OR: begin
                alu_out = op_a | op_b;
            end
            OP_XOR: begin
                alu_out = op_a ^ op_b;
            end
            OP_NOR: begin
                alu_out = ~(op_a | op_b);
            end
            OP_SLL: begin
                alu_out = op_b << sa;
            end
            OP_SRL: begin
                alu_out = op_b >> sa;
            end
            OP_SRA: begin
                alu_out = $signed(op_b) >>> sa;
            end
            OP_SLT: begin
                // Signed comparison: check if op_a < op_b
                // If sign differs: A is negative, B is positive => A < B (slt = 1)
                // If sign is same: check the subtraction result
                if (sign_a != sign_b) begin
                    alu_out = {31'd0, sign_a};
                end else begin
                    alu_out = {31'd0, adder_sum[31]};
                end
            end
            OP_SLTU: begin
                // Unsigned comparison: op_a < op_b
                alu_out = (op_a < op_b) ? 32'd1 : 32'd0;
            end
            OP_LUI: begin
                alu_out = {op_b[15:0], 16'd0};
            end
            default: begin
                alu_out = 32'd0;
            end
        endcase
    end

endmodule
