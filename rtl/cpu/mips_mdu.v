// =============================================================================
// File Name: mips_mdu.v
// Design:    MIPS32 Multiplier-Divider Unit (MDU)
// Author:    Antigravity
// Description:
//   Production-grade, multi-cycle Multiplier-Divider Unit.
//   Supports MULT/MULTU (2-cycle pipelined multiplication) and
//   DIV/DIVU (32-cycle sequential restoring division).
//   Includes HI/LO registers and MTHI/MTLO/MFHI/MFLO control.
// =============================================================================

module mips_mdu (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] op_a,      // Operand A
    input  wire [31:0] op_b,      // Operand B
    input  wire [2:0]  mdu_op,    // MDU Operation
    input  wire        start,     // Start multi-cycle operation
    output reg  [31:0] hi,        // HI Register output
    output reg  [31:0] lo,        // LO Register output
    output reg         ready,     // Operation complete
    output reg  [31:0] mdu_out    // Combinational read output for MFHI/MFLO
);

    // MDU Operation Codes
    localparam OP_MULT  = 3'b000;
    localparam OP_MULTU = 3'b001;
    localparam OP_DIV   = 3'b010;
    localparam OP_DIVU  = 3'b011;
    localparam OP_MTHI  = 3'b100;
    localparam OP_MTLO  = 3'b101;
    localparam OP_MFHI  = 3'b110;
    localparam OP_MFLO  = 3'b111;

    // FSM States
    localparam STATE_IDLE = 2'b00;
    localparam STATE_MULT = 2'b01;
    localparam STATE_DIV  = 2'b10;

    reg [1:0] state;
    reg [5:0] count; // Counter for division steps

    // Multiplication pipeline registers
    reg [31:0] mult_a_reg;
    reg [31:0] mult_b_reg;
    reg        mult_signed_reg;
    reg        mult_active;

    // Division registers
    reg [31:0] div_divisor;
    reg [63:0] div_rem_quot; // Holds remainder in upper 32 bits, quotient in lower 32 bits
    reg        div_sign_quot; // Sign of the final quotient
    reg        div_sign_rem;  // Sign of the final remainder
    reg        div_active;

    // Helper wires and regs for FSM operations
    wire [63:0] next_rem_quot;
    wire [32:0] sub_res;
    wire [63:0] mult_prod_signed   = $signed(mult_a_reg) * $signed(mult_b_reg);
    wire [63:0] mult_prod_unsigned = mult_a_reg * mult_b_reg;
    wire [63:0] mult_prod          = mult_signed_reg ? mult_prod_signed : mult_prod_unsigned;
    reg  [31:0] final_quot;
    reg  [31:0] final_rem;

    assign next_rem_quot = {div_rem_quot[62:0], 1'b0};
    assign sub_res       = {1'b0, next_rem_quot[63:32]} - {1'b0, div_divisor};

    // MFLO/MFHI read logic (combinational to match ALU outputs in EX stage)
    always @(*) begin
        case (mdu_op)
            OP_MFHI: mdu_out = hi;
            OP_MFLO: mdu_out = lo;
            default: mdu_out = 32'd0;
        endcase
    end

    // MDU Control FSM and Operation Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hi              <= 32'd0;
            lo              <= 32'd0;
            state           <= STATE_IDLE;
            count           <= 6'd0;
            ready           <= 1'b1;
            mult_active     <= 1'b0;
            div_active      <= 1'b0;
            mult_a_reg      <= 32'd0;
            mult_b_reg      <= 32'd0;
            mult_signed_reg <= 1'b0;
            div_divisor     <= 32'd0;
            div_rem_quot    <= 64'd0;
            div_sign_quot   <= 1'b0;
            div_sign_rem    <= 1'b0;
            final_quot      <= 32'd0;
            final_rem       <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    ready <= 1'b1;
                    if (start) begin
                        case (mdu_op)
                            OP_MULT, OP_MULTU: begin
                                state           <= STATE_MULT;
                                ready           <= 1'b0;
                                mult_a_reg      <= op_a;
                                mult_b_reg      <= op_b;
                                mult_signed_reg <= (mdu_op == OP_MULT);
                                mult_active     <= 1'b1;
                            end
                            OP_DIV, OP_DIVU: begin
                                state <= STATE_DIV;
                                ready <= 1'b0;
                                count <= 6'd0;
                                
                                // Sign preprocessing
                                if (mdu_op == OP_DIV) begin
                                    div_sign_quot <= op_a[31] ^ op_b[31];
                                    div_sign_rem  <= op_a[31];
                                    div_divisor   <= op_b[31] ? (~op_b + 32'd1) : op_b;
                                    div_rem_quot  <= {32'd0, op_a[31] ? (~op_a + 32'd1) : op_a};
                                end else begin
                                    div_sign_quot <= 1'b0;
                                    div_sign_rem  <= 1'b0;
                                    div_divisor   <= op_b;
                                    div_rem_quot  <= {32'd0, op_a};
                                end
                            end
                            default: ;
                        endcase
                    end else begin
                        // Single-cycle register writes
                        if (mdu_op == OP_MTHI) begin
                            hi <= op_a;
                        end else if (mdu_op == OP_MTLO) begin
                            lo <= op_a;
                        end
                    end
                end

                STATE_MULT: begin
                    // Multiplication is completed in 2 cycles total
                    // This is the 2nd cycle of multiplication
                    if (mult_active) begin
                        hi          <= mult_prod[63:32];
                        lo          <= mult_prod[31:0];
                        ready       <= 1'b1;
                        mult_active <= 1'b0;
                        state       <= STATE_IDLE;
                    end
                end

                STATE_DIV: begin
                    if (count < 6'd32) begin
                        // Shift left and subtract
                        // div_rem_quot is shifted left by 1, and the next subtraction is checked
                        if (sub_res[32] == 1'b0) begin
                            // Subtraction succeeded (remainder is >= divisor)
                            div_rem_quot <= {sub_res[31:0], next_rem_quot[31:1], 1'b1};
                        end else begin
                            // Subtraction failed (remainder is < divisor)
                            div_rem_quot <= {next_rem_quot[63:32], next_rem_quot[31:1], 1'b0};
                        end
                        count <= count + 6'd1;
                    end else begin
                        // Post-processing and writeback
                        final_quot = div_rem_quot[31:0];
                        final_rem  = div_rem_quot[63:32];

                        // division by zero check (avoid hang, return undefined values)
                        if (div_divisor == 32'd0) begin
                            hi <= 32'd0;
                            lo <= 32'd0;
                        end else begin
                            // Handle signed adjustments
                            if (div_sign_quot) begin
                                lo <= ~final_quot + 32'd1;
                            end else begin
                                lo <= final_quot;
                            end
                            
                            if (div_sign_rem) begin
                                hi <= ~final_rem + 32'd1;
                            end else begin
                                hi <= final_rem;
                            end
                        end
                        
                        ready <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

