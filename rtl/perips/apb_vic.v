// =============================================================================
// File Name: apb_vic.v
// Design:    Vectored Interrupt Controller — full implementation
// Author:    Antigravity — Phase D
// Description:
//   Complete VIC per docs/block_specs/vic_spec.md §2. Replaces the earlier
//   scaffold; still not integrated (apb_pic.v remains in DUT).
//
//   Features:
//     * NUM_SOURCES (default 32) with per-source enable + 4-bit priority
//     * Per-source trigger type: level or edge
//     * Per-source polarity: 0 = active-high / rising edge,
//                            1 = active-low  / falling edge
//     * Software-triggered sources (INTR_SOFT / INTR_SOFT_CLR)
//     * Priority encoder → VEC_ID + VEC_IPRIO
//     * ACTIVE tracking + RUNNING_PRIO for nested priority enforcement
//     * ACK: level-src clears when source drops; edge/soft cleared by W1C
//     * Combined irq → CPU (level), only asserted when highest-pending
//       priority strictly exceeds RUNNING_PRIO (nesting rule)
//
//   Register map (all addresses byte-offset):
//     0x000 INTR_RAW      RO  raw synchronized inputs (post edge-detect)
//     0x004 INTR_MASKED   RO  raw & enable
//     0x008 INTR_ENABLE   RW  per-source mask
//     0x00C INTR_ENABLE_SET  W1S
//     0x010 INTR_ENABLE_CLR  W1C
//     0x014 INTR_TYPE     RW  0=level 1=edge
//     0x018 INTR_POLARITY RW  0=high/rising 1=low/falling
//     0x01C INTR_SOFT     RW  software-triggered pending
//     0x020 INTR_SOFT_CLR W1C
//     0x100..0x17C  INTR_PRIO[0..31]  each 4-bit priority in a 32-bit word
//     0x200 VEC_ID        RO  8-bit highest-priority source id (0xFF if none)
//     0x204 VEC_IPRIO     RO  4-bit priority of that source
//     0x208 ACK           W1C  ISR ack (edge sources: clear pending;
//                              also clears the corresponding ACTIVE bit)
//     0x20C ACTIVE        RO  currently-being-serviced source bitmap
//     0x210 RUNNING_PRIO  RO  highest ACTIVE priority (for nesting decisions)
// =============================================================================

