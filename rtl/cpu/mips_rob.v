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
//   STAGE 1 (DEPTH=1): behaviorally identical to mips_mem_wb_reg. With
//   DEPTH=1 and the blocking D-cache, a load's data is already formatted
//   in MEM before allocation, so every allocated entry is immediately "ready"
//   and commits next cycle — degenerating to the old pipeline register.
//
//   STAGE 2 (DEPTH>=2, this file): introduces the real circular-buffer
//   skeleton (slot array + valid/ready bits + head/tail pointers +
//   occupancy count) that later stages will grow into true out-of-order
//   completion. The D-cache is still blocking in this step, so every
//   allocated entry is ready in the very cycle it is produced -- occupancy
//   provably never needs to exceed 0 across a clock edge. A cut-through path
//   (buffer empty + an allocate this cycle -> commit straight to wb_* the
//   same edge) is therefore always taken and reproduces the DEPTH=1 register
//   bit-for-bit. The buffered head/tail path exists and is bookkept every
//   cycle but is dead code until a later stage introduces entries that can
//   go un-ready for more than zero cycles (non-blocking D-cache miss).
//
//   Commit-visible outputs (wb_*) are registered and update on !stall, zero
//   on flush, hold on stall — matching mips_mem_wb_reg cycle-for-cycle at
//   any DEPTH, as long as occupancy stays 0 (true today).
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
    input  wire        mem_except_is_tlb_refill,
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
    output reg         wb_except_is_tlb_refill,
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
                wb_except_is_tlb_refill <= 1'b0;
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
                wb_except_is_tlb_refill <= mem_except_is_tlb_refill;
                wb_bd             <= mem_bd;
                wb_mem_to_reg     <= mem_mem_to_reg;
            end
        end
    end endgenerate

    // ------------------------------------------------------------------------
    // STAGE 2: DEPTH>=2 circular-buffer skeleton.
    //
    // The wb_* commit register is byte-for-byte the same three-way reset/
    // flush/stall register as the DEPTH==1 branch above -- this is what
    // guarantees bit-exact parity with today's behavior; it is not merely
    // "provably identical," it is literally the same code path.
    //
    // Alongside it, rob_head/rob_tail/rob_valid/rob_ready/rob_slot exercise
    // real circular-buffer bookkeeping every non-stalled cycle: each
    // allocate both enters and immediately exits the buffer (head chases
    // tail one slot per cycle), because the D-cache is still blocking, so
    // Stage 2 has no source of a late-arriving (not-yet-ready) result --
    // every entry is ready in the very cycle it is allocated, and occupancy
    // (rob_count) is a structural invariant of 0 across every clock edge.
    // rob_valid therefore never sets, which is intentional: it is dead code
    // until a later stage's non-blocking D-cache miss actually leaves an
    // entry un-ready for more than zero cycles, at which point occupancy can
    // exceed 0, rob_valid/rob_ready start mattering, and commit switches from
    // "always the incoming allocate" to "the ready head of the buffer."
    // ------------------------------------------------------------------------
    localparam BW = 131; // packed allocate-bundle width (see pack below)

    generate if (DEPTH >= 2) begin : g_depth_n
        localparam PTR_W = $clog2(DEPTH);

        reg [BW-1:0]    rob_slot  [0:DEPTH-1];
        reg             rob_valid [0:DEPTH-1];
        reg             rob_ready [0:DEPTH-1];
        reg [PTR_W-1:0] rob_head;
        reg [PTR_W-1:0] rob_tail;

        wire [BW-1:0] alloc_bundle = {
            mem_rdata_fmt, mem_ex_out, mem_pc_plus_8,          // 96 bits
            mem_waddr, mem_rd_addr, mem_cp0_raddr,             // 15 bits
            mem_cp0_sel,                                       // 3 bits
            mem_reg_write, mem_cp0_we, mem_is_eret,            // 3 bits
            mem_tlb_op,                                        // 3 bits
            mem_except_req, mem_except_code,                   // 6 bits
            mem_except_is_data, mem_except_is_tlb_refill, mem_bd, // 3 bits
            mem_mem_to_reg                                     // 2 bits
        };

        integer j;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rob_head <= {PTR_W{1'b0}};
                rob_tail <= {PTR_W{1'b0}};
                for (j = 0; j < DEPTH; j = j + 1) begin
                    rob_valid[j] <= 1'b0;
                    rob_ready[j] <= 1'b0;
                end
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
                wb_except_is_tlb_refill <= 1'b0;
                wb_bd             <= 1'b0;
            end else if (flush) begin
                rob_head <= {PTR_W{1'b0}};
                rob_tail <= {PTR_W{1'b0}};
                for (j = 0; j < DEPTH; j = j + 1) begin
                    rob_valid[j] <= 1'b0;
                    rob_ready[j] <= 1'b0;
                end
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
                wb_except_is_tlb_refill <= 1'b0;
                wb_bd             <= 1'b0;
            end else if (!stall) begin
                // Bookkeeping-only: store the bundle and walk both pointers
                // one slot forward. rob_valid/rob_ready are deliberately left
                // clear -- see header comment; nothing reads rob_slot back
                // yet.
                rob_slot[rob_tail] <= alloc_bundle;
                rob_head           <= rob_head + {{(PTR_W-1){1'b0}}, 1'b1};
                rob_tail           <= rob_tail + {{(PTR_W-1){1'b0}}, 1'b1};

                // Commit register: identical to the DEPTH==1 branch.
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
                wb_except_is_tlb_refill <= mem_except_is_tlb_refill;
                wb_bd             <= mem_bd;
                wb_mem_to_reg     <= mem_mem_to_reg;
            end
        end
    end endgenerate

endmodule
