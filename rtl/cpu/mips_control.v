// =============================================================================
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
    // Supported D-cache maintenance operations. TagLo/TagHi state is exposed
    // through CP0 for the implemented index-tag slice.
    output reg         cache_op_valid,
    output reg  [4:0]  cache_op,
    
    // WB Stage Control
    output reg  [1:0]  mem_to_reg,   // 0: EX output, 1: MEM load data, 2: PC+8 (link address)
    
    // Branch / Jump Control
    output reg  [2:0]  branch_op,    // 000: None, 001: BEQ, 010: BNE, 011: BLEZ, 100: BGTZ, 101: BLTZ, 110: BGEZ
    output reg  [1:0]  jump_op,      // 00: None, 01: J/JAL (direct), 10: JR/JALR (register)
    
    // Exception
    output reg         illegal_inst, // 1: Unsupported instruction
    
    // Coprocessor 0
    output reg         cp0_we,       // CP0 write enable (MTC0)
    output reg         is_mfc0,      // MFC0 (Phase B.4: for CU0 privilege check)
    output reg         is_eret,      // Exception Return (ERET)
    output reg         is_syscall,   // SYSCALL instruction

    // TLB instructions (Phase B.3.b). Encoding:
    //   000 = no TLB op   001 = TLBR    010 = TLBWI
    //   011 = TLBWR       100 = TLBP    others = reserved
    output reg  [2:0]  tlb_op,

    // MOVN/MOVZ (Phase B ISA R2): tell id_stage to gate waddr by val_rt.
    output reg         is_movn,
    output reg         is_movz
);

    wire [5:0] opcode = inst[31:26];
    wire [4:0] rs     = inst[25:21];
    wire [4:0] rt     = inst[20:16];
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
        jump_op      = 2'b00;
        illegal_inst = 1'b0;
        cp0_we       = 1'b0;
        is_mfc0      = 1'b0;
        is_eret      = 1'b0;
        is_syscall   = 1'b0;
        tlb_op       = 3'b000;
        is_movn      = 1'b0;
        is_movz      = 1'b0;

        case (opcode)
            6'b000000: begin // SPECIAL (R-type)
                case (func)
                    6'b100000: begin // ADD
                        alu_op    = 5'b00000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100001: begin // ADDU
                        alu_op    = 5'b00001;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100010: begin // SUB
                        alu_op    = 5'b00010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100011: begin // SUBU
                        alu_op    = 5'b00011;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100100: begin // AND
                        alu_op    = 5'b00100;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100101: begin // OR
                        alu_op    = 5'b00101;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100110: begin // XOR
                        alu_op    = 5'b00110;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100111: begin // NOR
                        alu_op    = 5'b00111;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b001100: begin // SYSCALL
                        is_syscall = 1'b1;
                    end
                    6'b001111: begin // SYNC
                        // The pipeline is already in-order and the memory
                        // stage blocks until the preceding request completes.
                        // Recognize SYNC as an ordered no-op rather than RI.
                    end
                    6'b001010: begin // MOVZ rd, rs, rt (R2)
                        alu_op    = 5'b10110;  // OP_MOV_PASS (rd = rs)
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        is_movz   = 1'b1;      // id_stage gates waddr on val_rt==0
                    end
                    6'b001011: begin // MOVN rd, rs, rt (R2)
                        alu_op    = 5'b10110;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        is_movn   = 1'b1;
                    end
                    6'b000000: begin // SLL
                        alu_op    = 5'b01000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000010: begin // SRL / ROTR (R2: rs[0]=1 → ROTR)
                        alu_op    = (rs[0]) ? 5'b10101 : 5'b01001;  // OP_ROTR : OP_SRL
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000011: begin // SRA
                        alu_op    = 5'b01010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000100: begin // SLLV
                        alu_op    = 5'b01000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b000110: begin // SRLV / ROTRV (R2: inst[6]=1 → ROTRV)
                        alu_op    = (inst[6]) ? 5'b10101 : 5'b01001;  // OP_ROTR : OP_SRL
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b000111: begin // SRAV
                        alu_op    = 5'b01010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b101010: begin // SLT
                        alu_op    = 5'b01011;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b101011: begin // SLTU
                        alu_op    = 5'b01100;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b001000: begin // JR
                        jump_op   = 2'b10;
                    end
                    6'b001001: begin // JALR
                        reg_write  = 1'b1;
                        reg_dst    = 2'b01; // writes link address to rd
                        mem_to_reg = 2'b10;
                        jump_op    = 2'b10;
                    end
                    6'b010000: begin // MFHI
                        mdu_op      = 4'd4;
                        sel_mdu_out = 1'b1;
                        reg_write   = 1'b1;
                        reg_dst     = 2'b01;
                    end
                    6'b010010: begin // MFLO
                        mdu_op      = 4'd5;
                        sel_mdu_out = 1'b1;
                        reg_write   = 1'b1;
                        reg_dst     = 2'b01;
                    end
                    6'b010001: begin // MTHI
                        mdu_op    = 4'd6;
                        mdu_start = 1'b1;
                    end
                    6'b010011: begin // MTLO
                        mdu_op    = 4'd7;
                        mdu_start = 1'b1;
                    end
                    6'b011000: begin // MULT
                        mdu_op    = 4'd0;
                        mdu_start = 1'b1;
                    end
                    6'b011001: begin // MULTU
                        mdu_op    = 4'd1;
                        mdu_start = 1'b1;
                    end
                    6'b011010: begin // DIV
                        mdu_op    = 4'd2;
                        mdu_start = 1'b1;
                    end
                    6'b011011: begin // DIVU
                        mdu_op    = 4'd3;
                        mdu_start = 1'b1;
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
                // First functional subset: D-cache hit/index maintenance.
                // The effective address is still computed by EX as rs+imm.
                case (rt)
                    5'b00001, // Index_Writeback_Invalidate_D
                    5'b00101, // Index_Load_Tag_D
                    5'b01001, // Index_Store_Tag_D
                    5'b10101, // Hit_Invalidate_D
                    5'b11001, // Hit_Writeback_Invalidate_D
                    5'b11101: begin // Hit_Writeback_D
                        alu_op         = 5'b00001;
                        alu_src        = 1'b1;
                        cache_op_valid = 1'b1;
                        cache_op       = rt;
                        imm_signed     = 1'b1;
                    end
                    default: illegal_inst = 1'b1;
                endcase
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
            6'b000101: begin // BNE
                branch_op  = 3'b010;
                imm_signed = 1'b1;
            end
            6'b000110: begin // BLEZ
                branch_op  = 3'b011;
                imm_signed = 1'b1;
            end
            6'b000111: begin // BGTZ
                branch_op  = 3'b100;
                imm_signed = 1'b1;
            end
            6'b000001: begin // REGIMM (BLTZ, BGEZ)
                case (rt)
                    5'b00000: begin // BLTZ
                        branch_op  = 3'b101;
                        imm_signed = 1'b1;
                    end
                    5'b00001: begin // BGEZ
                        branch_op  = 3'b110;
                        imm_signed = 1'b1;
                    end
                    5'b10000: begin // BLTZAL
                        branch_op  = 3'b101;
                        imm_signed = 1'b1;
                        reg_write  = 1'b1;
                        reg_dst    = 2'b10; // $ra
                        mem_to_reg = 2'b10; // PC+8
                    end
                    5'b10001: begin // BGEZAL
                        branch_op  = 3'b110;
                        imm_signed = 1'b1;
                        reg_write  = 1'b1;
                        reg_dst    = 2'b10; // $ra
                        mem_to_reg = 2'b10; // PC+8
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            
            6'b011100: begin // SPECIAL2 (MIPS32 R2: MADD/MADDU/MUL/MSUB/MSUBU/CLZ/CLO)
                case (func)
                    6'b000000: begin // MADD rs, rt
                        mdu_op    = 4'd8;
                        mdu_start = 1'b1;
                    end
                    6'b000001: begin // MADDU rs, rt
                        mdu_op    = 4'd9;
                        mdu_start = 1'b1;
                    end
                    6'b000010: begin // MUL rd, rs, rt (R2)
                        mdu_op      = 4'd12;
                        mdu_start   = 1'b1;
                        sel_mdu_out = 1'b1;
                        reg_write   = 1'b1;
                        reg_dst     = 2'b01;
                    end
                    6'b000100: begin // MSUB rs, rt
                        mdu_op    = 4'd10;
                        mdu_start = 1'b1;
                    end
                    6'b000101: begin // MSUBU rs, rt
                        mdu_op    = 4'd11;
                        mdu_start = 1'b1;
                    end
                    6'b100000: begin  // CLZ rd, rs
                        alu_op    = 5'b10000;  // OP_CLZ
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;     // rd
                        // Standard MIPS32 requires rd==rt but we ignore that
                        // constraint here; ALU uses op_a (=rs) only.
                    end
                    6'b100001: begin  // CLO rd, rs
                        alu_op    = 5'b10001;  // OP_CLO
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    default: illegal_inst = 1'b1;
                endcase
            end

            6'b011111: begin // SPECIAL3 (Phase B ISA R2: SEB / SEH via BSHFL func 0x20)
                case (func)
                    6'b100000: begin  // BSHFL family — sub-op in sa field (bits 10:6)
                        case (inst[10:6])
                            5'b00010: begin  // WSBH rd, rt (R2)
                                alu_op    = 5'b10100;  // OP_WSBH
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
                    default: illegal_inst = 1'b1;
                endcase
            end

            6'b010000: begin // COP0
                case (rs)
                    5'b00000: begin // MFC0
                        reg_write  = 1'b1;
                        reg_dst    = 2'b00; // rt
                        mem_to_reg = 2'b11; // Data from CP0
                        is_mfc0    = 1'b1;
                    end
                    5'b00100: begin // MTC0
                        cp0_we = 1'b1;
                        reg_dst = 2'b01; // Use rd as CP0 register index
                        alu_op    = 5'b01000; // SLL
                        use_sa = 1'b1;    // use sa (which is 0 for MTC0 because bits 10:6 are 0)
                        alu_src = 1'b0;   // op_b = rt
                    end
                    5'b10000: begin // CO — CP0 privileged ops
                        case (func)
                            6'b011000: is_eret = 1'b1;      // ERET
                            6'b000001: tlb_op  = 3'b001;    // TLBR
                            6'b000010: tlb_op  = 3'b010;    // TLBWI
                            6'b000110: tlb_op  = 3'b011;    // TLBWR
                            6'b001000: tlb_op  = 3'b100;    // TLBP
                            default:   illegal_inst = 1'b1;
                        endcase
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule
