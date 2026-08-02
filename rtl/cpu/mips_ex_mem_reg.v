// =============================================================================
// File Name: mips_ex_mem_reg.v
// Design:    EX/MEM Pipeline Register
// Author:    Antigravity
// =============================================================================

module mips_ex_mem_reg (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control
    input  wire        stall,
    input  wire        flush,
    input  wire        dmem_data_ok,
    input  wire        cache_op_done,

    
    // Inputs from EX
    input  wire [31:0] ex_out,         // ALU or MDU result (used as memory address or reg data)
    input  wire [31:0] ex_val_rt,      // Data to be written to memory
    input  wire [31:0] ex_pc_plus_8,
    input  wire [4:0]  ex_waddr,
    input  wire [4:0]  ex_rd_addr,
    input  wire [4:0]  ex_cp0_raddr,       // Destination register
    input  wire [2:0]  ex_cp0_sel,

    input  wire        ex_reg_write,
    
    // CP0
    input  wire        ex_cp0_we,
    input  wire        ex_is_eret,
    input  wire [2:0]  ex_tlb_op,

    // Exceptions
    input  wire        ex_except_req,
    input  wire [4:0]  ex_except_code,
    input  wire        ex_except_is_data,   // Phase B.3.d
    input  wire        ex_except_is_tlb_refill,
    input  wire        ex_bd,               // Phase B.5
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire [2:0]  ex_mem_op,
    input  wire [1:0]  ex_mem_to_reg,
    input  wire        ex_cache_op_valid,
    input  wire [4:0]  ex_cache_op,
    
    // Outputs to MEM
    output reg  [31:0] mem_ex_out,
    output reg  [31:0] mem_val_rt,
    output reg  [31:0] mem_pc_plus_8,
    output reg  [4:0]  mem_waddr,
    output reg  [4:0]  mem_rd_addr,
    output reg  [4:0]  mem_cp0_raddr,
    output reg  [2:0]  mem_cp0_sel,

    output reg         mem_reg_write,
    
    // CP0
    output reg         mem_cp0_we,
    output reg         mem_is_eret,
    output reg  [2:0]  mem_tlb_op,

    // Exceptions
    output reg         mem_except_req,
    output reg  [4:0]  mem_except_code,
    output reg         mem_except_is_data,
    output reg         mem_except_is_tlb_refill,
    output reg         mem_bd,
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg  [2:0]  mem_mem_op,
    output reg  [1:0]  mem_mem_to_reg,
    output reg         mem_cache_op_valid,
    output reg  [4:0]  mem_cache_op,
    output reg         mem_done
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ex_out     <= 32'd0;
            mem_val_rt     <= 32'd0;
            mem_pc_plus_8  <= 32'd0;
            mem_waddr      <= 5'd0;
            mem_rd_addr    <= 5'd0;
            mem_cp0_raddr  <= 5'd0;
            mem_cp0_sel    <= 3'd0;

            mem_reg_write  <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_mem_op     <= 3'd0;
            mem_mem_to_reg <= 2'd0;
            mem_cache_op_valid <= 1'b0;
            mem_cache_op   <= 5'd0;
            mem_cp0_we     <= 1'b0;
            mem_is_eret    <= 1'b0;
            mem_tlb_op     <= 3'd0;
            mem_except_req <= 1'b0;
            mem_except_code<= 5'd0;
            mem_except_is_data <= 1'b0;
            mem_except_is_tlb_refill <= 1'b0;
            mem_bd         <= 1'b0;
            mem_done       <= 1'b0;
        end else if (flush) begin
            mem_ex_out     <= 32'd0;
            mem_val_rt     <= 32'd0;
            mem_pc_plus_8  <= 32'd0;
            mem_waddr      <= 5'd0;
            mem_rd_addr    <= 5'd0;
            mem_cp0_raddr  <= 5'd0;
            mem_cp0_sel    <= 3'd0;

            mem_reg_write  <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_mem_op     <= 3'd0;
            mem_mem_to_reg <= 2'd0;
            mem_cache_op_valid <= 1'b0;
            mem_cache_op   <= 5'd0;
            mem_cp0_we     <= 1'b0;
            mem_is_eret    <= 1'b0;
            mem_tlb_op     <= 3'd0;
            mem_except_req <= 1'b0;
            mem_except_code<= 5'd0;
            mem_except_is_data <= 1'b0;
            mem_except_is_tlb_refill <= 1'b0;
            mem_bd         <= 1'b0;
            mem_done       <= 1'b0;
        end else if (!stall) begin
            mem_ex_out     <= ex_out;
            mem_val_rt     <= ex_val_rt;
            mem_pc_plus_8  <= ex_pc_plus_8;
            mem_waddr      <= ex_waddr;
            mem_rd_addr    <= ex_rd_addr;
            mem_cp0_raddr  <= ex_cp0_raddr;
            mem_cp0_sel    <= ex_cp0_sel;

            mem_reg_write  <= ex_reg_write;
            mem_cp0_we     <= ex_cp0_we;
            mem_is_eret    <= ex_is_eret;
            mem_tlb_op     <= ex_tlb_op;
            mem_except_req <= ex_except_req;
            mem_except_code<= ex_except_code;
            mem_except_is_data <= ex_except_is_data;
            mem_except_is_tlb_refill <= ex_except_is_tlb_refill;
            mem_bd         <= ex_bd;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_mem_op     <= ex_mem_op;
            mem_mem_to_reg <= ex_mem_to_reg;
            mem_cache_op_valid <= ex_cache_op_valid;
            mem_cache_op   <= ex_cache_op;
            mem_done       <= 1'b0;
        end else if (dmem_data_ok || (cache_op_done === 1'b1)) begin
            mem_done       <= 1'b1;
        end
    end

endmodule
