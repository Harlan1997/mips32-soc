// =============================================================================
// File Name : mips_bpu.v
// Module    : mips_bpu
// Design    : MIPS32 Branch Prediction Unit (Phase B.6 baseline storage +
//             prediction; IF next-PC redirection wiring deferred)
// Standard  : Verilog-2001 (synthesizable)
//
// Implements the three prediction structures described in
// docs/block_specs/bpu_spec.md:
//   * BTB    — direct-mapped, {valid, tag, target, type[1:0]}
//   * BHT    — 2-bit saturating counter per index
//   * RAS    — small circular return-address stack
//
// Prediction port (`predict_*`) is combinational and queried at IF stage; the
// update port (`resolve_*`) is driven synchronously after ID/EX branch/jump
// resolution to refresh BTB/BHT/RAS. This phase does not yet route
// predict_target back into mips_if_stage — the current pipeline already
// achieves zero taken-branch penalty because ID resolves branches early.
// A future phase will wire predict_target into IF for speculative fetch when
// the pipeline moves branch resolution later, or when a fetch queue exists.
//
// BTB.type encoding (2 bits):
//   00 = conditional branch (uses BHT counter for taken decision)
//   01 = direct jump J/JAL (unconditional; always predict target)
//   10 = jr $ra style return (pop RAS)
//   11 = jalr/call (push RAS with link)
// =============================================================================

