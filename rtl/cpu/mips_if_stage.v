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
    input  wire        branch_likely_annul, // Not-taken branch-likely skips delay slot
    input  wire        branch_likely_taken, // Taken branch-likely executes delay slot
    input  wire [31:0] branch_target,    // Branch target PC
    input  wire        jump_taken,       // Jump instruction detected
    input  wire [31:0] jump_target,       // Jump target PC
    input  wire        bpu_enable,
    input  wire        bpu_predict_valid,
    input  wire        bpu_predict_taken,
    input  wire [31:0] bpu_predict_target,
    input  wire        bpu_recover,
    input  wire [31:0] bpu_recover_target,
    
    // Exception Handling Interface
    input  wire        exception_req,    // Redirect PC to exception handler
    input  wire [31:0] exception_vector,  // Exception vector address
    input  wire        ctx_save_req,
    output wire        ctx_save_done,
    input  wire        ctx_restore_req,
    input  wire [31:0] ctx_restore_pc,
    output wire        ctx_restore_done,
    
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
    reg        bpu_delay_pending;
    reg [31:0] bpu_delay_target;
    reg        branch_likely_delay_pending;
    reg [31:0] branch_likely_delay_target;

    // Next PC selection logic
    always @(*) begin
        if (exception_req) begin
            next_pc = exception_vector;
        end else if (stall) begin
            next_pc = pc;
        end else if (bpu_recover) begin
            next_pc = bpu_recover_target;
        end else if (branch_likely_annul) begin
            // `pc` is the look-ahead/delay-slot fetch address when the
            // branch is resolved in ID.  Advancing one word skips that
            // already-fetched slot and lands on the sequential target.
            next_pc = pc + 32'd4;
        end else if (branch_likely_delay_pending) begin
            next_pc = branch_likely_delay_target;
        end else if (branch_likely_taken) begin
            // Fetch the architectural delay slot first; redirect on the
            // following cycle using the saved branch target.
            // `pc` is the architectural delay-slot address here.
            next_pc = pc;
        end else if (branch_taken) begin
            next_pc = branch_target;
        end else if (jump_taken) begin
            next_pc = jump_target;
        end else if (bpu_delay_pending) begin
            next_pc = bpu_delay_target;
        end else begin
            next_pc = pc + 32'd4;
        end
    end

    // PC Register update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= RESET_ADDR;
            bpu_delay_pending <= 1'b0;
            bpu_delay_target <= 32'd0;
            branch_likely_delay_pending <= 1'b0;
            branch_likely_delay_target <= 32'd0;
        end else begin
            if (ctx_restore_req)
                pc <= ctx_restore_pc;
            else
                pc <= next_pc;

            if (ctx_restore_req || exception_req || bpu_recover) begin
                bpu_delay_pending <= 1'b0;
                branch_likely_delay_pending <= 1'b0;
            end else if (branch_likely_delay_pending) begin
                branch_likely_delay_pending <= 1'b0;
            end else if (!stall) begin
                if (branch_likely_taken) begin
                    branch_likely_delay_pending <= 1'b1;
                    branch_likely_delay_target <= branch_target;
                end
                if (bpu_delay_pending) begin
                    bpu_delay_pending <= 1'b0;
                end else if (bpu_enable && bpu_predict_valid &&
                             bpu_predict_taken && !branch_taken &&
                             !jump_taken) begin
                    bpu_delay_pending <= 1'b1;
                    bpu_delay_target <= bpu_predict_target;
                end
            end
        end
    end

`ifdef DEBUG_BRANCH_LIKELY
    always @(posedge clk) begin
        if (rst_n && (branch_likely_annul || branch_likely_taken ||
                      branch_likely_delay_pending))
            $display("BRLIKELY t=%0t pc=%08h next=%08h taken=%b annul=%b pending=%b target=%08h",
                     $time, pc, next_pc, branch_likely_taken,
                     branch_likely_annul, branch_likely_delay_pending,
                     branch_likely_delay_target);
    end
`endif

    // Cache Interface
    assign inst_req  = 1'b1; // Always trying to fetch
    assign ctx_save_done = ctx_save_req;
    assign ctx_restore_done = ctx_restore_req;
    // I-cache returns the previous cycle's request on a hit while accepting
    // the next request. Keep this one-cycle look-ahead aligned with
    // pc_plus_4, which tags the returning instruction in IF/ID. During a
    // reset/miss stall next_pc equals pc, so the reset-vector word is still
    // the first address requested.
    assign inst_addr = next_pc;
    assign pc_plus_4 = pc + 32'd4;
    
    // Stall if data is not ready
    assign stall_req_if = ~inst_data_ok;

    // Address Error on Instruction Fetch (AdEL): PC must be word-aligned
    assign adel_exception = (pc[1:0] != 2'b00);

endmodule
