// =============================================================================
// File Name: mips_rob.v
// Design:    In-order-retirement completion buffer (mini-ROB)
// Author:    Antigravity — Phase C hit-under-miss
// Description:
//   Replaces the MEM/WB pipeline register with a circular completion buffer.
//   Instructions allocate an entry as they leave MEM and COMMIT strictly in
//   program order from the head, driving the register-file / CP0 / exception
//   path exactly as the old wb_* bundle did.
//
//   STAGE 1 (this file, DEPTH=1): behaviorally identical to mips_mem_wb_reg.
//   With DEPTH=1 and the blocking D-cache, a load's data is already formatted
//   in MEM before allocation, so every allocated entry is immediately "ready"
//   and commits next cycle — degenerating to the old pipeline register. The
//   circular-buffer structure, ready bits, and commit/alloc handshakes are the
//   skeleton that later stages grow (depth>1, run-ahead, late-load capture).
//
//   Commit-visible outputs (wb_*) are registered and, at DEPTH=1, update on
//   !stall, zero on flush, hold on stall — matching mips_mem_wb_reg cycle-for-
//   cycle.
// =============================================================================

module mips_rob #(
    parameter DEPTH = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    // Control (Stage 1: unified with the global pipeline stall/flush, exactly
    // as the MEM/WB register was driven).
    input  wire        stall,
    input  wire        flush,

    // Allocate inputs (from MEM stage) -----------------------------------------
    input  wire [31:0] mem_rdata_fmt,
    input  wire [31:0] mem_ex_out,
    input  wire [31:0] mem_pc_plus_8,
    input  wire [4:0]  mem_waddr,
    input  wire [4:0]  mem_rd_addr,
    input  wire [4:0]  mem_cp0_raddr,
    input  wire [2:0]  mem_cp0_sel,
    input  wire        mem_reg_write,
    input  wire        mem_cp0_we,
    input  wire        mem_is_eret,
    input  wire [2:0]  mem_tlb_op,
    input  wire        mem_except_req,
    input  wire [4:0]  mem_except_code,
    input  wire        mem_except_is_data,
    input  wire        mem_bd,
    input  wire [1:0]  mem_mem_to_reg,

    // Commit outputs (to WB / CP0 / RF) — same names/semantics as wb_* ---------
    output reg  [31:0] wb_rdata_fmt,
    output reg  [31:0] wb_ex_out,
    output reg  [31:0] wb_pc_plus_8,
    output reg  [4:0]  wb_waddr,
    output reg  [4:0]  wb_rd_addr,
    output reg  [4:0]  wb_cp0_raddr,
    output reg  [2:0]  wb_cp0_sel,
    output reg         wb_reg_write,
    output reg         wb_cp0_we,
    output reg         wb_is_eret,
    output reg  [2:0]  wb_tlb_op,
    output reg         wb_except_req,
    output reg  [4:0]  wb_except_code,
    output reg         wb_except_is_data,
    output reg         wb_bd,
    output reg  [1:0]  wb_mem_to_reg
);

    // ------------------------------------------------------------------------
    // STAGE 1: DEPTH==1 commit register.
    // Identical three-way behavior to mips_mem_wb_reg (reset/flush -> bubble;
    // !stall -> latch the MEM allocate bundle; stall -> hold). Bit-for-bit
    // equivalent, so all Stage-0 gates must reproduce exactly.
    // Stage 2 replaces this with a DEPTH-entry circular buffer + ready bits +
    // out-of-order slot write-back + in-order head commit.
    // ------------------------------------------------------------------------
    generate if (DEPTH == 1) begin : g_depth1
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n || flush) begin
                wb_rdata_fmt      <= 32'd0;
                wb_ex_out         <= 32'd0;
                wb_pc_plus_8      <= 32'd0;
                wb_waddr          <= 5'd0;
                wb_rd_addr        <= 5'd0;
                wb_cp0_raddr      <= 5'd0;
                wb_cp0_sel        <= 3'd0;
                wb_reg_write      <= 1'b0;
                wb_mem_to_reg     <= 2'd0;
                wb_cp0_we         <= 1'b0;
                wb_is_eret        <= 1'b0;
                wb_tlb_op         <= 3'd0;
                wb_except_req     <= 1'b0;
                wb_except_code    <= 5'd0;
                wb_except_is_data <= 1'b0;
                wb_bd             <= 1'b0;
            end else if (!stall) begin
                wb_rdata_fmt      <= mem_rdata_fmt;
                wb_ex_out         <= mem_ex_out;
                wb_pc_plus_8      <= mem_pc_plus_8;
                wb_waddr          <= mem_waddr;
                wb_rd_addr        <= mem_rd_addr;
                wb_cp0_raddr      <= mem_cp0_raddr;
                wb_cp0_sel        <= mem_cp0_sel;
                wb_reg_write      <= mem_reg_write;
                wb_cp0_we         <= mem_cp0_we;
                wb_is_eret        <= mem_is_eret;
                wb_tlb_op         <= mem_tlb_op;
                wb_except_req     <= mem_except_req;
                wb_except_code    <= mem_except_code;
                wb_except_is_data <= mem_except_is_data;
                wb_bd             <= mem_bd;
                wb_mem_to_reg     <= mem_mem_to_reg;
            end
        end
    end endgenerate

endmodule
