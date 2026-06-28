// =============================================================================
// File Name: mips_mem_wb_reg.v
// Design:    MEM/WB Pipeline Register
// Author:    Antigravity
// =============================================================================

module mips_mem_wb_reg (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control
    input  wire        stall,
    input  wire        flush,
    
    // Data Inputs from MEM
    input  wire [31:0] mem_rdata_fmt,
    input  wire [31:0] mem_ex_out,
    input  wire [31:0] mem_pc_plus_8,
    input  wire [4:0]  mem_waddr,
    input  wire [4:0]  mem_rd_addr,
    
    // Control Inputs from MEM
    input  wire        mem_reg_write,
    
    // CP0
    input  wire        mem_cp0_we,
    input  wire        mem_is_eret,
    
    // Exceptions
    input  wire        mem_except_req,
    input  wire [4:0]  mem_except_code,
    input  wire [1:0]  mem_mem_to_reg,
    
    // Data Outputs to WB
    output reg  [31:0] wb_rdata_fmt,
    output reg  [31:0] wb_ex_out,
    output reg  [31:0] wb_pc_plus_8,
    output reg  [4:0]  wb_waddr,
    output reg  [4:0]  wb_rd_addr,
    
    // Control Outputs to WB
    output reg         wb_reg_write,
    
    // CP0
    output reg         wb_cp0_we,
    output reg         wb_is_eret,
    
    // Exceptions
    output reg         wb_except_req,
    output reg  [4:0]  wb_except_code,
    output reg  [1:0]  wb_mem_to_reg
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_rdata_fmt   <= 32'd0;
            wb_ex_out      <= 32'd0;
            wb_pc_plus_8   <= 32'd0;
            wb_waddr       <= 5'd0;
            
            wb_reg_write   <= 1'b0;
            wb_mem_to_reg  <= 2'd0;
            wb_cp0_we      <= 1'b0;
            wb_is_eret     <= 1'b0;
            wb_except_req  <= 1'b0;
            wb_except_code <= 5'd0;
        end else if (flush) begin
            wb_rdata_fmt   <= 32'd0;
            wb_ex_out      <= 32'd0;
            wb_pc_plus_8   <= 32'd0;
            wb_waddr       <= 5'd0;
            
            wb_reg_write   <= 1'b0;
            wb_mem_to_reg  <= 2'd0;
            wb_cp0_we      <= 1'b0;
            wb_is_eret     <= 1'b0;
            wb_except_req  <= 1'b0;
            wb_except_code <= 5'd0;
        end else if (!stall) begin
            wb_rdata_fmt   <= mem_rdata_fmt;
            wb_ex_out      <= mem_ex_out;
            wb_pc_plus_8   <= mem_pc_plus_8;
            wb_waddr       <= mem_waddr;
            wb_rd_addr     <= mem_rd_addr;
            
            wb_reg_write   <= mem_reg_write;
            wb_cp0_we      <= mem_cp0_we;
            wb_is_eret     <= mem_is_eret;
            wb_except_req  <= mem_except_req;
            wb_except_code <= mem_except_code;
            wb_mem_to_reg  <= mem_mem_to_reg;
        end
    end

endmodule
