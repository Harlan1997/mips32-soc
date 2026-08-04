// =============================================================================
// File Name: mips_mem_stage.v
// Design:    MIPS32 MEM (Memory Access) Stage
// Author:    Antigravity
// Description:
//   Handles memory alignment for loads and stores (LB, LBU, LH, LHU, LW, SB, SH, SW).
//   Detects Address Error Exceptions (AdEL/AdES).
// =============================================================================

module mips_mem_stage (
    // Inputs from EX/MEM pipeline register
    input  wire [31:0] mem_ex_out,     // Address from ALU
    input  wire [31:0] mem_val_rt,     // Store data from register
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  mem_op,         // 000:B, 001:BU, 010:H, 011:HU, 100:W
    input  wire        mem_done,
    input  wire        mem_cache_op_valid,
    input  wire [4:0]  mem_cache_op,
    
    // Inputs from Data Memory / Cache
    input  wire [31:0] dmem_rdata,
    
    // Outputs to Data Memory / Cache
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_we,        // Write enable
    output wire [3:0]  dmem_be,        // Byte enables
    output wire        dmem_en,        // Memory request enable
    input  wire        dmem_addr_ok,
    input  wire        dmem_data_ok,
    input  wire        cache_op_done,
    input  wire        cache_op_error,
    
    // Outputs to Pipeline Control
    output wire        stall_req_mem,
    output wire        cache_op_valid,
    output wire [4:0]  cache_op,
    output wire [31:0] cache_op_addr,
    output wire        cache_op_fault,

    
    // Outputs to WB Stage
    output reg  [31:0] mem_rdata_ext,  // Formatted & extended read data
    
    // Exception Outputs
    output wire        adel_exception, // Address Error Load
    output wire        ades_exception  // Address Error Store
);

    // Basic outputs
    assign dmem_addr = {mem_ex_out[31:2], 2'b00}; // Word aligned access address
    assign dmem_en   = (mem_read | mem_write) & ~adel_exception & ~ades_exception & ~mem_done;
    assign dmem_we   = mem_write;
    assign cache_op_valid = mem_cache_op_valid & ~mem_done;
    assign cache_op       = mem_cache_op;
    assign cache_op_addr  = mem_ex_out;
    assign cache_op_fault = cache_op_valid & cache_op_done & cache_op_error;
    
    // Stall logic
    assign stall_req_mem = (dmem_en & ~dmem_data_ok) |
                           (cache_op_valid & ~cache_op_done);

    wire [1:0] addr_align = mem_ex_out[1:0];

    // Align & Duplicate store data
    reg [31:0] wdata_aligned;
    reg [3:0]  we_aligned;
    
    always @(*) begin
        wdata_aligned = 32'd0;
        we_aligned    = 4'b0000;
        
        if (mem_write) begin
            case (mem_op)
                3'b000: begin // SB: Store Byte
                    wdata_aligned = {4{mem_val_rt[7:0]}}; // Duplicate across all bytes
                    case (addr_align)
                        2'b00: we_aligned = 4'b0001;
                        2'b01: we_aligned = 4'b0010;
                        2'b10: we_aligned = 4'b0100;
                        2'b11: we_aligned = 4'b1000;
                        // VCS coverage off
                        default: we_aligned = 4'b0000;
                        // VCS coverage on
                    endcase
                end
                3'b010: begin // SH: Store Halfword
                    wdata_aligned = {2{mem_val_rt[15:0]}}; // Duplicate across both halfwords
                    case (addr_align[1])
                        1'b0: we_aligned = 4'b0011;
                        1'b1: we_aligned = 4'b1100;
                        // VCS coverage off
                        default: we_aligned = 4'b0000;
                        // VCS coverage on
                    endcase
                end
                3'b100, 3'b111: begin // SW / SC: Store Word
                    wdata_aligned = mem_val_rt;
                    we_aligned    = 4'b1111;
                end
                3'b101: begin // SWL (Little Endian)
                    case (addr_align)
                        2'b00: begin we_aligned = 4'b0001; wdata_aligned = {24'd0, mem_val_rt[31:24]}; end
                        2'b01: begin we_aligned = 4'b0011; wdata_aligned = {16'd0, mem_val_rt[31:16]}; end
                        2'b10: begin we_aligned = 4'b0111; wdata_aligned = {8'd0, mem_val_rt[31:8]}; end
                        2'b11: begin we_aligned = 4'b1111; wdata_aligned = mem_val_rt; end
                        // VCS coverage off
                        default: begin we_aligned = 4'b0000; wdata_aligned = 32'd0; end
                        // VCS coverage on
                    endcase
                end
                3'b110: begin // SWR (Little Endian)
                    case (addr_align)
                        2'b00: begin we_aligned = 4'b1111; wdata_aligned = mem_val_rt; end
                        2'b01: begin we_aligned = 4'b1110; wdata_aligned = {mem_val_rt[23:0], 8'd0}; end
                        2'b10: begin we_aligned = 4'b1100; wdata_aligned = {mem_val_rt[15:0], 16'd0}; end
                        2'b11: begin we_aligned = 4'b1000; wdata_aligned = {mem_val_rt[7:0], 24'd0}; end
                        // VCS coverage off
                        default: begin we_aligned = 4'b0000; wdata_aligned = 32'd0; end
                        // VCS coverage on
                    endcase
                end
                default: begin
                    wdata_aligned = 32'd0;
                    we_aligned    = 4'b0000;
                end
            endcase
        end
    end
    
    assign dmem_wdata = wdata_aligned;
    assign dmem_be    = we_aligned;

    // Load data formatting & extension
    always @(*) begin
        mem_rdata_ext = dmem_rdata; // default (e.g. LW)
        
        if (mem_read) begin
            case (mem_op)
                3'b000: begin // LB: Load Byte Signed
                    case (addr_align)
                        2'b00: mem_rdata_ext = { {24{dmem_rdata[7]}},  dmem_rdata[7:0] };
                        2'b01: mem_rdata_ext = { {24{dmem_rdata[15]}}, dmem_rdata[15:8] };
                        2'b10: mem_rdata_ext = { {24{dmem_rdata[23]}}, dmem_rdata[23:16] };
                        2'b11: mem_rdata_ext = { {24{dmem_rdata[31]}}, dmem_rdata[31:24] };
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                3'b001: begin // LBU: Load Byte Unsigned
                    case (addr_align)
                        2'b00: mem_rdata_ext = { 24'd0, dmem_rdata[7:0] };
                        2'b01: mem_rdata_ext = { 24'd0, dmem_rdata[15:8] };
                        2'b10: mem_rdata_ext = { 24'd0, dmem_rdata[23:16] };
                        2'b11: mem_rdata_ext = { 24'd0, dmem_rdata[31:24] };
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                3'b010: begin // LH: Load Halfword Signed
                    case (addr_align[1])
                        1'b0: mem_rdata_ext = { {16{dmem_rdata[15]}}, dmem_rdata[15:0] };
                        1'b1: mem_rdata_ext = { {16{dmem_rdata[31]}}, dmem_rdata[31:16] };
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                3'b011: begin // LHU: Load Halfword Unsigned
                    case (addr_align[1])
                        1'b0: mem_rdata_ext = { 16'd0, dmem_rdata[15:0] };
                        1'b1: mem_rdata_ext = { 16'd0, dmem_rdata[31:16] };
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                3'b100, 3'b111: begin // LW / LL: Load Word
                    mem_rdata_ext = dmem_rdata;
                end
                3'b101: begin // LWL (Little Endian)
                    case (addr_align)
                        2'b00: mem_rdata_ext = {dmem_rdata[7:0], mem_val_rt[23:0]};
                        2'b01: mem_rdata_ext = {dmem_rdata[15:0], mem_val_rt[15:0]};
                        2'b10: mem_rdata_ext = {dmem_rdata[23:0], mem_val_rt[7:0]};
                        2'b11: mem_rdata_ext = dmem_rdata;
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                3'b110: begin // LWR (Little Endian)
                    case (addr_align)
                        2'b00: mem_rdata_ext = dmem_rdata;
                        2'b01: mem_rdata_ext = {mem_val_rt[31:24], dmem_rdata[31:8]};
                        2'b10: mem_rdata_ext = {mem_val_rt[31:16], dmem_rdata[31:16]};
                        2'b11: mem_rdata_ext = {mem_val_rt[31:8], dmem_rdata[31:24]};
                        // VCS coverage off
                        default: mem_rdata_ext = dmem_rdata;
                        // VCS coverage on
                    endcase
                end
                default: begin
                    mem_rdata_ext = dmem_rdata;
                end
            endcase
        end
    end
    
    // Alignment Exception Checking
    wire bad_align_h = (mem_op == 3'b010 || mem_op == 3'b011) && (addr_align[0] != 1'b0);
    wire bad_align_w = (mem_op == 3'b100) && (addr_align != 2'b00);
    
    wire bad_align = bad_align_h | bad_align_w;
    
    assign adel_exception = mem_read & bad_align;
    assign ades_exception = mem_write & bad_align;

endmodule
