// =============================================================================
// File Name: mux_sync.v
// Design:    Mux-based Multi-bit Synchronizer
// Author:    Antigravity — Phase E
// Description:
//   Low-frequency, non-continuous multi-bit CDC using a valid handshake.
//   Data is captured on src side when src_valid asserts; valid is synced
//   via 2FF; dst samples data (which is stable in src domain) when synced
//   valid observed. Simpler than full handshake for slow, event-driven
//   signals. See docs/block_specs/clock_reset_spec.md §4.5.
// =============================================================================

module mux_sync #(
    parameter DATA_WIDTH = 32
) (
    input  wire                  src_clk,
    input  wire                  src_rst_n,
    input  wire                  src_valid,
    input  wire [DATA_WIDTH-1:0] src_data,

    input  wire                  dst_clk,
    input  wire                  dst_rst_n,
    output reg                   dst_valid,
    output reg  [DATA_WIDTH-1:0] dst_data
);

    reg                   src_valid_hold;
    reg [DATA_WIDTH-1:0]  src_data_hold;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_valid_hold <= 1'b0;
            src_data_hold  <= {DATA_WIDTH{1'b0}};
        end else if (src_valid) begin
            src_valid_hold <= 1'b1;
            src_data_hold  <= src_data;
        end
    end

    wire dst_valid_synced;
    sync_2ff #(.STAGES(2)) u_valid_sync (
        .dst_clk(dst_clk), .dst_rst_n(dst_rst_n),
        .src_data(src_valid_hold), .dst_data(dst_valid_synced));

    reg dst_valid_synced_d;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_valid_synced_d <= 1'b0;
            dst_valid          <= 1'b0;
            dst_data           <= {DATA_WIDTH{1'b0}};
        end else begin
            dst_valid_synced_d <= dst_valid_synced;
            dst_valid          <= dst_valid_synced & ~dst_valid_synced_d;
            if (dst_valid_synced & ~dst_valid_synced_d) begin
                dst_data <= src_data_hold; // src holds stable during transfer
            end
        end
    end

endmodule
