// =============================================================================
// File Name: async_fifo.v
// Design:    Asynchronous FIFO (dual-clock)
// Author:    Antigravity — Phase E
// Description:
//   Standard gray-coded pointer async FIFO for reliable data streaming
//   between two clock domains. Depth = 2^DEPTH_LOG2; suggested 8/16/32.
//   Full/empty computed by comparing gray-encoded pointers synced across
//   domains. See docs/block_specs/clock_reset_spec.md §4.4.
// =============================================================================

module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH_LOG2 = 4         // depth = 2^DEPTH_LOG2 = 16 by default
) (
    // Write side
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    // Read side
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    localparam DEPTH = (1 << DEPTH_LOG2);

    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Pointers use DEPTH_LOG2+1 bits (extra MSB distinguishes full vs empty).
    wire [DEPTH_LOG2:0]  wr_bin,   rd_bin;
    wire [DEPTH_LOG2:0]  wr_gray,  rd_gray;
    wire                 do_wr = wr_en & ~wr_full;
    wire                 do_rd = rd_en & ~rd_empty;

    gray_counter #(.WIDTH(DEPTH_LOG2+1)) u_wr_ptr (
        .clk(wr_clk), .rst_n(wr_rst_n), .incr(do_wr),
        .bin(wr_bin), .gray(wr_gray));
    gray_counter #(.WIDTH(DEPTH_LOG2+1)) u_rd_ptr (
        .clk(rd_clk), .rst_n(rd_rst_n), .incr(do_rd),
        .bin(rd_bin), .gray(rd_gray));

    // Write memory
    always @(posedge wr_clk) begin
        if (do_wr) mem[wr_bin[DEPTH_LOG2-1:0]] <= wr_data;
    end
    assign rd_data = mem[rd_bin[DEPTH_LOG2-1:0]];

    // Cross-domain pointer sync
    wire [DEPTH_LOG2:0] rd_gray_at_wr;
    wire [DEPTH_LOG2:0] wr_gray_at_rd;
    genvar i;
    generate
        for (i = 0; i <= DEPTH_LOG2; i = i + 1) begin: g_ptrsync
            sync_2ff #(.STAGES(2)) u_rd2wr (
                .dst_clk(wr_clk), .dst_rst_n(wr_rst_n),
                .src_data(rd_gray[i]), .dst_data(rd_gray_at_wr[i]));
            sync_2ff #(.STAGES(2)) u_wr2rd (
                .dst_clk(rd_clk), .dst_rst_n(rd_rst_n),
                .src_data(wr_gray[i]), .dst_data(wr_gray_at_rd[i]));
        end
    endgenerate

    // Full: next-write gray equals read gray but with top 2 bits flipped
    wire [DEPTH_LOG2:0] wr_gray_next = (wr_bin + 1'b1) ^ ((wr_bin + 1'b1) >> 1);
    assign wr_full  = (wr_gray_next == {~rd_gray_at_wr[DEPTH_LOG2:DEPTH_LOG2-1],
                                        rd_gray_at_wr[DEPTH_LOG2-2:0]});
    assign rd_empty = (rd_gray == wr_gray_at_rd);

endmodule
