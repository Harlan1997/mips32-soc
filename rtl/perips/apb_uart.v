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
    output wire        pslverr
);

    // TX Data Register: offset 0x0
    // TX Status Register: offset 0x4 (Bit 0: TX Ready)
    
    assign pready  = 1'b1; // Zero wait state
    assign pslverr = 1'b0; // No errors
    
    reg [31:0] read_data;
    assign prdata = read_data;
    
    always @(*) begin
        if (psel && !pwrite) begin
            if (paddr[7:0] == 8'h04) begin
                read_data = 32'd1; // TX Ready is always 1 in simulation
            end else begin
                read_data = 32'd0;
            end
        end else begin
            read_data = 32'd0;
        end
    end
    
    always @(posedge clk) begin
        if (rst_n) begin
            if (psel && penable && pwrite) begin
                if (paddr[7:0] == 8'h00) begin
                    // Write to TX Data
                    $write("%c", pwdata[7:0]);
                    $display("[%t] UART WRITE: '%c' (0x%h)", $time, pwdata[7:0], pwdata[7:0]);
                    // Flush standard output if newline
                end
            end
        end
    end

endmodule
