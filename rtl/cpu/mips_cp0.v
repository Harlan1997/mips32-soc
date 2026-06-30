// =============================================================================
// File Name: mips_cp0.v
// Design:    MIPS32 Coprocessor 0 (Exceptions & Interrupts)
// Author:    Antigravity
// =============================================================================

module mips_cp0 (
    input  wire        clk,
    input  wire        rst_n,
    
    // Hardware Interrupts (e.g. from Timer, External devices)
    input  wire [5:0]  hw_int,
    
    // MTC0/MFC0 Interface (from WB or MEM stage)
    input  wire        we,           // Write enable (MTC0)
    input  wire [4:0]  waddr,        // CP0 register address to write
    input  wire [31:0] wdata,        // Data to write
    input  wire [4:0]  raddr,        // CP0 register address to read (MFC0)
    output reg  [31:0] rdata,        // Data read
    
    // Exception Interface (from WB stage to ensure precise exceptions)
    input  wire        except_req,   // Exception request
    input  wire [4:0]  except_code,  // Exception code
    input  wire [31:0] except_pc,    // PC of the instruction causing the exception
    input  wire        except_bd,    // Is the instruction in a branch delay slot?
    input  wire        eret,         // ERET instruction
    
    // Outputs to CPU Control
    output wire [31:0] epc_out,      // EPC register value (for ERET)
    output wire        intr_req      // Interrupt request to CPU (if enabled)
);

    // CP0 Registers
    // Reg 12: Status
    // [15:8] IM (Interrupt Mask)
    // [1] EXL (Exception Level)
    // [0] IE (Interrupt Enable)
    reg [31:0] cp0_status;
    
    // Reg 13: Cause
    // [31] BD (Branch Delay)
    // [15:10] IP (Interrupt Pending - hardware)
    // [9:8] IP (Interrupt Pending - software)
    // [6:2] ExcCode (Exception Code)
    reg [31:0] cp0_cause;
    
    // Reg 14: EPC (Exception Program Counter)
    reg [31:0] cp0_epc;

    // Interrupt Request Logic
    // Interrupts are requested if IE=1, EXL=0, and any unmasked IP bit is set.
    assign intr_req = cp0_status[0] && !cp0_status[1] && (|(cp0_cause[15:8] & cp0_status[15:8]));
    
    assign epc_out = cp0_epc;

    // CP0 Read Logic (MFC0)
    always @(*) begin
        case (raddr)
            5'd12: rdata = cp0_status;
            5'd13: rdata = cp0_cause;
            5'd14: rdata = cp0_epc;
            default: rdata = 32'd0;
        endcase
    end

    // CP0 Write and Exception Update Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initial Status: EXL=0, IE=0, IM=0 (All interrupts masked, disabled)
            cp0_status <= 32'h00000000;
            cp0_cause  <= 32'h00000000;
            cp0_epc    <= 32'h00000000;
        end else begin
            // Update Hardware Interrupt Pending bits continuously
            cp0_cause[15:10] <= hw_int;
            
            if (except_req && !cp0_status[1]) begin
                // Handle Exception (only if not already in exception level)
                $display("[%t] EXCEPTION TAKEN! cause=%h, epc=%h, intr_req=%b, hw_int=%b", $time, except_code, except_pc, intr_req, hw_int);
                cp0_status[1]  <= 1'b1; // Set EXL
                cp0_cause[6:2] <= except_code;
                cp0_cause[31]  <= except_bd;
                
                // VCS coverage off
                if (except_bd)
                    cp0_epc <= except_pc - 32'd4; // Point to branch instruction
                else
                // VCS coverage on
                    cp0_epc <= except_pc;         // Point to faulting instruction
                    
            end else if (eret) begin
                // Handle ERET
                cp0_status[1] <= 1'b0; // Clear EXL
                
            end else if (we) begin
                // Handle MTC0
                case (waddr)
                    5'd12: begin
                        cp0_status[15:8] <= wdata[15:8]; // IM
                        cp0_status[1]    <= wdata[1];    // EXL
                        cp0_status[0]    <= wdata[0];    // IE
                    end
                    5'd13: begin
                        cp0_cause[9:8] <= wdata[9:8];    // Software interrupts
                    end
                    5'd14: begin
                        cp0_epc <= wdata;
                    end
                endcase
            end
        end
    end

endmodule
