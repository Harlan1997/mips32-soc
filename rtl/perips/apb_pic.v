// =============================================================================
// File Name: apb_pic.v
// Design:    Programmable Interrupt Controller (PIC)
// Author:    Antigravity
// Description:
//   Collects up to 32 interrupt sources and generates a single interrupt signal
//   to the CPU. Supports masking and pending status.
//
// Registers (APB):
//   0x00: INT_STATUS (Read-only, raw unmasked interrupt inputs)
//   0x04: INT_MASK   (Read/Write, 1 = Enable interrupt, 0 = Mask)
//   0x08: INT_ACTIVE (Read-only, STATUS & MASK)
// =============================================================================

module apb_pic (
    input  wire        pclk,
    input  wire        presetn,

    // APB Slave Interface
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire        pready,
    output reg  [31:0] prdata,
    output wire        pslverr,

    // Interrupt Sources
    input  wire [31:0] irq_sources,

    // CPU Interrupt Output
    output wire        cpu_int
);

    // Register File
    reg [31:0] int_mask;
    
    // Internal Signals
    wire [31:0] int_status = irq_sources;
    wire [31:0] int_active = int_status & int_mask;
    
    // Output to CPU
    assign cpu_int = (int_active != 32'd0);

    wire apb_write = psel & penable & pwrite;
    wire apb_read  = psel & ~pwrite;
    
    // Write Logic
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            int_mask <= 32'd0;
        end else begin
            if (apb_write && (paddr == 12'h004)) begin
                int_mask <= pwdata;
            end
        end
    end

    // Read Logic
    always @(*) begin
        if (psel) begin
            case (paddr)
                12'h000: prdata = int_status;
                12'h004: prdata = int_mask;
                12'h008: prdata = int_active;
                default: prdata = 32'd0;
            endcase
        end else begin
            prdata = 32'd0;
        end
    end
    
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

endmodule
