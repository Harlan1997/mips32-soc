// =============================================================================
// File Name: mips_if_id_reg.v
// Design:    IF/ID Pipeline Register
// Author:    Antigravity
// =============================================================================

module mips_if_id_reg (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control
    input  wire        stall,
    input  wire        flush,
    
    // Inputs from IF
    input  wire [31:0] if_pc_plus_4,
    input  wire [31:0] if_inst,
    input  wire        if_except_req,
    input  wire [4:0]  if_except_code,
    input  wire        if_except_is_tlb_refill,
    input  wire        if_bpu_valid,
    input  wire        if_bpu_taken,
    input  wire [31:0] if_bpu_target,
    input  wire [1:0]  if_bpu_type,
    
    // Outputs to ID
    output reg  [31:0] id_pc_plus_4,
    output reg  [31:0] id_inst,
    output reg         id_except_req,
    output reg  [4:0]  id_except_code,
    output reg         id_except_is_tlb_refill,
    output reg         id_bpu_valid,
    output reg         id_bpu_taken,
    output reg [31:0]  id_bpu_target,
    output reg [1:0]   id_bpu_type
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc_plus_4   <= 32'd0;
            id_inst        <= 32'd0;
            id_except_req  <= 1'b0;
            id_except_code <= 5'd0;
            id_except_is_tlb_refill <= 1'b0;
            id_bpu_valid  <= 1'b0;
            id_bpu_taken  <= 1'b0;
            id_bpu_target <= 32'd0;
            id_bpu_type   <= 2'd0;
        end else if (flush) begin
            id_pc_plus_4   <= 32'd0;
            id_inst        <= 32'd0;
            id_except_req  <= 1'b0;
            id_except_code <= 5'd0;
            id_except_is_tlb_refill <= 1'b0;
            id_bpu_valid  <= 1'b0;
            id_bpu_taken  <= 1'b0;
            id_bpu_target <= 32'd0;
            id_bpu_type   <= 2'd0;
        end else if (!stall) begin
            id_pc_plus_4   <= if_pc_plus_4;
            id_inst        <= if_inst;
            id_except_req  <= if_except_req;
            id_except_code <= if_except_code;
            id_except_is_tlb_refill <= if_except_is_tlb_refill;
            id_bpu_valid  <= if_bpu_valid;
            id_bpu_taken  <= if_bpu_taken;
            id_bpu_target <= if_bpu_target;
            id_bpu_type   <= if_bpu_type;
        end
    end

endmodule
