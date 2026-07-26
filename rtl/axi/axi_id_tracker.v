// =============================================================================
// File Name: axi_id_tracker.v
// Design:    AXI ID-Tag Tracking Table (Phase C multi-outstanding scaffold)
// Author:    Antigravity — Phase C
// Description:
//   Tracks up to N_OUTSTANDING in-flight AXI transactions by ID so
//   out-of-order responses can be reassembled. Scaffold for Phase C's
//   multi-outstanding AXI upgrade — current fabric is single-outstanding.
//
//   Interface: master calls issue() on AR/AW handshake; retire() on R/B
//   handshake. Table exposes "any_free" (backpressure request-issue) and
//   "id_valid[i]" (per-slot occupancy).
//
//   Currently not instantiated in the DUT. Integration with axi_arbiter and
//   axi_decoder is planned Phase C.
// =============================================================================

module axi_id_tracker #(
    parameter N_OUTSTANDING = 4,
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32
) (
    input  wire clk,
    input  wire rst_n,

    // Issue port
    input  wire                  issue_valid,
    input  wire [ID_WIDTH-1:0]   issue_id,
    input  wire [ADDR_WIDTH-1:0] issue_addr,
    input  wire                  issue_is_write,
    output wire                  issue_ready,

    // Retire port
    input  wire                  retire_valid,
    input  wire [ID_WIDTH-1:0]   retire_id,
    input  wire                  retire_is_write,

    // Status
    output wire [N_OUTSTANDING-1:0]                  slot_valid,
    output wire [N_OUTSTANDING-1:0] [ID_WIDTH-1:0]   slot_id,
    output wire                                       any_free
);

    reg  [N_OUTSTANDING-1:0]                slot_valid_r;
    reg  [ID_WIDTH-1:0]                     slot_id_r      [N_OUTSTANDING-1:0];
    reg  [ADDR_WIDTH-1:0]                   slot_addr_r    [N_OUTSTANDING-1:0];
    reg  [N_OUTSTANDING-1:0]                slot_write_r;

    integer i;

    // Simple free-slot lookup (priority encoder — small N)
    reg [$clog2(N_OUTSTANDING+1)-1:0] free_slot;
    reg                                free_found;
    always @(*) begin
        free_slot  = '0;
        free_found = 1'b0;
        for (i = 0; i < N_OUTSTANDING; i = i + 1) begin
            if (!slot_valid_r[i] && !free_found) begin
                free_slot  = i[$clog2(N_OUTSTANDING+1)-1:0];
                free_found = 1'b1;
            end
        end
    end

    assign issue_ready = free_found;
    assign any_free    = free_found;

    // Retire: find matching (id, write) slot
    reg [$clog2(N_OUTSTANDING+1)-1:0] retire_slot;
    reg                                retire_hit;
    always @(*) begin
        retire_slot = '0;
        retire_hit  = 1'b0;
        for (i = 0; i < N_OUTSTANDING; i = i + 1) begin
            if (slot_valid_r[i] && slot_id_r[i] == retire_id
                && slot_write_r[i] == retire_is_write && !retire_hit) begin
                retire_slot = i[$clog2(N_OUTSTANDING+1)-1:0];
                retire_hit  = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_valid_r <= {N_OUTSTANDING{1'b0}};
            slot_write_r <= {N_OUTSTANDING{1'b0}};
            for (i = 0; i < N_OUTSTANDING; i = i + 1) begin
                slot_id_r[i]   <= {ID_WIDTH{1'b0}};
                slot_addr_r[i] <= {ADDR_WIDTH{1'b0}};
            end
        end else begin
            if (issue_valid && issue_ready) begin
                slot_valid_r[free_slot] <= 1'b1;
                slot_id_r[free_slot]    <= issue_id;
                slot_addr_r[free_slot]  <= issue_addr;
                slot_write_r[free_slot] <= issue_is_write;
            end
            if (retire_valid && retire_hit) begin
                slot_valid_r[retire_slot] <= 1'b0;
            end
        end
    end

    assign slot_valid = slot_valid_r;
    genvar j;
    generate
        for (j = 0; j < N_OUTSTANDING; j = j + 1) begin: g_id_out
            assign slot_id[j] = slot_id_r[j];
        end
    endgenerate

endmodule
