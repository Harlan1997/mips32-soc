// =============================================================================
// File Name: handshake_sync.v
// Design:    4-Phase Handshake Synchronizer with Multi-bit Data Payload
// Author:    Antigravity — Phase E
// Description:
//   Full 4-phase req/ack handshake for reliable multi-bit data transfer
//   across clock domains. Sequence:
//     1) src: latch data, raise req
//     2) 2FF: req to dst
//     3) dst: sample data (stable while req high), raise ack
//     4) 2FF: ack back to src
//     5) src: sees ack, drops req
//     6) 2FF: req low to dst
//     7) dst: sees req low, drops ack
//     8) 2FF: ack low back to src → ready for next
//   Throughput: one transfer per ~6 (src+dst) clocks.
//   See docs/block_specs/clock_reset_spec.md §4.3.
// =============================================================================

module handshake_sync #(
    parameter DATA_WIDTH = 32
) (
    input  wire                  src_clk,
    input  wire                  src_rst_n,
    input  wire                  src_valid,
    output wire                  src_ready,
    input  wire [DATA_WIDTH-1:0] src_data,

    input  wire                  dst_clk,
    input  wire                  dst_rst_n,
    output wire                  dst_valid,
    input  wire                  dst_ready,
    output wire [DATA_WIDTH-1:0] dst_data
);

    // Forward decls (VCS strict requires reg decls before wire refs)
    reg                    src_req_r;
    reg [DATA_WIDTH-1:0]   src_data_r;
    reg                    dst_ack_r;
    reg                    dst_valid_r;

    // -------- src side ------------------------------------------------------
    wire                   src_ack_synced;

    sync_2ff #(.STAGES(2)) u_ack_sync (
        .dst_clk   (src_clk),
        .dst_rst_n (src_rst_n),
        .src_data  (dst_ack_r),
        .dst_data  (src_ack_synced)
    );

    assign src_ready = ~src_req_r & ~src_ack_synced;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_req_r  <= 1'b0;
            src_data_r <= {DATA_WIDTH{1'b0}};
        end else begin
            if (src_valid && src_ready) begin
                src_req_r  <= 1'b1;
                src_data_r <= src_data;
            end else if (src_req_r && src_ack_synced) begin
                src_req_r <= 1'b0;
            end
        end
    end

    // -------- dst side ------------------------------------------------------
    wire src_req_synced;

    sync_2ff #(.STAGES(2)) u_req_sync (
        .dst_clk   (dst_clk),
        .dst_rst_n (dst_rst_n),
        .src_data  (src_req_r),
        .dst_data  (src_req_synced)
    );

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_ack_r   <= 1'b0;
            dst_valid_r <= 1'b0;
        end else begin
            if (src_req_synced && !dst_ack_r) begin
                dst_ack_r   <= 1'b1;
                dst_valid_r <= 1'b1;
            end else if (dst_valid_r && dst_ready) begin
                dst_valid_r <= 1'b0;
            end else if (!src_req_synced && dst_ack_r && !dst_valid_r) begin
                dst_ack_r <= 1'b0;
            end
        end
    end

    assign dst_valid = dst_valid_r;
    assign dst_data  = src_data_r; // driven while req high; sampled by dst on valid handshake

endmodule