module apb_vic #(
    parameter NUM_SOURCES = 32
) (
    input  wire        clk,
    input  wire        rst_n,

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

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg [NUM_SOURCES-1:0] enable_r;
    reg [NUM_SOURCES-1:0] type_r;         // 0=level 1=edge
    reg [NUM_SOURCES-1:0] polarity_r;     // 0=high/rising 1=low/falling
    reg [NUM_SOURCES-1:0] soft_r;
    reg [NUM_SOURCES-1:0] edge_pending_r; // sticky bit for edge sources
    reg [NUM_SOURCES-1:0] active_r;       // ISR-in-progress bitmap
    reg [3:0]             prio_r [NUM_SOURCES-1:0];

    // Input synchronization + edge detection
    reg [NUM_SOURCES-1:0] src_sync1;
    reg [NUM_SOURCES-1:0] src_sync2;
    reg [NUM_SOURCES-1:0] src_sync3;
    wire [NUM_SOURCES-1:0] src_norm = src_sync2 ^ polarity_r; // normalize
    wire [NUM_SOURCES-1:0] src_norm_d = src_sync3 ^ polarity_r;
    wire [NUM_SOURCES-1:0] rising_edge = src_norm & ~src_norm_d;

    integer i;

    // ------------------------------------------------------------------
    // Input sync + edge-pending capture
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_sync1      <= {NUM_SOURCES{1'b0}};
            src_sync2      <= {NUM_SOURCES{1'b0}};
            src_sync3      <= {NUM_SOURCES{1'b0}};
            edge_pending_r <= {NUM_SOURCES{1'b0}};
        end else begin
            src_sync1 <= src_in;
            src_sync2 <= src_sync1;
            src_sync3 <= src_sync2;
            for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                if (type_r[i] && rising_edge[i]) begin
                    edge_pending_r[i] <= 1'b1;
                end
                // ACK / W1C on edge_pending is handled in the APB block below
            end
        end
    end

    // ------------------------------------------------------------------
    // APB writes
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_r   <= {NUM_SOURCES{1'b0}};
            type_r     <= {NUM_SOURCES{1'b0}};
            polarity_r <= {NUM_SOURCES{1'b0}};
            soft_r     <= {NUM_SOURCES{1'b0}};
            active_r   <= {NUM_SOURCES{1'b0}};
            for (i = 0; i < NUM_SOURCES; i = i + 1) prio_r[i] <= 4'h0;
        end else if (wr) begin
            case (paddr[11:2])
                10'h002: enable_r   <= pwdata[NUM_SOURCES-1:0];              // ENABLE
                10'h003: enable_r   <= enable_r   |  pwdata[NUM_SOURCES-1:0];// SET
                10'h004: enable_r   <= enable_r   & ~pwdata[NUM_SOURCES-1:0];// CLR
                10'h005: type_r     <= pwdata[NUM_SOURCES-1:0];              // TYPE
                10'h006: polarity_r <= pwdata[NUM_SOURCES-1:0];              // POLARITY
                10'h007: soft_r     <= soft_r     |  pwdata[NUM_SOURCES-1:0];// SOFT
                10'h008: soft_r     <= soft_r     & ~pwdata[NUM_SOURCES-1:0];// SOFT_CLR
                10'h082: begin // 0x208 ACK — clear pending + active for W1C bits
                    for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                        if (pwdata[i]) begin
                            active_r[i]       <= 1'b0;
                            edge_pending_r[i] <= 1'b0;
                            soft_r[i]         <= 1'b0;
                        end
                    end
                end
                default: begin
                    if (paddr[11:8] == 4'h1) begin
                        prio_r[paddr[7:2]] <= pwdata[3:0];
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Pending computation
    //   level source: pending = src_norm (level-normalized)
    //   edge  source: pending = edge_pending_r (sticky)
    //   soft always pending
    // ------------------------------------------------------------------
    wire [NUM_SOURCES-1:0] level_pend = src_norm & ~type_r;
    wire [NUM_SOURCES-1:0] raw        = level_pend | edge_pending_r | soft_r;
    wire [NUM_SOURCES-1:0] pending    = raw & enable_r;

    // ------------------------------------------------------------------
    // Priority encoder → highest-priority pending
    // Tie-break: lower source id wins (encoder iteration order)
    // ------------------------------------------------------------------
    reg [7:0] best_id_r;
    reg [3:0] best_pri_r;
    reg       any_pend_r;
    always @(*) begin
        best_id_r  = 8'hFF;
        best_pri_r = 4'h0;
        any_pend_r = 1'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (pending[i] && (prio_r[i] > best_pri_r || !any_pend_r)) begin
                best_id_r  = i[7:0];
                best_pri_r = prio_r[i];
                any_pend_r = 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // RUNNING_PRIO from active_r bitmap
    // ------------------------------------------------------------------
    reg [3:0] running_prio_r;
    reg       any_active_r;
    always @(*) begin
        running_prio_r = 4'h0;
        any_active_r   = 1'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (active_r[i] && (prio_r[i] > running_prio_r || !any_active_r)) begin
                running_prio_r = prio_r[i];
                any_active_r   = 1'b1;
            end
        end
    end

    // IRQ only fires if best pending priority > running priority
    // (nesting: same priority cannot preempt)
    assign irq      = any_pend_r && (!any_active_r || best_pri_r > running_prio_r);
    assign vec_id   = best_id_r;
    assign vec_prio = best_pri_r;

    // Latch active on CPU accept — approximated as: whenever irq is high and
    // software reads VEC_ID, transition that source into active. (The real
    // EIC signal would be a dedicated ack pin from CPU; using VEC_ID read
    // as the accept event is a common shim until CPU-side EIC hook lands.)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // active_r reset done above
        end else if (rd && paddr[11:2] == 10'h080 && any_pend_r && irq) begin
            active_r[best_id_r[$clog2(NUM_SOURCES)-1:0]] <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // APB reads
    // ------------------------------------------------------------------
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            case (paddr[11:2])
                10'h000: prdata = {{(32-NUM_SOURCES){1'b0}}, raw};
                10'h001: prdata = {{(32-NUM_SOURCES){1'b0}}, pending};
                10'h002: prdata = {{(32-NUM_SOURCES){1'b0}}, enable_r};
                10'h005: prdata = {{(32-NUM_SOURCES){1'b0}}, type_r};
                10'h006: prdata = {{(32-NUM_SOURCES){1'b0}}, polarity_r};
                10'h007: prdata = {{(32-NUM_SOURCES){1'b0}}, soft_r};
                10'h080: prdata = {24'h0, best_id_r};
                10'h081: prdata = {28'h0, best_pri_r};
                10'h083: prdata = {{(32-NUM_SOURCES){1'b0}}, active_r};
                10'h084: prdata = {28'h0, running_prio_r};
                default: begin
                    if (paddr[11:8] == 4'h1)
                        prdata = {28'h0, prio_r[paddr[7:2]]};
                end
            endcase
        end
    end

endmodule
