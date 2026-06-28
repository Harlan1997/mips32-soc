// =============================================================================
// File Name: mips_id_ex_reg.v
// Design:    ID/EX Pipeline Register
// Author:    Antigravity
// =============================================================================

module mips_id_ex_reg (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control
    input  wire        stall,
    input  wire        flush,
    
    // Data Inputs from ID
    input  wire [31:0] id_val_rs,
    input  wire [31:0] id_val_rt,
    input  wire [31:0] id_imm_ext,
    input  wire [31:0] id_pc_plus_8,
    input  wire [4:0]  id_waddr,
    input  wire [4:0]  id_rd_addr,
    input  wire [4:0]  id_sa,
    
    // Control Inputs from ID
    input  wire [3:0]  id_alu_op,
    input  wire [2:0]  id_mdu_op,
    input  wire        id_mdu_start,
    input  wire        id_illegal_inst,
    input  wire        id_except_req,
    input  wire [4:0]  id_except_code,
    input  wire        id_cp0_we,
    input  wire        id_is_eret,
    input  wire        id_sel_mdu_out,
    input  wire        id_alu_src,

    input  wire        id_reg_write,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire [2:0]  id_mem_op,
    input  wire [1:0]  id_mem_to_reg,
    
    // Data Outputs to EX
    output reg  [31:0] ex_val_rs,
    output reg  [31:0] ex_val_rt,
    output reg  [31:0] ex_imm_ext,
    output reg  [31:0] ex_pc_plus_8,
    output reg  [4:0]  ex_waddr,
    output reg  [4:0]  ex_rd_addr,
    output reg  [4:0]  ex_sa,
    
    // Control Outputs to EX
    output reg  [3:0]  ex_alu_op,
    output reg  [2:0]  ex_mdu_op,
    output reg         ex_mdu_start,
    output reg         ex_illegal_inst,
    output reg         ex_except_req,
    output reg  [4:0]  ex_except_code,
    output reg         ex_cp0_we,
    output reg         ex_is_eret,
    output reg         ex_sel_mdu_out,
    output reg         ex_alu_src,
    output reg         ex_reg_write,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg  [2:0]  ex_mem_op,
    output reg  [1:0]  ex_mem_to_reg
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_val_rs      <= 32'd0;
            ex_val_rt      <= 32'd0;
            ex_imm_ext     <= 32'd0;
            ex_pc_plus_8   <= 32'd0;
            ex_waddr       <= 5'd0;
            ex_rd_addr     <= 5'd0;
            ex_sa          <= 5'd0;
            
            ex_alu_op      <= 4'd0;
            ex_mdu_op      <= 3'd0;
            ex_mdu_start   <= 1'b0;
            ex_illegal_inst<= 1'b0;
            ex_except_req  <= 1'b0;
            ex_except_code <= 5'd0;
            ex_cp0_we      <= 1'b0;
            ex_is_eret     <= 1'b0;
            ex_sel_mdu_out <= 1'b0;
            ex_alu_src     <= 1'b0;
            ex_reg_write   <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_mem_op      <= 3'd0;
            ex_mem_to_reg  <= 2'd0;
        end else if (flush) begin
            ex_val_rs      <= 32'd0;
            ex_val_rt      <= 32'd0;
            ex_imm_ext     <= 32'd0;
            ex_pc_plus_8   <= 32'd0;
            ex_waddr       <= 5'd0;
            ex_rd_addr     <= 5'd0;
            ex_sa          <= 5'd0;
            
            ex_alu_op      <= 4'd0;
            ex_mdu_op      <= 3'd0;
            ex_mdu_start   <= 1'b0;
            ex_illegal_inst<= 1'b0;
            ex_except_req  <= 1'b0;
            ex_except_code <= 5'd0;
            ex_cp0_we      <= 1'b0;
            ex_is_eret     <= 1'b0;
            ex_sel_mdu_out <= 1'b0;
            ex_alu_src     <= 1'b0;
            ex_reg_write   <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_mem_op      <= 3'd0;
            ex_mem_to_reg  <= 2'd0;
        end else if (!stall) begin
            ex_val_rs      <= id_val_rs;
            ex_val_rt      <= id_val_rt;
            ex_imm_ext     <= id_imm_ext;
            ex_pc_plus_8   <= id_pc_plus_8;
            ex_waddr       <= id_waddr;
            ex_rd_addr     <= id_rd_addr;
            ex_sa          <= id_sa;
            
            ex_alu_op      <= id_alu_op;
            ex_mdu_op      <= id_mdu_op;
            ex_mdu_start   <= id_mdu_start;
            ex_illegal_inst<= id_illegal_inst;
            ex_except_req  <= id_except_req;
            ex_except_code <= id_except_code;
            ex_cp0_we      <= id_cp0_we;
            ex_is_eret     <= id_is_eret;
            ex_sel_mdu_out <= id_sel_mdu_out;
            ex_alu_src     <= id_alu_src;
            ex_reg_write   <= id_reg_write;
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
            ex_mem_op      <= id_mem_op;
            ex_mem_to_reg  <= id_mem_to_reg;
        end
    end

endmodule
