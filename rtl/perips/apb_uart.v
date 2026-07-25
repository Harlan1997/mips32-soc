// =============================================================================
// File Name: apb_uart.v
// Design:    Simple APB UART for Simulation
// Author:    Antigravity
// Description:
//   A dummy UART that intercepts writes to its TX register (offset 0x0)
//   and prints the character to the simulation console using $write.
//   Also has a simple status register at offset 0x4 (always Ready).
// =============================================================================

module apb_uart (
    input  wire        clk,
    input  wire        rst_n,

    // APB Slave Interface
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    output wire        pready,
    output wire [31:0] prdata,
    output wire        pslverr,

    output wire        tx_int,
    output wire        rx_int
);

    // TX Data Register: offset 0x0
    // TX Status Register: offset 0x4 (Bit 0: TX Ready)
    // IRQ Status Register: offset 0x8 (Bit 1: TX interrupt pending)
    // IRQ Clear Register: offset 0xC (write 1 to bit 1 to clear TX interrupt)
    
    assign pready  = 1'b1; // Zero wait state
    assign pslverr = 1'b0; // No errors
    
    reg [31:0] read_data;
    reg        tx_irq_pending;
    assign prdata = read_data;
    assign tx_int = tx_irq_pending;
    assign rx_int = 1'b0;
    
    always @(*) begin
        if (psel && !pwrite) begin
            case (paddr[7:0])
                8'h04: read_data = {30'd0, tx_irq_pending, 1'b1};
                8'h08: read_data = {30'd0, tx_irq_pending, 1'b0};
                default: read_data = 32'd0;
            endcase
        end else begin
            read_data = 32'd0;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_irq_pending <= 1'b0;
        end else begin
            if (psel && penable && pwrite) begin
                case (paddr[7:0])
                    8'h00: begin
                        // Write to TX Data
                        $write("%c", pwdata[7:0]);
                        $display("[%t] UART WRITE: '%c' (0x%h)", $time, pwdata[7:0], pwdata[7:0]);
                        tx_irq_pending <= 1'b1;
                    end
                    8'h0C: begin
                        if (pwdata[1]) begin
                            tx_irq_pending <= 1'b0;
                        end
                    end
                endcase
            end
        end
    end

endmodule
