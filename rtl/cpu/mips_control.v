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
    output reg  [3:0]  alu_op,       // ALU operation select
    output reg  [2:0]  mdu_op,       // MDU operation select
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
    
    // WB Stage Control
    output reg  [1:0]  mem_to_reg,   // 0: EX output, 1: MEM load data, 2: PC+8 (link address)
    
    // Branch / Jump Control
    output reg  [2:0]  branch_op,    // 000: None, 001: BEQ, 010: BNE, 011: BLEZ, 100: BGTZ, 101: BLTZ, 110: BGEZ
    output reg  [1:0]  jump_op,      // 00: None, 01: J/JAL (direct), 10: JR/JALR (register)
    
    // Exception
    output reg         illegal_inst, // 1: Unsupported instruction
    
    // Coprocessor 0
    output reg         cp0_we,       // CP0 write enable (MTC0)
    output reg         is_eret,      // Exception Return (ERET)
    output reg         is_syscall    // SYSCALL instruction
);

    wire [5:0] opcode = inst[31:26];
    wire [4:0] rs     = inst[25:21];
    wire [4:0] rt     = inst[20:16];
    wire [5:0] func   = inst[5:0];

    always @(*) begin
        // Default assignments to prevent latches
        alu_op       = 4'b0000;
        mdu_op       = 3'b000;
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
        mem_to_reg   = 2'b00;
        branch_op    = 3'b000;
        jump_op      = 2'b00;
        illegal_inst = 1'b0;
        cp0_we       = 1'b0;
        is_eret      = 1'b0;
        is_syscall   = 1'b0;

        case (opcode)
            6'b000000: begin // SPECIAL (R-type)
                case (func)
                    6'b100000: begin // ADD
                        alu_op    = 4'b0000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100001: begin // ADDU
                        alu_op    = 4'b0001;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100010: begin // SUB
                        alu_op    = 4'b0010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100011: begin // SUBU
                        alu_op    = 4'b0011;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100100: begin // AND
                        alu_op    = 4'b0100;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100101: begin // OR
                        alu_op    = 4'b0101;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100110: begin // XOR
                        alu_op    = 4'b0110;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b100111: begin // NOR
                        alu_op    = 4'b0111;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b001100: begin // SYSCALL
                        is_syscall = 1'b1;
                    end
                    6'b000000: begin // SLL
                        alu_op    = 4'b1000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000010: begin // SRL
                        alu_op    = 4'b1001;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000011: begin // SRA
                        alu_op    = 4'b1010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b000100: begin // SLLV
                        alu_op    = 4'b1000;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b000110: begin // SRLV
                        alu_op    = 4'b1001;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b000111: begin // SRAV
                        alu_op    = 4'b1010;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                        use_sa    = 1'b0; // shift amount from rs
                    end
                    6'b101010: begin // SLT
                        alu_op    = 4'b1011;
                        reg_write = 1'b1;
                        reg_dst   = 2'b01;
                    end
                    6'b101011: begin // SLTU
                        alu_op    = 4'b1100;
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
                        mdu_op      = 3'b110;
                        sel_mdu_out = 1'b1;
                        reg_write   = 1'b1;
                        reg_dst     = 2'b01;
                    end
                    6'b010010: begin // MFLO
                        mdu_op      = 3'b111;
                        sel_mdu_out = 1'b1;
                        reg_write   = 1'b1;
                        reg_dst     = 2'b01;
                    end
                    6'b010001: begin // MTHI
                        mdu_op    = 3'b100;
                    end
                    6'b010011: begin // MTLO
                        mdu_op    = 3'b101;
                    end
                    6'b011000: begin // MULT
                        mdu_op    = 3'b000;
                        mdu_start = 1'b1;
                    end
                    6'b011001: begin // MULTU
                        mdu_op    = 3'b001;
                        mdu_start = 1'b1;
                    end
                    6'b011010: begin // DIV
                        mdu_op    = 3'b010;
                        mdu_start = 1'b1;
                    end
                    6'b011011: begin // DIVU
                        mdu_op    = 3'b011;
                        mdu_start = 1'b1;
                    end
                    default: begin
                        illegal_inst = 1'b1;
                    end
                endcase
            end
            
            6'b001000: begin // ADDI
                alu_op     = 4'b0000;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001001: begin // ADDIU
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001010: begin // SLTI
                alu_op     = 4'b1011;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001011: begin // SLTIU
                alu_op     = 4'b1100;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b1;
            end
            6'b001100: begin // ANDI
                alu_op     = 4'b0100;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001101: begin // ORI
                alu_op     = 4'b0101;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001110: begin // XORI
                alu_op     = 4'b0110;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0; // Zero extended
            end
            6'b001111: begin // LUI
                alu_op     = 4'b1101;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                imm_signed = 1'b0;
            end
            6'b100011: begin // LW
                alu_op     = 4'b0001; // address = rs + sign_extend(offset)
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b100;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100000: begin // LB
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b000;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100100: begin // LBU
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b001;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100001: begin // LH
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b010;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100101: begin // LHU
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b011;
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100010: begin // LWL
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b101; // WL
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b100110: begin // LWR
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                reg_write  = 1'b1;
                reg_dst    = 2'b00;
                mem_read   = 1'b1;
                mem_op     = 3'b110; // WR
                mem_to_reg = 2'b01;
                imm_signed = 1'b1;
            end
            6'b101011: begin // SW
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b100;
                imm_signed = 1'b1;
            end
            6'b101000: begin // SB
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b000;
                imm_signed = 1'b1;
            end
            6'b101001: begin // SH
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b010;
                imm_signed = 1'b1;
            end
            6'b101010: begin // SWL
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b101; // WL
                imm_signed = 1'b1;
            end
            6'b101110: begin // SWR
                alu_op     = 4'b0001;
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                mem_op     = 3'b110; // WR
                imm_signed = 1'b1;
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
            
            6'b010000: begin // COP0
                case (rs)
                    5'b00000: begin // MFC0
                        reg_write  = 1'b1;
                        reg_dst    = 2'b00; // rt
                        mem_to_reg = 2'b11; // Data from CP0
                    end
                    5'b00100: begin // MTC0
                        cp0_we = 1'b1;
                        reg_dst = 2'b01; // Use rd as CP0 register index
                        alu_op = 4'b1000; // SLL
                        use_sa = 1'b1;    // use sa (which is 0 for MTC0 because bits 10:6 are 0)
                        alu_src = 1'b0;   // op_b = rt
                    end
                    5'b10000: begin // CO
                        if (func == 6'b011000) begin // ERET
                            is_eret = 1'b1;
                        end else begin
                            illegal_inst = 1'b1;
                        end
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
