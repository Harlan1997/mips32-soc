// =============================================================================

`include "../include/soc_config.vh"
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
    input  wire        we,

    // MIPS32r2 software-selected shadow register set. These ports are tied to
    // bank zero in legacy users and are ignored unless SOC_SRS_ENABLE is set.
    input  wire [3:0]  current_set,
    input  wire [3:0]  previous_set,
    input  wire [4:0]  shadow_raddr,
    output wire [31:0] shadow_rdata,
    input  wire        shadow_we,
    input  wire [3:0]  shadow_wset,
    input  wire [4:0]  shadow_waddr,
    input  wire [31:0] shadow_wdata,

    // Packed context image uses register index * 32 as bit offset.
    input  wire        ctx_save_req,
    output wire        ctx_save_done,
    output wire [1023:0] ctx_save_data,
    output wire [16383:0] ctx_save_srs_data,
    input  wire        ctx_restore_req,
    input  wire [1023:0] ctx_restore_data,
    input  wire [16383:0] ctx_restore_srs_data,
    input  wire [3:0]  ctx_restore_set,
    output wire        ctx_restore_done
);

    // Sixteen 32-register sets. Set zero is the legacy bank. Register zero is
    // hardwired to zero in every set and is never written.
    reg [31:0] regs [0:511];
    wire [3:0] active_set = (^current_set === 1'bx) ? 4'd0 : current_set;
    wire [3:0] active_prev_set = (^previous_set === 1'bx) ? 4'd0 : previous_set;
    wire [3:0] restore_set = (^ctx_restore_set === 1'bx) ? active_set : ctx_restore_set;
    wire [8:0] active_ridx1 = {active_set, raddr1};
    wire [8:0] active_ridx2 = {active_set, raddr2};
    wire [8:0] active_shadow_ridx = {active_prev_set, shadow_raddr};
    wire [8:0] shadow_widx = {shadow_wset, shadow_waddr};

    // Asynchronous Read with internal forwarding/bypass
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 :
                    ((we && (waddr == raddr1)) ? wdata : regs[active_ridx1]);
                    
    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 :
                    ((we && (waddr == raddr2)) ? wdata : regs[active_ridx2]);

    assign shadow_rdata = (shadow_raddr == 5'd0) ? 32'd0 :
                          ((shadow_we && (shadow_wset == active_prev_set) &&
                            (shadow_waddr == shadow_raddr)) ? shadow_wdata :
                           regs[active_shadow_ridx]);

    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : gen_ctx_image
            if (g == 0)
                assign ctx_save_data[g*32 +: 32] = 32'd0;
            else
                assign ctx_save_data[g*32 +: 32] = regs[{active_set, g[4:0]}];
        end
        for (g = 0; g < 512; g = g + 1) begin : gen_srs_ctx_image
            assign ctx_save_srs_data[g*32 +: 32] = regs[g];
        end
    endgenerate

    assign ctx_save_done = ctx_save_req;
    assign ctx_restore_done = ctx_restore_req;

    // Synchronous Write
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 512; i = i + 1)
                regs[i] <= 32'd0;
        end else if (ctx_restore_req) begin
            for (i = 1; i < 32; i = i + 1)
                regs[{restore_set, i[4:0]}] <= ctx_restore_data[i*32 +: 32];
            regs[{restore_set, 5'd0}] <= 32'd0;
            if (`SOC_SRS_ENABLE != 0) begin
                for (i = 0; i < 512; i = i + 1)
                    regs[i] <= (i[4:0] == 0) ? 32'd0 :
                               ctx_restore_srs_data[i*32 +: 32];
            end
        end else if (shadow_we && (shadow_waddr != 5'd0)) begin
            regs[shadow_widx] <= shadow_wdata;
            if (we && (waddr != 5'd0))
                regs[{active_set, waddr}] <= wdata;
        end else if (we && (waddr != 5'd0)) begin
            regs[{active_set, waddr}] <= wdata;
        end
    end

endmodule
