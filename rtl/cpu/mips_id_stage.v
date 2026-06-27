// =============================================================================
// File Name: mips_id_stage.v
// Design:    MIPS32 ID (Instruction Decode) Stage Wrapper
// Author:    Antigravity
// Description:
//   Ties together the register file and control unit. Resolves branch and jump
//   decisions early in the ID stage using forwarding to reduce branch penalty.
//   Performs hazard detection for load-use stalls.
// =============================================================================

module mips_id_stage (
    input  wire        clk,
    input  wire        rst_n,
    
    // Instruction and PC from IF/ID Pipeline Register
    input  wire [31:0] inst,
    input  wire [31:0] pc_plus_4,    // PC + 4 of the current instruction
    
    // RegFile Writeback Interface (from WB stage)
    input  wire [4:0]  rf_waddr,
    input  wire [31:0] rf_wdata,
    input  wire        rf_we,
    
    // Forwarding paths from downstream stages for ID stage branch comparison
    input  wire        fw_ex_we,
    input  wire [4:0]  fw_ex_waddr,
    input  wire [31:0] fw_ex_val,
    
    input  wire        fw_mem_we,
    input  wire [4:0]  fw_mem_waddr,
    input  wire [31:0] fw_mem_val,
    
    input  wire        fw_wb_we,
    input  wire [4:0]  fw_wb_waddr,
    input  wire [31:0] fw_wb_val,
    
    // Hazard detection helper inputs
    input  wire        ex_mem_read,  // EX stage instruction is a Load
    input  wire [4:0]  ex_waddr,     // EX stage write register address
    input  wire        mem_mem_read, // MEM stage instruction is a Load
    
    // Outputs to Pipeline Control / Hazard Unit
    output wire        stall_req,    // Stall request due to load-use hazard
    
    // Outputs to Fetch (IF) stage
    output wire        branch_taken, // 1: Branch condition met
    output wire [31:0] branch_target,// Calculated branch target address
    output wire        jump_taken,   // 1: Jump instruction detected
    output wire [31:0] jump_target,   // Calculated jump target address
    
    // Decoded Outputs to ID/EX Pipeline Register
    output wire [31:0] val_rs,       // rs register value (with forwarding)
    output wire [31:0] val_rt,       // rt register value (with forwarding)
    output wire [31:0] imm_ext,      // Extended immediate value
    output wire [4:0]  waddr_out,    // Selected destination register address
    output wire [4:0]  sa_out,       // Shift amount
    output wire [4:0]  rs_addr,      // rs register address
    output wire [4:0]  rt_addr,      // rt register address
    output wire [4:0]  rd_addr,      // rd register address
    
    // Control Signals to ID/EX Pipeline Register
    output wire [3:0]  alu_op,
    output wire [2:0]  mdu_op,
    output wire        mdu_start,
    output wire        sel_mdu_out,
    output wire        alu_src,
    output wire        reg_write,
    output wire        mem_read,
    output wire        mem_write,
    output wire [2:0]  mem_op,
    output wire [1:0]  mem_to_reg,
    
    // CP0 and Exceptions
    output wire        cp0_we,
    output wire        is_eret,
    output wire        illegal_inst
);

    // Register File Address Extraction
    assign rs_addr = inst[25:21];
    assign rt_addr = inst[20:16];
    assign rd_addr = inst[15:11];

    // Raw Register File Outputs
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    // Instantiate General-Purpose Register File
    mips_regfile u_mips_regfile (
        .clk    (clk),
        .rst_n  (rst_n),
        .raddr1 (rs_addr),
        .rdata1 (rf_rdata1),
        .raddr2 (rt_addr),
        .rdata2 (rf_rdata2),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata),
        .we     (rf_we)
    );

    // Instantiate Control Unit
    wire [2:0] branch_op;
    wire [1:0] jump_op;
    wire       imm_signed;
    wire       use_sa;
    wire [1:0] reg_dst;

    mips_control u_mips_control (
        .inst        (inst),
        .alu_op      (alu_op),
        .mdu_op      (mdu_op),
        .mdu_start   (mdu_start),
        .sel_mdu_out (sel_mdu_out),
        .alu_src     (alu_src),
        .reg_write   (reg_write),
        .reg_dst     (reg_dst),
        .imm_signed  (imm_signed),
        .use_sa      (use_sa),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .mem_op      (mem_op),
        .mem_to_reg  (mem_to_reg),
        .branch_op   (branch_op),
        .jump_op     (jump_op),
        .illegal_inst(illegal_inst),
        .cp0_we      (cp0_we),
        .is_eret     (is_eret),
        .is_syscall  (is_syscall)
    );

    // Forwarding logic to resolve raw dependencies for ID-stage branch comparator
    assign val_rs = (rs_addr == 5'd0) ? 32'd0 :
                    ((fw_ex_we  && (fw_ex_waddr  == rs_addr)) ? fw_ex_val :
                     ((fw_mem_we && (fw_mem_waddr == rs_addr)) ? fw_mem_val :
                      ((fw_wb_we  && (fw_wb_waddr  == rs_addr)) ? fw_wb_val : rf_rdata1)));

    assign val_rt = (rt_addr == 5'd0) ? 32'd0 :
                    ((fw_ex_we  && (fw_ex_waddr  == rt_addr)) ? fw_ex_val :
                     ((fw_mem_we && (fw_mem_waddr == rt_addr)) ? fw_mem_val :
                      ((fw_wb_we  && (fw_wb_waddr  == rt_addr)) ? fw_wb_val : rf_rdata2)));

    // Branch Condition Evaluation
    reg br_taken;
    always @(*) begin
        case (branch_op)
            3'b001:  br_taken = (val_rs == val_rt);                      // BEQ
            3'b010:  br_taken = (val_rs != val_rt);                      // BNE
            3'b011:  br_taken = ($signed(val_rs) <= $signed(32'd0));     // BLEZ
            3'b100:  br_taken = ($signed(val_rs) >  $signed(32'd0));     // BGTZ
            3'b101:  br_taken = ($signed(val_rs) <  $signed(32'd0));     // BLTZ
            3'b110:  br_taken = ($signed(val_rs) >= $signed(32'd0));     // BGEZ
            default: br_taken = 1'b0;
        endcase
    end
    
    wire is_branch = (branch_op != 3'b000);
    wire is_jump   = (jump_op != 2'b00);
    
    assign branch_taken = br_taken & ~stall_req;
    assign jump_taken   = is_jump & ~stall_req;

    // Direct / Register Jump Resolution
    assign jump_target = (jump_op == 2'b01) ? {pc_plus_4[31:28], inst[25:0], 2'b00} : val_rs;

    // Immediate extension
    assign imm_ext = imm_signed ? { {16{inst[15]}}, inst[15:0] } : { 16'd0, inst[15:0] };

    // Branch Target Calculation (Relative to PC+4)
    assign branch_target = pc_plus_4 + { {14{inst[15]}}, inst[15:0], 2'b00 };

    // Register Destination Multiplexer
    assign waddr_out = (reg_dst == 2'b00) ? rt_addr :
                       (reg_dst == 2'b01) ? rd_addr :
                       (reg_dst == 2'b10) ? 5'd31    : 5'd0;

    // Shift Amount Multiplexer
    assign sa_out = use_sa ? inst[10:6] : val_rs[4:0];

    // Precision Hazard Stall Logic: Only stall if the current instruction actually reads the hazard register
    wire [5:0] opcode = inst[31:26];
    wire [5:0] func   = inst[5:0];

    wire reads_rs = (opcode == 6'b000000) ? (func != 6'b000000 && func != 6'b000010 && func != 6'b000011 && func != 6'b010000 && func != 6'b010010) :
                    (opcode != 6'b000010 && opcode != 6'b000011 && opcode != 6'b001111);

    wire reads_rt = (opcode == 6'b000000) ? (func != 6'b001000 && func != 6'b001001 && func != 6'b010000 && func != 6'b010001 && func != 6'b010010 && func != 6'b010011) :
                    (opcode == 6'b101011 || opcode == 6'b101001 || opcode == 6'b101000 || opcode == 6'b000100 || opcode == 6'b000101);

    wire load_use_hazard = (ex_mem_read && (ex_waddr != 5'd0) && 
                           ((reads_rs && (ex_waddr == rs_addr)) || 
                            (reads_rt && (ex_waddr == rt_addr)))) ||
                           (is_branch && mem_mem_read && (fw_mem_waddr != 5'd0) &&
                           ((reads_rs && (fw_mem_waddr == rs_addr)) || 
                            (reads_rt && (fw_mem_waddr == rt_addr))));

    assign stall_req = load_use_hazard;

endmodule
