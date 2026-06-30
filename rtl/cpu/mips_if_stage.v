// =============================================================================
// File Name: mips_if_stage.v
// Design:    MIPS32 IF (Instruction Fetch) Stage
// Author:    Antigravity
// Description:
//   Manages the Program Counter (PC) register and next PC selection logic.
//   Handles branch/jump targets, pipeline stalls, exception vectors, and
//   instruction address alignment exception checks (AdEL).
// =============================================================================

module mips_if_stage #(
    parameter RESET_ADDR = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Pipeline Stall Control
    input  wire        stall,            // Keep current PC value
    
    // Control Decisions (from Decode stage)
    input  wire        branch_taken,     // Branch condition met
    input  wire [31:0] branch_target,    // Branch target PC
    input  wire        jump_taken,       // Jump instruction detected
    input  wire [31:0] jump_target,       // Jump target PC
    
    // Exception Handling Interface
    input  wire        exception_req,    // Redirect PC to exception handler
    input  wire [31:0] exception_vector,  // Exception vector address
    
    // Outputs to Instruction Cache
    output wire        inst_req,
    output wire [31:0] inst_addr,        // Memory fetch address (current PC)
    input  wire        inst_addr_ok,
    input  wire        inst_data_ok,
    
    // Outputs to Pipeline Control
    output wire        stall_req_if,
    
    // Outputs to ID Stage
    output reg  [31:0] pc,               // Current PC register value
    output wire [31:0] pc_plus_4,        // Increment PC (PC + 4)
    output wire        adel_exception    // Address Error Exception on instruction fetch
);

    reg [31:0] next_pc;

    // Next PC selection logic
    always @(*) begin
        if (exception_req) begin
            next_pc = exception_vector;
        end else if (stall) begin
            next_pc = pc;
        end else if (branch_taken) begin
            next_pc = branch_target;
        end else if (jump_taken) begin
            next_pc = jump_target;
        end else begin
            next_pc = pc + 32'd4;
        end
    end

    // PC Register update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= RESET_ADDR;
        end else begin
            pc <= next_pc;
        end
    end

    // Cache Interface
    assign inst_req  = 1'b1; // Always trying to fetch
    assign inst_addr = next_pc;
    assign pc_plus_4 = pc + 32'd4;
    
    // Stall if data is not ready
    assign stall_req_if = ~inst_data_ok;

    // Address Error on Instruction Fetch (AdEL): PC must be word-aligned
    assign adel_exception = (pc[1:0] != 2'b00);

endmodule
