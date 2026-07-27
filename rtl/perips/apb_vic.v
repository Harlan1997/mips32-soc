// =============================================================================
// File Name: apb_vic.v
// Design:    Vectored Interrupt Controller — Phase 4D Commercial Baseline
// Author:    Antigravity — Phase 4D
// Description:
//   Commercial-grade Vectored Interrupt Controller (apb_vic) for MIPS32 SoC.
//   Phase 4D contract:
//     - Single interrupt output line (`irq`) to CPU CP0 Cause.IP[x]
//     - APB-accessible register interface with single sequential state writers
//     - Priority arbitration with lower-ID tie-breaking
//     - Priority nesting via ACTIVE bitmap and RUNNING_PRIO tracking
//     - Software accept event on reading VEC_ID while `irq` is asserted
//     - Support for level-high, level-low, rising-edge, falling-edge, and soft IRQs
//
// Register Map (Byte Offsets):
//   0x000 INTR_RAW       RO  raw synchronized input / soft pending state
//   0x004 INTR_ENABLE    RW  per-source enable mask (1 = allow)
//   0x008 INTR_MASKED    RO  enabled pending state
//   0x00C ENABLE_SET     W1S write 1 to set enable bits
//   0x010 ENABLE_CLR     W1C write 1 to clear enable bits
//   0x014 TYPE           RW  0 = level, 1 = edge
//   0x018 POLARITY       RW  0 = active-high / rising, 1 = active-low / falling
//   0x01C SOFT           RW  write 1 to set software pending bits
//   0x020 SOFT_CLR       W1C write 1 to clear software pending bits
//   0x100..0x17C PRIO[i] RW  4-bit priority for source i
//   0x200 VEC_ID         RO  highest priority pending source ID (0xFF if none)
//   0x204 VEC_IPRIO      RO  priority of highest pending source (0 if none)
//   0x208 ACK            W1C clear active, edge pending, and soft pending bits
//   0x20C ACTIVE         RO  active interrupt bitmap currently in service
//   0x210 RUNNING_PRIO   RO  highest priority among active sources
// =============================================================================

