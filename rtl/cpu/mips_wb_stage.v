// =============================================================================
// File Name: mips_wb_stage.v
// Design:    WB Stage
// Author:    Antigravity
// =============================================================================

module mips_wb_stage (
    input  wire [31:0] mem_rdata_fmt,
    input  wire [31:0] ex_out,
    input  wire [31:0] pc_plus_8,
    input  wire [1:0]  mem_to_reg,
    input  wire [31:0] cp0_data,
    
    output reg  [31:0] wb_wdata
);

    always @(*) begin
        case (mem_to_reg)
            2'b00: wb_wdata = ex_out;
            2'b01: wb_wdata = mem_rdata_fmt;
            2'b10: wb_wdata = pc_plus_8;
            2'b11: wb_wdata = cp0_data;
            default: wb_wdata = ex_out;
        endcase
    end

endmodule
