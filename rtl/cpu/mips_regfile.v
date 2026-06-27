// =============================================================================
// File Name: mips_regfile.v
// Design:    MIPS32 General-Purpose Register File (RegFile)
// Author:    Antigravity
// Description:
//   32 x 32-bit register file. Dual asynchronous read ports, single synchronous
//   write port. Incorporates internal write-to-read bypass logic to prevent
//   data hazards when reading and writing the same register in a single cycle.
// =============================================================================

module mips_regfile (
    input  wire        clk,
    input  wire        rst_n,
    
    // Read Ports
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,
    
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,
    
    // Write Port
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire        we
);

    // Register 0 is hardwired to 0. 31 registers are writeable.
    reg [31:0] regs [1:31];

    // Asynchronous Read with internal forwarding/bypass
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 :
                    ((we && (waddr == raddr1)) ? wdata : regs[raddr1]);
                    
    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 :
                    ((we && (waddr == raddr2)) ? wdata : regs[raddr2]);

    // Synchronous Write
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

endmodule
