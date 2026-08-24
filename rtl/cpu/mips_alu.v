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
    input  wire [4:0]  msbd,      // EXT/INS most-significant bit (rd field)
    input  wire [4:0]  alu_op,    // ALU operation control (Phase B ISA R2: 5-bit)
    output reg  [31:0] alu_out,   // ALU result output
    output wire        overflow,  // Signed overflow flag
    output wire        zero       // Zero flag (for branches)
);

    // ALU Operation Codes (Phase B ISA R2: extended to 5-bit)
    localparam OP_ADD  = 5'b00000;
    localparam OP_ADDU = 5'b00001;
    localparam OP_SUB  = 5'b00010;
    localparam OP_SUBU = 5'b00011;
    localparam OP_AND  = 5'b00100;
    localparam OP_OR   = 5'b00101;
    localparam OP_XOR  = 5'b00110;
    localparam OP_NOR  = 5'b00111;
    localparam OP_SLL  = 5'b01000;
    localparam OP_SRL  = 5'b01001;
    localparam OP_SRA  = 5'b01010;
    localparam OP_SLT  = 5'b01011;
    localparam OP_SLTU = 5'b01100;
    localparam OP_LUI  = 5'b01101;
    // Phase B ISA R2 additions
    localparam OP_CLZ      = 5'b10000; // Count leading zeros of op_a
    localparam OP_CLO      = 5'b10001; // Count leading ones of op_a
    localparam OP_SEB      = 5'b10010; // Sign-extend byte from op_b[7:0]
    localparam OP_SEH      = 5'b10011; // Sign-extend halfword from op_b[15:0]
    localparam OP_WSBH     = 5'b10100; // Word swap bytes within halfwords (op_b)
    localparam OP_ROTR     = 5'b10101; // Rotate right op_b by sa
    localparam OP_MOV_PASS = 5'b10110; // Pass op_a (for MOVN/MOVZ; write gate in id_stage)
    localparam OP_EXT      = 5'b10111; // Extract size=(rd+1) bits at pos
    localparam OP_INS      = 5'b11000; // Insert bits [rd:pos]
    localparam OP_BITSWAP  = 5'b11001; // Reverse bit order within each byte

    // SPECIAL3 EXT uses rd as size-1; INS uses rd as the high bit. The EX
    // wrapper supplies rd separately from the ALU shift amount.
    // Internal signals for adder/subtractor and overflow detection
    wire [31:0] sub_b;
    wire [32:0] adder_sum;
    wire        is_sub;
    wire [5:0]  field_width = {1'b0, msbd} - {1'b0, sa} + 6'd1;
    wire [31:0] field_mask = (field_width == 6'd32) ? 32'hFFFF_FFFF :
                              (32'hFFFF_FFFF >> (6'd32 - field_width));
    wire [5:0]  ext_width = {1'b0, msbd} + 6'd1;
    wire [31:0] ext_mask = (ext_width == 6'd32) ? 32'hFFFF_FFFF :
                           (32'hFFFF_FFFF >> (6'd32 - ext_width));

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

    // Phase B ISA R2 helpers — CLZ / CLO: parametric priority encoder.
    reg [5:0] clz_result;
    reg [5:0] clo_result;
    integer   ci;
    integer   bi;
    always @(*) begin
        clz_result = 6'd32;   // all zeros → 32
        clo_result = 6'd32;   // all ones  → 32
        for (ci = 31; ci >= 0; ci = ci - 1) begin
            if (op_a[ci] == 1'b1 && clz_result == 6'd32)
                clz_result = 6'd31 - ci[5:0];
            if (op_a[ci] == 1'b0 && clo_result == 6'd32)
                clo_result = 6'd31 - ci[5:0];
        end
    end

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
            OP_CLZ: begin
                alu_out = { 26'd0, clz_result };
            end
            OP_CLO: begin
                alu_out = { 26'd0, clo_result };
            end
            OP_SEB: begin
                alu_out = { {24{op_b[7]}}, op_b[7:0] };
            end
            OP_SEH: begin
                alu_out = { {16{op_b[15]}}, op_b[15:0] };
            end
            OP_WSBH: begin
                // Swap byte order within each halfword of op_b
                alu_out = { op_b[23:16], op_b[31:24], op_b[7:0], op_b[15:8] };
            end
            OP_ROTR: begin
                // Rotate-right op_b by sa via double-word right shift trick.
                // Guarantees correct behaviour at sa=0 (which << 32 would break).
                alu_out = ({op_b, op_b} >> sa) & 32'hFFFF_FFFF;
            end
            OP_MOV_PASS: begin
                alu_out = op_a;
            end
            OP_EXT: begin
                alu_out = (op_a >> sa) & ext_mask;
            end
            OP_INS: begin
                // The architectural destination/base is rt (op_b), while
                // the inserted field is taken from rs (op_a).
                alu_out = (op_b & ~(field_mask << sa)) |
                          ((op_a & field_mask) << sa);
            end
            OP_BITSWAP: begin
                alu_out = 32'd0;
                for (bi = 0; bi < 4; bi = bi + 1) begin
                    alu_out[bi*8 + 0] = op_b[bi*8 + 7];
                    alu_out[bi*8 + 1] = op_b[bi*8 + 6];
                    alu_out[bi*8 + 2] = op_b[bi*8 + 5];
                    alu_out[bi*8 + 3] = op_b[bi*8 + 4];
                    alu_out[bi*8 + 4] = op_b[bi*8 + 3];
                    alu_out[bi*8 + 5] = op_b[bi*8 + 2];
                    alu_out[bi*8 + 6] = op_b[bi*8 + 1];
                    alu_out[bi*8 + 7] = op_b[bi*8 + 0];
                end
            end
            default: begin
                alu_out = 32'd0;
            end
        endcase
    end

endmodule