module apb_vic #(
    parameter NUM_SOURCES = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    psel,
    input  wire                    penable,
    input  wire                    pwrite,
    input  wire [11:0]             paddr,
    input  wire [31:0]             pwdata,
    output reg  [31:0]             prdata,
    output wire                    pready,
    output wire                    pslverr,

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
    // State Registers (Single Sequential Writer per Register)
    // ------------------------------------------------------------------
    reg [NUM_SOURCES-1:0] enable_r;
    reg [NUM_SOURCES-1:0] type_r;         // 0=level, 1=edge
    reg [NUM_SOURCES-1:0] polarity_r;     // 0=high/rising, 1=low/falling
    reg [NUM_SOURCES-1:0] soft_r;         // software pending
    reg [NUM_SOURCES-1:0] edge_pending_r; // sticky edge pending
    reg [NUM_SOURCES-1:0] active_r;       // ISR active bitmap
    reg [3:0]             prio_r [NUM_SOURCES-1:0];

    // Synchronizer flops
    reg [NUM_SOURCES-1:0] src_sync1;
    reg [NUM_SOURCES-1:0] src_sync2;
    reg [NUM_SOURCES-1:0] src_sync3;

    integer i;

    // 1. Input Synchronizer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_sync1 <= {NUM_SOURCES{1'b0}};
            src_sync2 <= {NUM_SOURCES{1'b0}};
            src_sync3 <= {NUM_SOURCES{1'b0}};
        end else begin
            src_sync1 <= src_in;
            src_sync2 <= src_sync1;
            src_sync3 <= src_sync2;
        end
    end

    // Input normalization & edge detection
    wire [NUM_SOURCES-1:0] src_norm   = src_sync2 ^ polarity_r;
    wire [NUM_SOURCES-1:0] src_norm_d = src_sync3 ^ polarity_r;
    wire [NUM_SOURCES-1:0] rising_edge = src_norm & ~src_norm_d;

    // 2. Enable Register (enable_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_r <= {NUM_SOURCES{1'b0}};
        end else if (wr) begin
            case (paddr[11:2])
                10'h001: enable_r <= pwdata[NUM_SOURCES-1:0];               // 0x004 INTR_ENABLE
                10'h003: enable_r <= enable_r | pwdata[NUM_SOURCES-1:0];  // 0x00C ENABLE_SET
                10'h004: enable_r <= enable_r & ~pwdata[NUM_SOURCES-1:0]; // 0x010 ENABLE_CLR
                default: ;
            endcase
        end
    end

    // 3. Type Register (type_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            type_r <= {NUM_SOURCES{1'b0}};
        end else if (wr && (paddr[11:2] == 10'h005)) begin // 0x014 TYPE
            type_r <= pwdata[NUM_SOURCES-1:0];
        end
    end

    // 4. Polarity Register (polarity_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            polarity_r <= {NUM_SOURCES{1'b0}};
        end else if (wr && (paddr[11:2] == 10'h006)) begin // 0x018 POLARITY
            polarity_r <= pwdata[NUM_SOURCES-1:0];
        end
    end

    // 5. Software Interrupt Register (soft_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            soft_r <= {NUM_SOURCES{1'b0}};
        end else if (wr) begin
            case (paddr[11:2])
                10'h007: soft_r <= soft_r |  pwdata[NUM_SOURCES-1:0]; // 0x01C SOFT
                10'h008: soft_r <= soft_r & ~pwdata[NUM_SOURCES-1:0]; // 0x020 SOFT_CLR
                10'h082: soft_r <= soft_r & ~pwdata[NUM_SOURCES-1:0]; // 0x208 ACK
                default: ;
            endcase
        end
    end

    // 6. Edge Pending Register (edge_pending_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_pending_r <= {NUM_SOURCES{1'b0}};
        end else begin
            for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                if (type_r[i] && rising_edge[i]) begin
                    edge_pending_r[i] <= 1'b1;
                end else if (wr && (paddr[11:2] == 10'h082) && pwdata[i]) begin // 0x208 ACK
                    edge_pending_r[i] <= 1'b0;
                end
            end
        end
    end

    // Forward declarations of combinatorial encoder signals used by active_r
    reg [7:0] best_id_r;
    reg [3:0] best_pri_r;
    reg       any_pend_r;

    // 7. Active Register (active_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_r <= {NUM_SOURCES{1'b0}};
        end else if (wr && (paddr[11:2] == 10'h082)) begin // 0x208 ACK
            active_r <= active_r & ~pwdata[NUM_SOURCES-1:0];
        end else if (rd && (paddr[11:2] == 10'h080) && irq) begin // 0x200 VEC_ID read accept
            if (best_id_r < NUM_SOURCES) begin
                active_r[best_id_r[$clog2(NUM_SOURCES)-1:0]] <= 1'b1;
            end
        end
    end

    // 8. Priority Registers (prio_r)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                prio_r[i] <= 4'h0;
            end
        end else if (wr && (paddr[11:8] == 4'h1)) begin
            if (paddr[7:2] < NUM_SOURCES) begin
                prio_r[paddr[7:2]] <= pwdata[3:0];
            end
        end
    end

    // ------------------------------------------------------------------
    // Combinatorial Pending & Priority Arbitration
    // ------------------------------------------------------------------
    wire [NUM_SOURCES-1:0] level_pend = src_norm & ~type_r;
    wire [NUM_SOURCES-1:0] raw        = level_pend | edge_pending_r | soft_r;
    wire [NUM_SOURCES-1:0] pending    = raw & enable_r;

    // Priority Encoder: Find highest priority pending source.
    // Tie-break: lower source ID wins.
    always @(*) begin
        best_id_r  = 8'hFF;
        best_pri_r = 4'h0;
        any_pend_r = 1'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (pending[i]) begin
                if (!any_pend_r || (prio_r[i] > best_pri_r)) begin
                    best_id_r  = i[7:0];
                    best_pri_r = prio_r[i];
                    any_pend_r = 1'b1;
                end
            end
        end
    end

    // RUNNING_PRIO: Highest priority among currently active sources.
    reg [3:0] running_prio_r;
    reg       any_active_r;
    always @(*) begin
        running_prio_r = 4'h0;
        any_active_r   = 1'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (active_r[i]) begin
                if (!any_active_r || (prio_r[i] > running_prio_r)) begin
                    running_prio_r = prio_r[i];
                    any_active_r   = 1'b1;
                end
            end
        end
    end

    // Interrupt signal: Asserted only when best pending source strictly preempts RUNNING_PRIO
    assign irq      = any_pend_r && (!any_active_r || (best_pri_r > running_prio_r));
    assign vec_id   = best_id_r;
    assign vec_prio = best_pri_r;

    // ------------------------------------------------------------------
    // APB Read Data Bus
    // ------------------------------------------------------------------
    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            case (paddr[11:2])
                10'h000: prdata = 32'h0 | raw;        // 0x000 INTR_RAW
                10'h001: prdata = 32'h0 | enable_r;   // 0x004 INTR_ENABLE
                10'h002: prdata = 32'h0 | pending;    // 0x008 INTR_MASKED
                10'h005: prdata = 32'h0 | type_r;     // 0x014 TYPE
                10'h006: prdata = 32'h0 | polarity_r; // 0x018 POLARITY
                10'h007: prdata = 32'h0 | soft_r;     // 0x01C SOFT
                10'h080: prdata = {24'h0, best_id_r}; // 0x200 VEC_ID
                10'h081: prdata = {28'h0, best_pri_r};// 0x204 VEC_IPRIO
                10'h083: prdata = 32'h0 | active_r;   // 0x20C ACTIVE
                10'h084: prdata = {28'h0, running_prio_r}; // 0x210 RUNNING_PRIO
                default: begin
                    if ((paddr[11:8] == 4'h1) && (paddr[7:2] < NUM_SOURCES)) begin
                        prdata = {28'h0, prio_r[paddr[7:2]]};
                    end
                end
            endcase
        end
    end

endmodule