`include "soc_config.vh"

module mips_bpu #(
    parameter BTB_ENTRIES = `SOC_BTB_ENTRIES,
    parameter BTB_IDX_BITS = `SOC_BTB_INDEX_BITS,
    parameter BHT_ENTRIES = `SOC_BHT_ENTRIES,
    parameter BHT_IDX_BITS = `SOC_BHT_INDEX_BITS,
    parameter RAS_DEPTH   = `SOC_RAS_DEPTH,
    parameter RAS_PTR_BITS = `SOC_RAS_DEPTH_BITS,
    parameter ADDR_WIDTH  = 32,
    parameter ENABLE_BPU  = 1'b1
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Prediction port (IF stage). Combinational.
    input  wire                    if_valid,        // 1 = IF is fetching a valid PC
    input  wire [ADDR_WIDTH-1:0]   if_pc,
    output wire                    predict_hit,     // BTB matches this PC
    output wire                    predict_taken,   // Prediction: take the branch/jump
    output wire [ADDR_WIDTH-1:0]   predict_target,  // Predicted next PC when taken
    output wire [1:0]              predict_type,    // BTB entry type

    // Resolution / update port (ID or EX after branch resolves). Synchronous.
    input  wire                    resolve_valid,
    input  wire [ADDR_WIDTH-1:0]   resolve_pc,
    input  wire                    resolve_taken,
    input  wire [ADDR_WIDTH-1:0]   resolve_target,
    input  wire [1:0]              resolve_type,
    input  wire                    resolve_mispredict,
    input  wire                    flush_if
);

    localparam BTB_TAG_BITS = ADDR_WIDTH - BTB_IDX_BITS - 2;   // ignore 2 word-align

    // -------------------------------------------------------------------------
    // Storage arrays
    // -------------------------------------------------------------------------
    reg                    btb_valid  [0:BTB_ENTRIES-1];
    reg [BTB_TAG_BITS-1:0] btb_tag    [0:BTB_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]   btb_target [0:BTB_ENTRIES-1];
    reg [1:0]              btb_type   [0:BTB_ENTRIES-1];
    reg [1:0]              bht_ctr    [0:BHT_ENTRIES-1];

    reg [ADDR_WIDTH-1:0]   ras_stack  [0:RAS_DEPTH-1];
    reg [RAS_PTR_BITS-1:0] ras_top;
    reg                    ras_valid;   // 1 if at least one push happened

    // -------------------------------------------------------------------------
    // Prediction path (combinational, IF stage)
    // -------------------------------------------------------------------------
    wire [BTB_IDX_BITS-1:0] pred_btb_idx = if_pc[BTB_IDX_BITS+1:2];
    wire [BTB_TAG_BITS-1:0] pred_tag     = if_pc[ADDR_WIDTH-1:BTB_IDX_BITS+2];
    wire [BHT_IDX_BITS-1:0] pred_bht_idx = if_pc[BHT_IDX_BITS+1:2];

    wire btb_hit = ENABLE_BPU && if_valid && btb_valid[pred_btb_idx]
                            && (btb_tag[pred_btb_idx] == pred_tag);
    wire [1:0] btb_type_out    = btb_type[pred_btb_idx];
    wire [ADDR_WIDTH-1:0] btb_target_out = btb_target[pred_btb_idx];
    wire        bht_taken      = bht_ctr[pred_bht_idx][1];

    // Per-type prediction resolution
    reg  taken_r;
    reg  [ADDR_WIDTH-1:0] target_r;
    always @(*) begin
        // Default fall-through: predict not-taken, target = PC+4 (caller is
        // free to substitute PC+4 in its own path; we mirror it here).
        taken_r  = 1'b0;
        target_r = if_pc + 32'd4;
        if (btb_hit) begin
            case (btb_type_out)
                2'b00: begin                                   // conditional branch
                    taken_r  = bht_taken;
                    target_r = btb_target_out;
                end
                2'b01: begin                                   // direct jump
                    taken_r  = 1'b1;
                    target_r = btb_target_out;
                end
                2'b10: begin                                   // jr $ra (return)
                    taken_r  = ras_valid;
                    target_r = ras_stack[ras_top];
                end
                2'b11: begin                                   // jalr / call
                    taken_r  = 1'b1;
                    target_r = btb_target_out;
                end
                default: ;
            endcase
        end
    end
    assign predict_hit    = btb_hit;
    assign predict_taken  = taken_r;
    assign predict_target = target_r;
    assign predict_type   = btb_type_out;

    // -------------------------------------------------------------------------
    // Update path (synchronous)
    // -------------------------------------------------------------------------
    wire [BTB_IDX_BITS-1:0] upd_btb_idx = resolve_pc[BTB_IDX_BITS+1:2];
    wire [BTB_TAG_BITS-1:0] upd_tag     = resolve_pc[ADDR_WIDTH-1:BTB_IDX_BITS+2];
    wire [BHT_IDX_BITS-1:0] upd_bht_idx = resolve_pc[BHT_IDX_BITS+1:2];

    integer bi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Only need to invalidate BTB — data arrays overwritten before use.
            for (bi = 0; bi < BTB_ENTRIES; bi = bi + 1)
                btb_valid[bi] <= 1'b0;
            // BHT starts weakly not-taken (2'b01) as a mildly optimistic bias
            // for typical loops with early not-taken guard.
            for (bi = 0; bi < BHT_ENTRIES; bi = bi + 1)
                bht_ctr[bi] <= 2'b01;
            ras_top   <= {RAS_PTR_BITS{1'b0}};
            ras_valid <= 1'b0;
        end else if (resolve_valid) begin
            // -----------------------------------------------------------------
            // BTB: allocate on taken, update target on hit-but-target-changed
            // for indirect jumps. Not-taken conditional branches only refresh
            // BHT.
            // -----------------------------------------------------------------
            case (resolve_type)
                2'b00: begin  // conditional branch
                    if (resolve_taken) begin
                        btb_valid [upd_btb_idx] <= 1'b1;
                        btb_tag   [upd_btb_idx] <= upd_tag;
                        btb_target[upd_btb_idx] <= resolve_target;
                        btb_type  [upd_btb_idx] <= 2'b00;
                    end
                    // BHT saturating update
                    if (resolve_taken)
                        bht_ctr[upd_bht_idx] <= (bht_ctr[upd_bht_idx] == 2'b11)
                                              ? 2'b11
                                              : bht_ctr[upd_bht_idx] + 2'd1;
                    else
                        bht_ctr[upd_bht_idx] <= (bht_ctr[upd_bht_idx] == 2'b00)
                                              ? 2'b00
                                              : bht_ctr[upd_bht_idx] - 2'd1;
                end
                default: begin  // direct jump / call / return
                    btb_valid [upd_btb_idx] <= 1'b1;
                    btb_tag   [upd_btb_idx] <= upd_tag;
                    btb_target[upd_btb_idx] <= resolve_target;
                    btb_type  [upd_btb_idx] <= resolve_type;
                end
            endcase

            // RAS bookkeeping — push on call (type 11), pop on return (type 10).
            if (resolve_type == 2'b11) begin
                ras_top          <= ras_top + {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
                ras_stack[ras_top + {{(RAS_PTR_BITS-1){1'b0}}, 1'b1}]
                                 <= resolve_pc + 32'd8;  // return addr = call+delay_slot+4
                ras_valid        <= 1'b1;
            end else if (resolve_type == 2'b10 && ras_valid) begin
                ras_top <= ras_top - {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
                if (ras_top == {RAS_PTR_BITS{1'b0}}) begin
                    // Underflow — clear valid so subsequent pop returns fall-through
                    ras_valid <= 1'b0;
                end
            end

            // A mispredict is deliberately trained with the resolved
            // architectural outcome.  `flush_if` only describes the IF
            // recovery action and must not discard this update.
        end
    end

    // These inputs describe pipeline recovery/diagnostics; state updates are
    // controlled by resolve_valid, which the CPU suppresses for exceptions.
    wire _unused_ok = &{1'b0, resolve_mispredict, flush_if};

endmodule
