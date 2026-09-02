// =============================================================================
`include "../include/soc_config.vh"
// File Name: mips_control.v
// Design:    MIPS32 Control Unit & Instruction Decoder
// Author:    Antigravity
// Description:
//   Decodes standard MIPS32 R1 integer instructions.
//   Generates control signals for EX (ALU, MDU), MEM (Loads/Stores),
//   WB (Register Write Source), and Branch/Jump execution.
// =============================================================================

module mips_control (
    input  wire [31:0] inst,         // MIPS32 instruction
    
    // EX Stage Control
    output reg  [4:0]  alu_op,       // ALU operation select (Phase B ISA R2: 5-bit)
    output reg  [3:0]  mdu_op,       // MDU operation select (Phase 4B: 4-bit)
    output reg         mdu_start,    // Start multi-cycle MDU op
    output reg         sel_mdu_out,  // Select MDU read data as EX result
    output reg         alu_src,      // 0: reg rdata2, 1: immediate
    
    // RegFile Write Control
    output reg         reg_write,    // Register file write enable
    output reg  [1:0]  reg_dst,      // 0: rt (inst[20:16]), 1: rd (inst[15:11]), 2: $ra (5'd31)
    
    // Decode Control
    output reg         imm_signed,   // 1: sign extend imm, 0: zero extend imm
    output reg         use_sa,       // 1: use instruction sa (inst[10:6]), 0: use register rs
    
    // MEM Stage Control
    output reg         mem_read,     // Data memory read enable
    output reg         mem_write,    // Data memory write enable
    output reg  [2:0]  mem_op,       // Size control: 000: B, 001: BU, 010: H, 011: HU, 100: W
    // Supported I/D-cache maintenance operations. TagLo/TagHi state is exposed
    // through CP0 for the implemented index-tag slice.
    output reg         cache_op_valid,
    output reg  [4:0]  cache_op,
    
    // WB Stage Control
    output reg  [1:0]  mem_to_reg,   // 0: EX output, 1: MEM load data, 2: PC+8 (link address)
    
    // Branch / Jump Control
    output reg  [2:0]  branch_op,    // 000: None, 001: BEQ, 010: BNE, 011: BLEZ, 100: BGTZ, 101: BLTZ, 110: BGEZ, 111: BC1
    output reg         branch_likely, // Branch-likely; annul the delay slot when not taken
    output reg         fpu_branch_invert,
    output reg  [1:0]  jump_op,      // 00: None, 01: J/JAL (direct), 10: JR/JALR (register)
    
    // Exception
    output reg         illegal_inst, // 1: Unsupported instruction
    
    // Coprocessor 0
    output reg         cp0_we,       // CP0 write enable (MTC0)
    output reg         is_mfc0,      // MFC0 (Phase B.4: for CU0 privilege check)
    output reg         is_eret,      // Exception Return (ERET)
    output reg         is_syscall,   // SYSCALL instruction
    output reg         is_break,     // BREAK instruction
    output reg         is_di,        // DI: disable interrupts, return old Status
    output reg         is_ei,        // EI: enable interrupts, return old Status
    output reg         is_wait,      // WAIT: suspend until an interrupt is accepted
    output reg         is_trap,      // SPECIAL trap instruction
    output reg  [3:0]  trap_op,      // register and immediate trap variants

    // TLB instructions (Phase B.3.b). Encoding:
    //   000 = no TLB op   001 = TLBR    010 = TLBWI
    //   011 = TLBWR       100 = TLBP    others = reserved
    output reg  [2:0]  tlb_op,

    // MOVN/MOVZ (Phase B ISA R2): tell id_stage to gate waddr by val_rt.
    output reg         is_movn,
    output reg         is_movz,

    // COP1 conditional moves use the selected FCSR condition code in this
    // opt-in slice; rt[1] and other reserved fields remain RI.
    output reg         is_movf,
    output reg         is_movt,
    output reg         is_rdpgpr,
    output reg         is_wrpgpr,
    // MIPS32 COP1 condition-code selector.  MOVF/MOVT encode cc in rt[4:2],
    // keep rt[1] reserved, and encode polarity in rt[0].
    output reg  [2:0]  fpu_condition_code
);

    wire [5:0] opcode = inst[31:26];
    wire [4:0] rs     = inst[25:21];
    wire [4:0] rt     = inst[20:16];
    wire [4:0] rd     = inst[15:11];
    wire [4:0] sa     = inst[10:6];
    wire [5:0] func   = inst[5:0];

    always @(*) begin
        // Default assignments to prevent latches
        alu_op       = 5'b00000;
        mdu_op       = 4'b0000;
        mdu_start    = 1'b0;
        sel_mdu_out  = 1'b0;
        alu_src      = 1'b0;
        reg_write    = 1'b0;
        reg_dst      = 2'b00;
        imm_signed   = 1'b1;
        use_sa       = 1'b1;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        mem_op       = 3'b100; // Word by default
        cache_op_valid = 1'b0;
        cache_op     = 5'd0;
        mem_to_reg   = 2'b00;
        branch_op    = 3'b000;
        branch_likely = 1'b0;
        fpu_branch_invert = 1'b0;
        jump_op      = 2'b00;
        illegal_inst = 1'b0;
        cp0_we       = 1'b0;
        is_mfc0      = 1'b0;
        is_eret      = 1'b0;
        is_syscall   = 1'b0;
        is_break     = 1'b0;
        is_di        = 1'b0;
        is_ei        = 1'b0;
        is_wait      = 1'b0;
        is_trap      = 1'b0;
        trap_op      = 4'd0;
        tlb_op       = 3'b000;
        is_movn      = 1'b0;
        is_movz      = 1'b0;
        is_movf      = 1'b0;
        is_movt      = 1'b0;
        is_rdpgpr    = 1'b0;
        is_wrpgpr    = 1'b0;
        fpu_condition_code = 3'd0;

        case (opcode)
            6'b000000: begin // SPECIAL (R-type)
                case (func)
                    6'b100000: begin // ADD
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00000;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100001: begin // ADDU
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00001;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100010: begin // SUB
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00010;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100011: begin // SUBU
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00011;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100100: begin // AND
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00100;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100101: begin // OR
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00101;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100110: begin // XOR
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00110;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b100111: begin // NOR
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b00111;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b001100: begin // SYSCALL
                        is_syscall = 1'b1;
                    end
                    6'b001101: begin // BREAK
                        is_break = 1'b1;
                    end
                    6'b110000: begin // TGE (code is bits [15:6])
                        // Unlike ordinary R-type instructions, rd/sa are the
                        // ten-bit architecturally ignored trap code field.
                        // Linux uses a non-zero code in BUG_ON call sites.
                        is_trap = 1'b1; trap_op = 4'd0;
                    end
                    6'b110001: begin // TGEU (code is bits [15:6])
                        is_trap = 1'b1; trap_op = 4'd1;
                    end
                    6'b110010: begin // TLT (code is bits [15:6])
                        is_trap = 1'b1; trap_op = 4'd2;
                    end
                    6'b110011: begin // TLTU (code is bits [15:6])
                        is_trap = 1'b1; trap_op = 4'd3;
                    end
                    6'b110100: begin // TEQ (code is bits [15:6])
                        is_trap = 1'b1; trap_op = 4'd4;
                    end
                    6'b110110: begin // TNE (code is bits [15:6])
                        is_trap = 1'b1; trap_op = 4'd5;
                    end
                    6'b001111: begin // SYNC
                        // The pipeline is already in-order and the memory
                        // stage blocks until the preceding request completes.
                        // Route SYNC through the private cache barrier opcode.
                        cache_op_valid = 1'b1;
                        cache_op       = 5'b11110;
                    end
                    6'b001010: begin // MOVZ rd, rs, rt (R2)
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b10110;  // OP_MOV_PASS (rd = rs)
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            is_movz   = 1'b1;      // id_stage gates waddr on val_rt==0
                        end
                    end
                    6'b001011: begin // MOVN rd, rs, rt (R2)
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b10110;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            is_movn   = 1'b1;
                        end
                    end
                    6'b000001: begin // MOVF/MOVT rd, rs, cc (R2/COP1)
                        if ((`SOC_FPU_ENABLE == 0) || rt[1] ||
                            inst[10:8] != 3'd0 || inst[7:6] != 2'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            alu_op    = 5'b10110; // pass rs
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            is_movf   = !rt[0];
                            is_movt   = rt[0];
                            fpu_condition_code = rt[4:2];
                        end
                    end
                    6'b000000: begin // SLL
                        // SLL is valid for every rt/rd/shamt combination as
                        // long as rs is zero.  The previous check admitted
                        // only NOP (plus one unrelated special encoding),
                        // causing legal exception handlers such as
                        // `sll k1,k1,2` to take Reserved Instruction.
                        if (rs != 5'd0)
                            illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01000;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b000010: begin // SRL / ROTR (R2: rs[0]=1 → ROTR)
                        if (rs[4:1] != 4'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = (rs[0]) ? 5'b10101 : 5'b01001;  // OP_ROTR : OP_SRL
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b000011: begin // SRA
                        if (rs != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01010;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b000100: begin // SLLV
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01000;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            use_sa    = 1'b0; // shift amount from rs
                        end
                    end
                    6'b000110: begin // SRLV / ROTRV (R2: inst[6]=1 → ROTRV)
                        if (inst[10:7] != 4'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = (inst[6]) ? 5'b10101 : 5'b01001;  // OP_ROTR : OP_SRL
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            use_sa    = 1'b0; // shift amount from rs
                        end
                    end
                    6'b000111: begin // SRAV
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01010;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                            use_sa    = 1'b0; // shift amount from rs
                        end
                    end
                    6'b101010: begin // SLT
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01011;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b101011: begin // SLTU
                        if (sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            alu_op    = 5'b01100;
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    6'b001000: begin // JR / JR.HB (MIPS32 R2 hazard barrier)
                        // This in-order core has no separate fetch hazard
                        // queue, so JR.HB shares JR's architectural path.
                        if (rt == 5'd0 && rd == 5'd0 &&
                            (sa == 5'd0 || sa == 5'd16))
                            jump_op = 2'b10;
                        else
                            illegal_inst = 1'b1;
                    end
                    6'b001001: begin // JALR / JALR.HB
                        if (rt == 5'd0 && (sa == 5'd0 || sa == 5'd16)) begin
                            reg_write  = 1'b1;
                            reg_dst    = 2'b01; // writes link address to rd
                            mem_to_reg = 2'b10;
                            jump_op    = 2'b10;
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    6'b010000: begin // MFHI
                        if (rs != 5'd0 || rt != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            mdu_op      = 4'd4;
                            sel_mdu_out = 1'b1;
                            reg_write   = 1'b1;
                            reg_dst     = 2'b01;
                        end
                    end
                    6'b010010: begin // MFLO
                        if (rs != 5'd0 || rt != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin
                            mdu_op      = 4'd5;
                            sel_mdu_out = 1'b1;
                            reg_write   = 1'b1;
                            reg_dst     = 2'b01;
                        end
                    end
                    6'b010001: begin // MTHI
                        if (rt != 5'd0 || rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd6; mdu_start = 1'b1; end
                    end
                    6'b010011: begin // MTLO
                        if (rt != 5'd0 || rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd7; mdu_start = 1'b1; end
                    end
                    6'b011000: begin // MULT
                        if (rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd0; mdu_start = 1'b1; end
                    end
                    6'b011001: begin // MULTU
                        if (rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd1; mdu_start = 1'b1; end
                    end
                    6'b011010: begin // DIV
                        if (rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd2; mdu_start = 1'b1; end
                    end
                    6'b011011: begin // DIVU
                        if (rd != 5'd0 || sa != 5'd0) illegal_inst = 1'b1;
                        else begin mdu_op = 4'd3; mdu_start = 1'b1; end
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            
            6'b001000: begin // ADDI
                alu_op    = 5'b00000;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001001: begin // ADDIU
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001010: begin // SLTI
                alu_op    = 5'b01011;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001011: begin // SLTIU
                alu_op    = 5'b01100;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001100: begin // ANDI
                alu_op    = 5'b00100;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001101: begin // ORI
                alu_op    = 5'b00101;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001110: begin // XORI
                alu_op    = 5'b00110;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001111: begin // LUI
                alu_op    = 5'b01101;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0;
            end
            6'b100011: begin // LW
                alu_op    = 5'b00001; // address = rs + sign_extend(offset)
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b100;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b110001: begin // LWC1 (single precision, opt-in)
                if (`SOC_FPU_ENABLE == 0) begin
                    illegal_inst = 1'b1;
                end else begin
                    alu_op    = 5'b00001;
                    alu_src   = 1'b1;
                    mem_read  = 1'b1;
                    mem_op    = 3'b100;
                    mem_to_reg = 2'b01;
                    imm_signed = 1'b1;
                end
            end
            6'b110101: begin // LDC1 (double precision, opt-in; even FPR pair)
                if (`SOC_FPU_ENABLE == 0 || rt[0]) begin
                    illegal_inst = 1'b1;
                end else begin
                    alu_op    = 5'b00001;
                    alu_src   = 1'b1;
                    mem_read  = 1'b1;
                    mem_op    = 3'b100;
                    mem_to_reg = 2'b01;
                    imm_signed = 1'b1;
                end
            end
            6'b110000: begin // LL (word)
                alu_op    = 5'b00001;
                alu_src   = 1'b1;
                reg_write = 1'b1;
                reg_dst   = 2'b00;
                mem_read  = 1'b1;
                mem_op    = 3'b111;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100000: begin // LB
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b000;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100100: begin // LBU
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b001;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100001: begin // LH
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b010;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100101: begin // LHU
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b011;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100010: begin // LWL
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b101; // WL
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100110: begin // LWR
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b110; // WR
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b101011: begin // SW
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b100;
                imm_signed = 1'b1;
            end
            6'b111001: begin // SWC1 (single precision, opt-in)
                if (`SOC_FPU_ENABLE == 0) begin
                    illegal_inst = 1'b1;
                end else begin
                    alu_op    = 5'b00001;
                    alu_src   = 1'b1;
                    mem_write = 1'b1;
                    mem_op    = 3'b100;
                    imm_signed = 1'b1;
                end
            end
            6'b111101: begin // SDC1 (double precision, opt-in; even FPR pair)
                if (`SOC_FPU_ENABLE == 0 || rt[0]) begin
                    illegal_inst = 1'b1;
                end else begin
                    alu_op    = 5'b00001;
                    alu_src   = 1'b1;
                    mem_write = 1'b1;
                    mem_op    = 3'b100;
                    imm_signed = 1'b1;
                end
            end
            6'b111000: begin // SC (word)
                alu_op    = 5'b00001;
                alu_src   = 1'b1;
                reg_write = 1'b1;
                reg_dst   = 2'b00;
                mem_write = 1'b1;
                mem_op    = 3'b111;
                imm_signed = 1'b1;
            end
            6'b101000: begin // SB
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b000;
                imm_signed = 1'b1;
            end
            6'b101001: begin // SH
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b010;
                imm_signed = 1'b1;
            end
            6'b101010: begin // SWL
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b101; // WL
                imm_signed = 1'b1;
            end
            6'b101110: begin // SWR
                alu_op    = 5'b00001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b110; // WR
                imm_signed = 1'b1;
            end

            6'b101111: begin // CACHE
                // Functional subset: I/D-cache hit/index maintenance. The
                // pipeline carries the raw op; mips_cpu derives the I-cache
                // sideband for the two architecturally distinct I-cache ops.
                // The effective address is still computed by EX as rs+imm.
                case (rt)
                    5'b00000, // Index_Invalidate_I
                    5'b00100, // Index_Load_Tag_I
                    5'b01000, // Index_Store_Tag_I
                    5'b10000, // Hit_Invalidate_I
                    5'b00001, // Index_Writeback_Invalidate_D
                    5'b00101, // Index_Load_Tag_D
                    5'b01001, // Index_Store_Tag_D
                    5'b10001, // Hit_Invalidate_D
                    5'b10101, // Hit_Writeback_Invalidate_D
                    5'b11101, // Hit_Writeback_D (R2 alias)
                    5'b11001: begin // Hit_Writeback_D (legacy encoding)
                        alu_op         = 5'b00001;
                        alu_src        = 1'b1;
                        cache_op_valid = 1'b1;
                        cache_op       = rt;
                        imm_signed     = 1'b1;
                    end
                    default: illegal_inst = 1'b1;
                endcase
            end

            6'b110011: begin // PREF: implementation-defined cache hint
                // PREF has no architectural result or fault in this slice.
                // Treating the hint as an ordered no-op preserves the guest
                // stream while leaving cache prefetch policy implementation
                // defined.
            end
            
            // Jumps
            6'b000010: begin // J
                jump_op = 2'b01;
            end
            6'b000011: begin // JAL
                reg_write  = 1'b1;
                reg_dst    = 2'b10; // $ra (31)
                mem_to_reg = 2'b10; // PC+8 (link)
                jump_op    = 2'b01;
            end
            
            // Branches
            6'b000100: begin // BEQ
                branch_op  = 3'b001;
                imm_signed = 1'b1;
            end
            6'b010100: begin // BEQL
                branch_op    = 3'b001;
                branch_likely = 1'b1;
                imm_signed   = 1'b1;
            end
            6'b000101: begin // BNE
                branch_op  = 3'b010;
                imm_signed = 1'b1;
            end
            6'b010101: begin // BNEL
                branch_op    = 3'b010;
                branch_likely = 1'b1;
                imm_signed   = 1'b1;
            end
            6'b000110: begin // BLEZ
                if (rt != 5'd0) illegal_inst = 1'b1;
                else begin
                    branch_op  = 3'b011;
                    imm_signed = 1'b1;
                end
            end
            6'b010110: begin // BLEZL
                if (rt != 5'd0) illegal_inst = 1'b1;
                else begin
                    branch_op    = 3'b011;
                    branch_likely = 1'b1;
                    imm_signed   = 1'b1;
                end
            end
            6'b000111: begin // BGTZ
                if (rt != 5'd0) illegal_inst = 1'b1;
                else begin
                    branch_op  = 3'b100;
                    imm_signed = 1'b1;
                end
            end
            6'b010111: begin // BGTZL
                if (rt != 5'd0) illegal_inst = 1'b1;
                else begin
                    branch_op    = 3'b100;
                    branch_likely = 1'b1;
                    imm_signed   = 1'b1;
                end
            end
            6'b000001: begin // REGIMM (BLTZ, BGEZ)
                case (rt)
                    5'b00000: begin // BLTZ
                        branch_op  = 3'b101;
                        imm_signed = 1'b1;
                    end
                    5'b00010: begin // BLTZL
                        branch_op    = 3'b101;
                        branch_likely = 1'b1;
                        imm_signed   = 1'b1;
                    end
                    5'b00001: begin // BGEZ
                        branch_op  = 3'b110;
                        imm_signed = 1'b1;
                    end
                    5'b00011: begin // BGEZL
                        branch_op    = 3'b110;
                        branch_likely = 1'b1;
                        imm_signed   = 1'b1;
                    end
                    5'b10000: begin // BLTZAL
                        branch_op  = 3'b101;
                        imm_signed = 1'b1;
                        reg_write  = 1'b1;
                        reg_dst    = 2'b10; // $ra
                        mem_to_reg = 2'b10; // PC+8
                    end
                    5'b10010: begin // BLTZALL
                        branch_op    = 3'b101;
                        branch_likely = 1'b1;
                        imm_signed   = 1'b1;
                        reg_write    = 1'b1;
                        reg_dst      = 2'b10;
                        mem_to_reg   = 2'b10;
                    end
                    5'b10001: begin // BGEZAL
                        branch_op  = 3'b110;
                        imm_signed = 1'b1;
                        reg_write  = 1'b1;
                        reg_dst    = 2'b10; // $ra
                        mem_to_reg = 2'b10; // PC+8
                    end
                    5'b10011: begin // BGEZALL
                        branch_op    = 3'b110;
                        branch_likely = 1'b1;
                        imm_signed   = 1'b1;
                        reg_write    = 1'b1;
                        reg_dst      = 2'b10;
                        mem_to_reg   = 2'b10;
                    end
                    5'b11111: begin // SYNCI offset(base), REGIMM rt=31
                        alu_op         = 5'b00001;
                        alu_src        = 1'b1;
                        cache_op_valid = 1'b1;
                        cache_op       = 5'b10000; // Hit_Invalidate_I
                        imm_signed     = 1'b1;
                    end
                    5'b01000: begin // TGEI rs, imm
                        is_trap = 1'b1; trap_op = 4'd6; imm_signed = 1'b1;
                    end
                    5'b01001: begin // TGEIU rs, imm
                        is_trap = 1'b1; trap_op = 4'd7; imm_signed = 1'b1;
                    end
                    5'b01010: begin // TLTI rs, imm
                        is_trap = 1'b1; trap_op = 4'd8; imm_signed = 1'b1;
                    end
                    5'b01011: begin // TLTIU rs, imm
                        is_trap = 1'b1; trap_op = 4'd9; imm_signed = 1'b1;
                    end
                    5'b01100: begin // TEQI rs, imm
                        is_trap = 1'b1; trap_op = 4'd10; imm_signed = 1'b1;
                    end
                    5'b01110: begin // TNEI rs, imm
                        is_trap = 1'b1; trap_op = 4'd11; imm_signed = 1'b1;
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            
            6'b011100: begin // SPECIAL2 (MIPS32 R2: MADD/MADDU/MUL/MSUB/MSUBU/CLZ/CLO)
                case (func)
                    6'b000000: begin // MADD rs, rt
                        if (rd != 5'd0 || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            mdu_op    = 4'd8;
                            mdu_start = 1'b1;
                        end
                    end
                    6'b000001: begin // MADDU rs, rt
                        if (rd != 5'd0 || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            mdu_op    = 4'd9;
                            mdu_start = 1'b1;
                        end
                    end
                    6'b000010: begin // MUL rd, rs, rt (R2)
                        if (sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            mdu_op      = 4'd12;
                            mdu_start   = 1'b1;
                            sel_mdu_out = 1'b1;
                            reg_write   = 1'b1;
                            reg_dst     = 2'b01;
                        end
                    end
                    6'b000100: begin // MSUB rs, rt
                        if (rd != 5'd0 || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            mdu_op    = 4'd10;
                            mdu_start = 1'b1;
                        end
                    end
                    6'b000101: begin // MSUBU rs, rt
                        if (rd != 5'd0 || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            mdu_op    = 4'd11;
                            mdu_start = 1'b1;
                        end
                    end
                    6'b100000: begin  // CLZ rd, rs
                        if (rt != rd || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            alu_op    = 5'b10000;  // OP_CLZ
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;     // rd
                        end
                    end
                    6'b100001: begin  // CLO rd, rs
                        if (rt != rd || sa != 5'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            alu_op    = 5'b10001;  // OP_CLO
                            reg_write = 1'b1;
                            reg_dst   = 2'b01;
                        end
                    end
                    default: illegal_inst = 1'b1;
                endcase
            end

            6'b011111: begin // SPECIAL3 (MIPS32 R2: EXT / INS / BSHFL / RDHWR)
                case (func)
                    6'b000000: begin  // EXT rt, rs, pos, size (rd=size-1)
                        if (({1'b0, inst[10:6]} + {1'b0, inst[15:11]}) < 6'd32) begin
                            alu_op    = 5'b10111;
                            reg_write = 1'b1;
                            reg_dst   = 2'b00;
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    6'b000100: begin  // INS rt, rs, pos, size (msbd encoded in rd)
                        if (inst[15:11] >= inst[10:6]) begin
                            alu_op    = 5'b11000;
                            reg_write = 1'b1;
                            reg_dst   = 2'b00;
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    6'b111011: begin  // RDHWR rt, rd (SYNCI_Step=1, Count=2, UserLocal=29)
                        if (rs == 5'b00000 &&
                            ((inst[15:11] == 5'd0) || (inst[15:11] == 5'd1) ||
                             (inst[15:11] == 5'd2) || (inst[15:11] == 5'd3) ||
                             (inst[15:11] == 5'd29))) begin
                            reg_write  = 1'b1;
                            reg_dst    = 2'b00; // rt is the GPR destination
                            mem_to_reg = 2'b11; // CP0-backed hardware register
                            is_mfc0    = 1'b1; // reuse CP0 readback pipeline
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    6'b100000: begin  // BSHFL family — sub-op in sa field (bits 10:6)
                        // BSHFL has rs fixed to zero; the sa field selects the
                        // sub-operation.  Keep all other encodings reserved.
                        // ALIGN is the BSHFL sub-family that deliberately
                        // consumes both rs and rt.  The remaining BSHFL
                        // operations use the architectural fixed rs=0.
                        if (rs != 5'b00000 &&
                            !(inst[10:6] >= 5'b01000 &&
                              inst[10:6] <= 5'b01011)) begin
                            illegal_inst = 1'b1;
                        end else begin
                            case (inst[10:6])
                                5'b01000,  // ALIGN rd, rs, rt, bp=0
                                5'b01001,  // ALIGN rd, rs, rt, bp=1
                                5'b01010,  // ALIGN rd, rs, rt, bp=2
                                5'b01011: begin // ALIGN rd, rs, rt, bp=3
                                    alu_op    = 5'b11010;  // OP_ALIGN
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;       // op_b = rt
                                end
                                5'b00000: begin  // BITSWAP rd, rt (R2)
                                    alu_op    = 5'b11001;
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;
                                end
                                5'b00010: begin  // WSBH rd, rt (R2)
                                    alu_op    = 5'b10100;  // OP_WSBH
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;     // op_b = rt
                                end
                                5'b00110: begin  // WSBW rd, rt (R2)
                                    alu_op    = 5'b11100;  // OP_WSBW
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;     // op_b = rt
                                end
                                5'b10000: begin  // SEB rd, rt
                                    alu_op    = 5'b10010;  // OP_SEB
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;     // op_b = rt
                                end
                                5'b11000: begin  // SEH rd, rt
                                    alu_op    = 5'b10011;  // OP_SEH
                                    reg_write = 1'b1;
                                    reg_dst   = 2'b01;
                                    alu_src   = 1'b0;
                                end
                                default: illegal_inst = 1'b1;
                            endcase
                        end
                    end
                    default: illegal_inst = 1'b1;
                endcase
            end

            6'b010000: begin // COP0
                case (rs)
                    5'b00000: begin // MFC0
                        // Bits [2:0] are the CP0 sub-select. Bits [10:3]
                        // remain reserved for the transfer encoding.
                        if (inst[10:3] != 8'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            reg_write  = 1'b1;
                            reg_dst    = 2'b00; // rt
                            mem_to_reg = 2'b11; // Data from CP0
                            is_mfc0    = 1'b1;
                        end
                    end
                    5'b00100: begin // MTC0
                        // MTC0 has the same reserved [10:3] rule; the low
                        // three bits select the CP0 sub-register.
                        if (inst[10:3] != 8'd0) begin
                            illegal_inst = 1'b1;
                        end else begin
                            cp0_we = 1'b1;
                            reg_dst = 2'b01; // Use rd as CP0 register index
                            alu_op    = 5'b01000; // SLL
                            use_sa = 1'b1;
                            alu_src = 1'b0;   // op_b = rt
                        end
                    end
                    5'b10000: begin // CO — CP0 privileged ops
                        case (func)
                            6'b011000: begin                // ERET
                                // CO fixes rs=5'b10000; remaining fields
                                // between rs and funct are reserved for ERET.
                                if (inst[24:6] == 19'd0)
                                    is_eret = 1'b1;
                                else
                                    illegal_inst = 1'b1;
                            end
                            6'b000001: begin                 // TLBR
                                if (inst[24:6] == 19'd0) tlb_op = 3'b001;
                                else illegal_inst = 1'b1;
                            end
                            6'b000010: begin                 // TLBWI
                                if (inst[24:6] == 19'd0) tlb_op = 3'b010;
                                else illegal_inst = 1'b1;
                            end
                            6'b000110: begin                 // TLBWR
                                if (inst[24:6] == 19'd0) tlb_op = 3'b011;
                                else illegal_inst = 1'b1;
                            end
                            6'b001000: begin                 // TLBP
                                if (inst[24:6] == 19'd0) tlb_op = 3'b100;
                                else illegal_inst = 1'b1;
                            end
                            6'b100000: begin                 // WAIT
                                if (inst[24:6] == 19'd0) is_wait = 1'b1;
                                else illegal_inst = 1'b1;
                            end
                            default:   illegal_inst = 1'b1;
                        endcase
                    end
                    5'b01011: begin // MFMC0: DI/EI (MIPS32 R2)
                        if (inst[15:11] == 5'd12 && inst[10:6] == 5'd0 &&
                            // MIPS32 R2 encodes DI as funct=0 and EI as
                            // funct=0x20.  The latter is bit[5], not funct=1.
                            (func == 6'b000000 || func == 6'b100000)) begin
                            reg_write  = 1'b1;
                            reg_dst    = 2'b00;
                            mem_to_reg = 2'b11;
                            is_mfc0    = 1'b1;
                            is_di      = (func == 6'b000000);
                            is_ei      = (func == 6'b100000);
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    5'b01010: begin // RDPGPR (shadow GPR read)
                        if (`SOC_SRS_ENABLE != 0 && sa == 5'd0 && func == 6'd0) begin
                            reg_write = 1'b1;
                            reg_dst   = 2'b01; // rd receives shadow[rt]
                            alu_op    = 5'b10110; // pass shadow read value
                            is_rdpgpr = 1'b1;
                        end else begin
                            illegal_inst = 1'b1;
                        end
                    end
                    5'b01110: begin // WRPGPR (shadow GPR write)
                        if (`SOC_SRS_ENABLE != 0 && sa == 5'd0 && func == 6'd0)
                            is_wrpgpr = 1'b1;
                        else
                            illegal_inst = 1'b1;
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            6'b010011: begin // COP1X indexed memory and fused arithmetic
                // PREFX is an integer-cache hint in the COP1X encoding space
                // and remains legal when the optional FPU is disabled.
                if (func == 6'h0f) begin
                    // PREFX has no architectural result; model the
                    // implementation-defined prefetch as an ordered no-op.
                    if (sa != 5'd0)
                        illegal_inst = 1'b1;
                end else if (func == 6'h00 || func == 6'h01 ||
                             func == 6'h08 || func == 6'h09) begin
                    // LWXC1/LDXC1 and SWXC1/SDXC1 use GPR[rs]+GPR[rt]
                    // as an indexed address and rd as the FPR selector.
                    // Double transfers require an even FPR pair.
                    if (`SOC_FPU_ENABLE == 0 ||
                        ((func == 6'h01 || func == 6'h09) && rd[0])) begin
                        illegal_inst = 1'b1;
                    end else begin
                        alu_op    = 5'b00001;
                        alu_src   = 1'b0;
                        mem_op    = 3'b100;
                        imm_signed = 1'b1;
                        if (func == 6'h00 || func == 6'h01) begin
                            mem_read  = 1'b1;
                            mem_to_reg = 2'b01;
                        end else begin
                            mem_write = 1'b1;
                        end
                    end
                end else if (`SOC_FPU_ENABLE == 0) begin
                    illegal_inst = 1'b1;
                end else begin
                    case (func)
                        6'h20, 6'h21, 6'h28, 6'h29,
                        6'h30, 6'h31, 6'h38, 6'h39: begin
                            // COP1X uses rs=fr, rt=ft, rd=fs, sa=fd.
                            // Odd function encodings are the D forms, where
                            // every selector names the first word of a pair.
                            if (func[0] &&
                                (rs[0] || rt[0] || rd[0] || sa[0]))
                                illegal_inst = 1'b1;
                        end
                        default: illegal_inst = 1'b1;
                    endcase
                end
            end

            6'b010001: begin // COP1 single/double development slice
                if (`SOC_FPU_ENABLE == 0) begin
                    illegal_inst = 1'b1;
                end else begin
                    case (rs)
                        5'b01000: begin // BC1F/BC1T and branch-likely forms
                            if (!(rt == 5'd0 || rt == 5'd1 ||
                                  rt == 5'd2 || rt == 5'd3)) begin
                                illegal_inst = 1'b1;
                            end else begin
                                branch_op = 3'b111;
                                branch_likely = rt[1];
                                fpu_branch_invert = ~rt[0];
                                fpu_condition_code = inst[20:18];
                            end
                        end
                        5'b00000, 5'b00010, 5'b00100, 5'b00110: begin
                            // MFC1/CFC1/MTC1/CTC1 side effects are committed
                            // by the opt-in CP1 state block in mips_cpu.
                            // The low eleven bits are reserved for transfers;
                            // CFC1/CTC1 expose FCSR only (fs=$31).
                            if (inst[10:0] != 11'd0 ||
                                ((rs == 5'b00010 || rs == 5'b00110) &&
                                 inst[15:11] != 5'd31))
                                illegal_inst = 1'b1;
                        end
                        5'b10000, 5'b10001, 5'b10100: begin
                            case (func)
                                6'h00, 6'h01, 6'h02, 6'h03, 6'h04,
                                6'h05, 6'h06, 6'h07,
                                6'h0c, 6'h0d, 6'h0e, 6'h0f,
                                6'h11,
                                6'h15, 6'h16,
                                6'h12, 6'h13,
                                6'h20, 6'h21, 6'h24,
                                6'h30, 6'h31, 6'h32, 6'h33,
                                6'h34, 6'h35, 6'h36, 6'h37,
                                6'h38, 6'h39, 6'h3a, 6'h3b,
                                6'h3c, 6'h3d, 6'h3e, 6'h3f: begin end
                                default: illegal_inst = 1'b1;
                            endcase
                            // fmt=D uses an even-numbered register pair for
                            // fd/fs/ft.  Reject odd or malformed encodings at
                            // decode so no partial FPR state can commit.
                            // MOVZ/MOVN use the rt field as an integer GPR
                            // condition, not as the D-format ft FPR.  Only
                            // ordinary D operations require all three FPR
                            // selectors to be even.
                            if ((rs == 5'b10001) &&
                                (inst[6] || inst[11] ||
                                 ((func == 6'h11) ? inst[17] :
                                  ((func != 6'h12 && func != 6'h13) &&
                                   inst[16]))))
                                illegal_inst = 1'b1;
                            if ((rs == 5'b10100 &&
                                 func != 6'h20 && func != 6'h21))
                                illegal_inst = 1'b1;
                            if ((rs == 5'b10000 && func == 6'h20) ||
                                (rs == 5'b10001 && func == 6'h21))
                                illegal_inst = 1'b1;
                        end
                        default: illegal_inst = 1'b1;
                    endcase
                end
            end
            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule
