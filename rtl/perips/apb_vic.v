// =============================================================================
// File Name: apb_vic.v
// Design:    Vectored Interrupt Controller (functional subset)
// Author:    Antigravity — Phase D
// Description:
//   Simplified VIC replacing the existing apb_pic OR-reducer. Implements the
//   subset of docs/block_specs/vic_spec.md sufficient for a 32-source
//   priority-encoded interrupt system with soft interrupts. Existing
//   apb_pic.v is kept until integration cutover.
//
//   Implemented:
//     * 32 sources, per-source enable + 4-bit priority
//     * Level-triggered (edge detect deferred)
//     * Software-triggered sources (INTR_SOFT)
//     * Priority encoder → VEC_ID + VEC_IPRIO
//     * Combined irq → CPU (level)
//     * ACK (write-1-clear on soft; level sources cleared when source drops)
//
//   Deferred (spec §2 remainder):
//     * Edge trigger + polarity per source
//     * ACTIVE tracking + RUNNING_PRIO for nested-priority enforcement
//     * Multi-vector CPU dispatch (needs CPU-side EIC hook)
// =============================================================================

module apb_vic #(
    parameter NUM_SOURCES = 32
) (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    input  wire [NUM_SOURCES-1:0] src_in,
    output wire                    irq,
    output wire [7:0]              vec_id,
    output wire [3:0]              vec_prio
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;

    // ------------- registers -------------
    reg [NUM_SOURCES-1:0] enable_r;
    reg [NUM_SOURCES-1:0] soft_r;
    reg [3:0] prio_r [NUM_SOURCES-1:0];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_r <= {NUM_SOURCES{1'b0}};
            soft_r   <= {NUM_SOURCES{1'b0}};
            for (i = 0; i < NUM_SOURCES; i = i + 1) prio_r[i] <= 4'h0;
        end else if (wr) begin
            case (paddr[11:2])
                10'h002: enable_r <= pwdata[NUM_SOURCES-1:0];       // 0x008 ENABLE
                10'h003: enable_r <= enable_r |  pwdata[NUM_SOURCES-1:0]; // 0x00C SET
                10'h004: enable_r <= enable_r & ~pwdata[NUM_SOURCES-1:0]; // 0x010 CLR
                10'h007: soft_r   <= soft_r   |  pwdata[NUM_SOURCES-1:0]; // 0x01C SOFT
                10'h008: soft_r   <= soft_r   & ~pwdata[NUM_SOURCES-1:0]; // 0x020 SOFT_CLR
                default: begin
                    // PRIO regs at 0x100 + 4*i
                    if (paddr[11:8] == 4'h1) begin
                        prio_r[paddr[7:2]] <= pwdata[3:0];
                    end
                    // ACK at 0x208 — level src cleared automatically; clear soft only
                    if (paddr == 12'h208) begin
                        soft_r <= soft_r & ~pwdata[NUM_SOURCES-1:0];
                    end
                end
            endcase
        end
    end

    // ------------- pending computation -------------
    wire [NUM_SOURCES-1:0] raw     = src_in | soft_r;
    wire [NUM_SOURCES-1:0] pending = raw & enable_r;

    // ------------- priority encoder -------------
    reg [7:0] best_id;
    reg [3:0] best_pri;
    reg       any_pend;
    always @(*) begin
        best_id  = 8'hFF;
        best_pri = 4'h0;
        any_pend = 1'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (pending[i] && (prio_r[i] > best_pri || !any_pend)) begin
                best_id  = i[7:0];
                best_pri = prio_r[i];
                any_pend = 1'b1;
            end
        end
    end

    assign vec_id   = best_id;
    assign vec_prio = best_pri;
    assign irq      = any_pend;

    // ------------- APB read -------------
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            case (paddr[11:2])
                10'h000: prdata = {{(32-NUM_SOURCES){1'b0}}, raw};       // INTR_RAW
                10'h001: prdata = {{(32-NUM_SOURCES){1'b0}}, pending};   // INTR_MASKED
                10'h002: prdata = {{(32-NUM_SOURCES){1'b0}}, enable_r};
                10'h007: prdata = {{(32-NUM_SOURCES){1'b0}}, soft_r};
                10'h080: prdata = {24'h0, best_id};                       // 0x200 VEC_ID
                10'h081: prdata = {28'h0, best_pri};                       // 0x204 VEC_IPRIO
                default: begin
                    if (paddr[11:8] == 4'h1)
                        prdata = {28'h0, prio_r[paddr[7:2]]};
                    else
                        prdata = 32'h0;
                end
            endcase
        end
    end

endmodule
