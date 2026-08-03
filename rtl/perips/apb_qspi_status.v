// =============================================================================
// File Name: apb_qspi_status.v
// Design:    APB-visible QSPI/XIP fault observability
// =============================================================================
// This block is deliberately an observability slice, not a QSPI controller.
// The memory subsystem supplies a sticky AXI-side XIP timeout indication and a
// static controller-present indication. Software can inspect the version,
// status and last error, then clear the captured error with W1C control.
//
// Register map (APB, byte offsets):
//   0x00 VERSION: 0x51535001 ("QSP", version 1)
//   0x04 STATUS : bit[0] XIP timeout captured, bit[1] controller present
//   0x08 ERROR  : [31:16] error class, [15:0] error code
//   0x0c CONTROL: bit[0] W1C status and last error
//
// Error class/code 0x0001/0x0001 denotes the bounded AXI XIP timeout. Other
// controller/boot sources may use error_event/error_value to publish the
// canonical taxonomy from docs/qspi_error_taxonomy.md. The source guards are
// edge detected so a W1C write is not immediately undone by a sticky source.

module apb_qspi_status (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        controller_present,
    input  wire        xip_timeout_sticky,
    input  wire        error_event,
    input  wire [31:0] error_value,

    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [4:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr
);

    localparam [31:0] VERSION_VALUE = 32'h5153_5001;
    localparam [31:0] XIP_TIMEOUT_ERROR = 32'h0001_0001;

    reg        timeout_captured_r;
    reg [31:0] last_error_r;
    reg        source_seen_r;
    reg        error_seen_r;

    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;
    wire timeout_rise = xip_timeout_sticky & ~source_seen_r;
    wire error_rise = error_event & ~error_seen_r;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_captured_r <= 1'b0;
            last_error_r       <= 32'h0000_0000;
            source_seen_r      <= 1'b0;
            error_seen_r       <= 1'b0;
        end else begin
            source_seen_r <= xip_timeout_sticky;
            error_seen_r  <= error_event;

            if (timeout_rise) begin
                timeout_captured_r <= 1'b1;
                last_error_r       <= XIP_TIMEOUT_ERROR;
            end

            if (error_rise) begin
                timeout_captured_r <= 1'b1;
                last_error_r       <= error_value;
            end

            // W1C has priority for a simultaneous source edge and software
            // clear; a still-high source is suppressed until it drops.
            if (wr && (paddr[4:2] == 3'b011) && pwdata[0]) begin
                timeout_captured_r <= 1'b0;
                last_error_r       <= 32'h0000_0000;
            end
        end
    end

    always @(*) begin
        prdata = 32'h0000_0000;
        if (rd) begin
            case (paddr[4:2])
                3'b000: prdata = VERSION_VALUE;
                3'b001: prdata = {30'd0, controller_present, timeout_captured_r};
                3'b010: prdata = last_error_r;
                3'b011: prdata = 32'h0000_0000;
                default: prdata = 32'h0000_0000;
            endcase
        end
    end
endmodule
