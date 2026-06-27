// =============================================================================
// File Name: mips_id_stage_pkg.sv
// Design:    MIPS32 ID Stage UVM Verification Package
// Author:    Antigravity
// Description:
//   Contains the complete UVM environment for block-level verification
//   of the MIPS32 Instruction Decode stage wrapper.
// =============================================================================

package mips_id_stage_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // =========================================================================
    // 1. Transaction Item
    // =========================================================================
    class mips_id_stage_item extends uvm_sequence_item;
        // Inputs to DUT
        bit [31:0]     inst;         // Controlled by custom randomize function
        rand bit [31:0] pc_plus_4;
        rand bit [4:0]  rf_waddr;
        rand bit [31:0] rf_wdata;
        rand bit        rf_we;
        
        rand bit        fw_ex_we;
        rand bit [4:0]  fw_ex_waddr;
        rand bit [31:0] fw_ex_val;
        
        rand bit        fw_mem_we;
        rand bit [4:0]  fw_mem_waddr;
        rand bit [31:0] fw_mem_val;
        
        rand bit        fw_wb_we;
        rand bit [4:0]  fw_wb_waddr;
        rand bit [31:0] fw_wb_val;
        
        rand bit        ex_mem_read;
        rand bit [4:0]  ex_waddr;

        // Outputs from DUT
        bit        stall_req;
        bit        branch_taken;
        bit [31:0] branch_target;
        bit        jump_taken;
        bit [31:0] jump_target;
        
        bit [31:0] val_rs;
        bit [31:0] val_rt;
        bit [31:0] imm_ext;
        bit [4:0]  waddr_out;
        bit [4:0]  sa_out;
        bit [4:0]  rs_addr;
        bit [4:0]  rt_addr;
        bit [4:0]  rd_addr;
        
        bit [3:0]  alu_op;
        bit [2:0]  mdu_op;
        bit        mdu_start;
        bit        sel_mdu_out;
        bit        alu_src;
        bit        reg_write;
        bit        mem_read;
        bit        mem_write;
        bit [2:0]  mem_op;
        bit [1:0]  mem_to_reg;
        bit        illegal_inst;

        `uvm_object_utils_begin(mips_id_stage_item)
            `uvm_field_int(inst, UVM_ALL_ON)
            `uvm_field_int(pc_plus_4, UVM_ALL_ON)
            `uvm_field_int(rf_waddr, UVM_ALL_ON)
            `uvm_field_int(rf_wdata, UVM_ALL_ON)
            `uvm_field_int(rf_we, UVM_ALL_ON)
            `uvm_field_int(fw_ex_we, UVM_ALL_ON)
            `uvm_field_int(fw_ex_waddr, UVM_ALL_ON)
            `uvm_field_int(fw_ex_val, UVM_ALL_ON)
            `uvm_field_int(fw_mem_we, UVM_ALL_ON)
            `uvm_field_int(fw_mem_waddr, UVM_ALL_ON)
            `uvm_field_int(fw_mem_val, UVM_ALL_ON)
            `uvm_field_int(fw_wb_we, UVM_ALL_ON)
            `uvm_field_int(fw_wb_waddr, UVM_ALL_ON)
            `uvm_field_int(fw_wb_val, UVM_ALL_ON)
            `uvm_field_int(ex_mem_read, UVM_ALL_ON)
            `uvm_field_int(ex_waddr, UVM_ALL_ON)
            `uvm_field_int(stall_req, UVM_ALL_ON)
            `uvm_field_int(branch_taken, UVM_ALL_ON)
            `uvm_field_int(branch_target, UVM_ALL_ON)
            `uvm_field_int(jump_taken, UVM_ALL_ON)
            `uvm_field_int(jump_target, UVM_ALL_ON)
            `uvm_field_int(val_rs, UVM_ALL_ON)
            `uvm_field_int(val_rt, UVM_ALL_ON)
            `uvm_field_int(imm_ext, UVM_ALL_ON)
            `uvm_field_int(waddr_out, UVM_ALL_ON)
            `uvm_field_int(sa_out, UVM_ALL_ON)
            `uvm_field_int(rs_addr, UVM_ALL_ON)
            `uvm_field_int(rt_addr, UVM_ALL_ON)
            `uvm_field_int(rd_addr, UVM_ALL_ON)
            `uvm_field_int(alu_op, UVM_ALL_ON)
            `uvm_field_int(mdu_op, UVM_ALL_ON)
            `uvm_field_int(mdu_start, UVM_ALL_ON)
            `uvm_field_int(sel_mdu_out, UVM_ALL_ON)
            `uvm_field_int(alu_src, UVM_ALL_ON)
            `uvm_field_int(reg_write, UVM_ALL_ON)
            `uvm_field_int(mem_read, UVM_ALL_ON)
            `uvm_field_int(mem_write, UVM_ALL_ON)
            `uvm_field_int(mem_op, UVM_ALL_ON)
            `uvm_field_int(mem_to_reg, UVM_ALL_ON)
            `uvm_field_int(illegal_inst, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "mips_id_stage_item");
            super.new(name);
        endfunction

        // Generates valid instruction codes for supported MIPS32 R1 core subset
        function void post_randomize();
            int idx = $urandom_range(0, 49);
            bit [5:0] opcode;
            bit [5:0] func;
            bit [4:0] rs = $urandom_range(0, 31);
            bit [4:0] rt = $urandom_range(0, 31);
            bit [4:0] rd = $urandom_range(0, 31);
            bit [4:0] sa = $urandom_range(0, 31);
            bit [15:0] imm = $urandom();
            bit [25:0] target = $urandom();
            
            case (idx)
                // SPECIAL (R-type)
                0:  begin opcode = 6'b000000; func = 6'b100000; end // ADD
                1:  begin opcode = 6'b000000; func = 6'b100001; end // ADDU
                2:  begin opcode = 6'b000000; func = 6'b100010; end // SUB
                3:  begin opcode = 6'b000000; func = 6'b100011; end // SUBU
                4:  begin opcode = 6'b000000; func = 6'b100100; end // AND
                5:  begin opcode = 6'b000000; func = 6'b100101; end // OR
                6:  begin opcode = 6'b000000; func = 6'b100110; end // XOR
                7:  begin opcode = 6'b000000; func = 6'b100111; end // NOR
                8:  begin opcode = 6'b000000; func = 6'b000000; end // SLL
                9:  begin opcode = 6'b000000; func = 6'b000010; end // SRL
                10: begin opcode = 6'b000000; func = 6'b000011; end // SRA
                11: begin opcode = 6'b000000; func = 6'b000100; end // SLLV
                12: begin opcode = 6'b000000; func = 6'b000110; end // SRLV
                13: begin opcode = 6'b000000; func = 6'b000111; end // SRAV
                14: begin opcode = 6'b000000; func = 6'b101010; end // SLT
                15: begin opcode = 6'b000000; func = 6'b101011; end // SLTU
                16: begin opcode = 6'b000000; func = 6'b001000; end // JR
                17: begin opcode = 6'b000000; func = 6'b001001; end // JALR
                18: begin opcode = 6'b000000; func = 6'b010000; end // MFHI
                19: begin opcode = 6'b000000; func = 6'b010010; end // MFLO
                20: begin opcode = 6'b000000; func = 6'b010001; end // MTHI
                21: begin opcode = 6'b000000; func = 6'b010011; end // MTLO
                22: begin opcode = 6'b000000; func = 6'b011000; end // MULT
                23: begin opcode = 6'b000000; func = 6'b011001; end // MULTU
                24: begin opcode = 6'b000000; func = 6'b011010; end // DIV
                25: begin opcode = 6'b000000; func = 6'b011011; end // DIVU
                
                // I-type
                26: begin opcode = 6'b001000; end // ADDI
                27: begin opcode = 6'b001001; end // ADDIU
                28: begin opcode = 6'b001010; end // SLTI
                29: begin opcode = 6'b001011; end // SLTIU
                30: begin opcode = 6'b001100; end // ANDI
                31: begin opcode = 6'b001101; end // ORI
                32: begin opcode = 6'b001110; end // XORI
                33: begin opcode = 6'b001111; end // LUI
                34: begin opcode = 6'b100011; end // LW
                35: begin opcode = 6'b100000; end // LB
                36: begin opcode = 6'b100100; end // LBU
                37: begin opcode = 6'b100001; end // LH
                38: begin opcode = 6'b100101; end // LHU
                39: begin opcode = 6'b101011; end // SW
                40: begin opcode = 6'b101000; end // SB
                41: begin opcode = 6'b101001; end // SH
                
                // J-type / Branches
                42: begin opcode = 6'b000010; end // J
                43: begin opcode = 6'b000011; end // JAL
                44: begin opcode = 6'b000100; end // BEQ
                45: begin opcode = 6'b000101; end // BNE
                46: begin opcode = 6'b000110; rt = 5'b00000; end // BLEZ
                47: begin opcode = 6'b000111; rt = 5'b00000; end // BGTZ
                48: begin opcode = 6'b000001; rt = 5'b00000; end // BLTZ
                49: begin opcode = 6'b000001; rt = 5'b00001; end // BGEZ
            endcase
            
            if (opcode == 6'b000000) begin
                inst = {opcode, rs, rt, rd, sa, func};
            end else if (opcode == 6'b000010 || opcode == 6'b000011) begin
                inst = {opcode, target};
            end else begin
                inst = {opcode, rs, rt, imm};
            end
        endfunction
    endclass

    // =========================================================================
    // 2. Driver
    // =========================================================================
    class mips_id_stage_driver extends uvm_driver #(mips_id_stage_item);
        `uvm_component_utils(mips_id_stage_driver)
        virtual mips_id_stage_if vif;

        function new(string name = "mips_id_stage_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_id_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("DRV", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            // Reset state
            vif.drv_cb.inst         <= 32'h0000_0000;
            vif.drv_cb.pc_plus_4    <= 32'h0000_0000;
            vif.drv_cb.rf_waddr     <= 5'd0;
            vif.drv_cb.rf_wdata     <= 32'd0;
            vif.drv_cb.rf_we        <= 1'b0;
            vif.drv_cb.fw_ex_we     <= 1'b0;
            vif.drv_cb.fw_ex_waddr  <= 5'd0;
            vif.drv_cb.fw_ex_val    <= 32'd0;
            vif.drv_cb.fw_mem_we    <= 1'b0;
            vif.drv_cb.fw_mem_waddr <= 5'd0;
            vif.drv_cb.fw_mem_val   <= 32'd0;
            vif.drv_cb.fw_wb_we     <= 1'b0;
            vif.drv_cb.fw_wb_waddr  <= 5'd0;
            vif.drv_cb.fw_wb_val    <= 32'd0;
            vif.drv_cb.ex_mem_read  <= 1'b0;
            vif.drv_cb.ex_waddr     <= 5'd0;
            
            @(posedge vif.rst_n);
            
            forever begin
                seq_item_port.get_next_item(req);
                drive_item(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_item(mips_id_stage_item item);
            @(vif.drv_cb);
            vif.drv_cb.inst         <= item.inst;
            vif.drv_cb.pc_plus_4    <= item.pc_plus_4;
            vif.drv_cb.rf_waddr     <= item.rf_waddr;
            vif.drv_cb.rf_wdata     <= item.rf_wdata;
            vif.drv_cb.rf_we        <= item.rf_we;
            vif.drv_cb.fw_ex_we     <= item.fw_ex_we;
            vif.drv_cb.fw_ex_waddr  <= item.fw_ex_waddr;
            vif.drv_cb.fw_ex_val    <= item.fw_ex_val;
            vif.drv_cb.fw_mem_we    <= item.fw_mem_we;
            vif.drv_cb.fw_mem_waddr <= item.fw_mem_waddr;
            vif.drv_cb.fw_mem_val   <= item.fw_mem_val;
            vif.drv_cb.fw_wb_we     <= item.fw_wb_we;
            vif.drv_cb.fw_wb_waddr  <= item.fw_wb_waddr;
            vif.drv_cb.fw_wb_val    <= item.fw_wb_val;
            vif.drv_cb.ex_mem_read  <= item.ex_mem_read;
            vif.drv_cb.ex_waddr     <= item.ex_waddr;
        endtask
    endclass

    // =========================================================================
    // 3. Monitor
    // =========================================================================
    class mips_id_stage_monitor extends uvm_monitor;
        `uvm_component_utils(mips_id_stage_monitor)
        virtual mips_id_stage_if vif;
        uvm_analysis_port #(mips_id_stage_item) ap;

        function new(string name = "mips_id_stage_monitor", uvm_component parent = null);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_id_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("MON", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            mips_id_stage_item item;
            @(posedge vif.rst_n);
            forever begin
                @(vif.mon_cb);
                item = mips_id_stage_item::type_id::create("item");
                item.inst         = vif.mon_cb.inst;
                item.pc_plus_4    = vif.mon_cb.pc_plus_4;
                item.rf_waddr     = vif.mon_cb.rf_waddr;
                item.rf_wdata     = vif.mon_cb.rf_wdata;
                item.rf_we        = vif.mon_cb.rf_we;
                item.fw_ex_we     = vif.mon_cb.fw_ex_we;
                item.fw_ex_waddr  = vif.mon_cb.fw_ex_waddr;
                item.fw_ex_val    = vif.mon_cb.fw_ex_val;
                item.fw_mem_we    = vif.mon_cb.fw_mem_we;
                item.fw_mem_waddr = vif.mon_cb.fw_mem_waddr;
                item.fw_mem_val   = vif.mon_cb.fw_mem_val;
                item.fw_wb_we     = vif.mon_cb.fw_wb_we;
                item.fw_wb_waddr  = vif.mon_cb.fw_wb_waddr;
                item.fw_wb_val    = vif.mon_cb.fw_wb_val;
                item.ex_mem_read  = vif.mon_cb.ex_mem_read;
                item.ex_waddr     = vif.mon_cb.ex_waddr;

                item.stall_req     = vif.mon_cb.stall_req;
                item.branch_taken  = vif.mon_cb.branch_taken;
                item.branch_target = vif.mon_cb.branch_target;
                item.jump_taken    = vif.mon_cb.jump_taken;
                item.jump_target   = vif.mon_cb.jump_target;
                item.val_rs        = vif.mon_cb.val_rs;
                item.val_rt        = vif.mon_cb.val_rt;
                item.imm_ext       = vif.mon_cb.imm_ext;
                item.waddr_out     = vif.mon_cb.waddr_out;
                item.sa_out        = vif.mon_cb.sa_out;
                item.rs_addr       = vif.mon_cb.rs_addr;
                item.rt_addr       = vif.mon_cb.rt_addr;
                item.rd_addr       = vif.mon_cb.rd_addr;
                item.alu_op        = vif.mon_cb.alu_op;
                item.mdu_op        = vif.mon_cb.mdu_op;
                item.mdu_start     = vif.mon_cb.mdu_start;
                item.sel_mdu_out   = vif.mon_cb.sel_mdu_out;
                item.alu_src       = vif.mon_cb.alu_src;
                item.reg_write     = vif.mon_cb.reg_write;
                item.mem_read      = vif.mon_cb.mem_read;
                item.mem_write     = vif.mon_cb.mem_write;
                item.mem_op        = vif.mon_cb.mem_op;
                item.mem_to_reg    = vif.mon_cb.mem_to_reg;
                item.illegal_inst  = vif.mon_cb.illegal_inst;
                
                ap.write(item);
            end
        endtask
    endclass

    // =========================================================================
    // 4. Scoreboard (Reference Model & Verification)
    // =========================================================================
    class mips_id_stage_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(mips_id_stage_scoreboard)
        uvm_analysis_imp #(mips_id_stage_item, mips_id_stage_scoreboard) item_collected_export;

        // Register File Mirror
        reg [31:0] regs [32];

        int match_cnt;
        int error_cnt;

        function new(string name = "mips_id_stage_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
            for (int i = 0; i < 32; i++) regs[i] = 32'd0;
            match_cnt = 0;
            error_cnt = 0;
        endfunction

        // Golden Decoder logic representing the reference model
        function void golden_decode(
            input  [31:0] inst,
            output [3:0]  alu_op,
            output [2:0]  mdu_op,
            output        mdu_start,
            output        sel_mdu_out,
            output        alu_src,
            output        reg_write,
            output [1:0]  reg_dst,
            output        imm_signed,
            output        use_sa,
            output        mem_read,
            output        mem_write,
            output [2:0]  mem_op,
            output [1:0]  mem_to_reg,
            output [2:0]  branch_op,
            output [1:0]  jump_op,
            output        illegal_inst
        );
            bit [5:0] opcode = inst[31:26];
            bit [5:0] func   = inst[5:0];
            bit [4:0] rt     = inst[20:16];

            // Default values
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
            mem_op       = 3'b100;
            mem_to_reg   = 2'b00;
            branch_op    = 3'b000;
            jump_op      = 2'b00;
            illegal_inst = 1'b0;

            case (opcode)
                6'b000000: begin // SPECIAL
                    case (func)
                        6'b100000: begin alu_op = 4'b0000; reg_write = 1; reg_dst = 2'b01; end // ADD
                        6'b100001: begin alu_op = 4'b0001; reg_write = 1; reg_dst = 2'b01; end // ADDU
                        6'b100010: begin alu_op = 4'b0010; reg_write = 1; reg_dst = 2'b01; end // SUB
                        6'b100011: begin alu_op = 4'b0011; reg_write = 1; reg_dst = 2'b01; end // SUBU
                        6'b100100: begin alu_op = 4'b0100; reg_write = 1; reg_dst = 2'b01; end // AND
                        6'b100101: begin alu_op = 4'b0101; reg_write = 1; reg_dst = 2'b01; end // OR
                        6'b100110: begin alu_op = 4'b0110; reg_write = 1; reg_dst = 2'b01; end // XOR
                        6'b100111: begin alu_op = 4'b0111; reg_write = 1; reg_dst = 2'b01; end // NOR
                        6'b000000: begin alu_op = 4'b1000; reg_write = 1; reg_dst = 2'b01; end // SLL
                        6'b000010: begin alu_op = 4'b1001; reg_write = 1; reg_dst = 2'b01; end // SRL
                        6'b000011: begin alu_op = 4'b1010; reg_write = 1; reg_dst = 2'b01; end // SRA
                        6'b000100: begin alu_op = 4'b1000; reg_write = 1; reg_dst = 2'b01; use_sa = 0; end // SLLV
                        6'b000110: begin alu_op = 4'b1001; reg_write = 1; reg_dst = 2'b01; use_sa = 0; end // SRLV
                        6'b000111: begin alu_op = 4'b1010; reg_write = 1; reg_dst = 2'b01; use_sa = 0; end // SRAV
                        6'b101010: begin alu_op = 4'b1011; reg_write = 1; reg_dst = 2'b01; end // SLT
                        6'b101011: begin alu_op = 4'b1100; reg_write = 1; reg_dst = 2'b01; end // SLTU
                        6'b001000: begin jump_op = 2'b10; end // JR
                        6'b001001: begin reg_write = 1; reg_dst = 2'b01; mem_to_reg = 2'b10; jump_op = 2'b10; end // JALR
                        6'b010000: begin mdu_op = 3'b110; sel_mdu_out = 1; reg_write = 1; reg_dst = 2'b01; end // MFHI
                        6'b010010: begin mdu_op = 3'b111; sel_mdu_out = 1; reg_write = 1; reg_dst = 2'b01; end // MFLO
                        6'b010001: begin mdu_op = 3'b100; end // MTHI
                        6'b010011: begin mdu_op = 3'b101; end // MTLO
                        6'b011000: begin mdu_op = 3'b000; mdu_start = 1; end // MULT
                        6'b011001: begin mdu_op = 3'b001; mdu_start = 1; end // MULTU
                        6'b011010: begin mdu_op = 3'b010; mdu_start = 1; end // DIV
                        6'b011011: begin mdu_op = 3'b011; mdu_start = 1; end // DIVU
                        default:   begin illegal_inst = 1; end
                    endcase
                end
                6'b001000: begin alu_op = 4'b0000; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 1; end // ADDI
                6'b001001: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 1; end // ADDIU
                6'b001010: begin alu_op = 4'b1011; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 1; end // SLTI
                6'b001011: begin alu_op = 4'b1100; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 1; end // SLTIU
                6'b001100: begin alu_op = 4'b0100; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 0; end // ANDI
                6'b001101: begin alu_op = 4'b0101; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 0; end // ORI
                6'b001110: begin alu_op = 4'b0110; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 0; end // XORI
                6'b001111: begin alu_op = 4'b1101; alu_src = 1; reg_write = 1; reg_dst = 2'b00; imm_signed = 0; end // LUI
                6'b100011: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; mem_read = 1; mem_op = 3'b100; mem_to_reg = 2'b01; imm_signed = 1; end // LW
                6'b100000: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; mem_read = 1; mem_op = 3'b000; mem_to_reg = 2'b01; imm_signed = 1; end // LB
                6'b100100: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; mem_read = 1; mem_op = 3'b001; mem_to_reg = 2'b01; imm_signed = 1; end // LBU
                6'b100001: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; mem_read = 1; mem_op = 3'b010; mem_to_reg = 2'b01; imm_signed = 1; end // LH
                6'b100101: begin alu_op = 4'b0001; alu_src = 1; reg_write = 1; reg_dst = 2'b00; mem_read = 1; mem_op = 3'b011; mem_to_reg = 2'b01; imm_signed = 1; end // LHU
                6'b101011: begin alu_op = 4'b0001; alu_src = 1; mem_write = 1; mem_op = 3'b100; imm_signed = 1; end // SW
                6'b101000: begin alu_op = 4'b0001; alu_src = 1; mem_write = 1; mem_op = 3'b000; imm_signed = 1; end // SB
                6'b101001: begin alu_op = 4'b0001; alu_src = 1; mem_write = 1; mem_op = 3'b010; imm_signed = 1; end // SH
                6'b000010: begin jump_op = 2'b01; end // J
                6'b000011: begin reg_write = 1; reg_dst = 2'b10; mem_to_reg = 2'b10; jump_op = 2'b01; end // JAL
                6'b000100: begin branch_op = 3'b001; imm_signed = 1; end // BEQ
                6'b000101: begin branch_op = 3'b010; imm_signed = 1; end // BNE
                6'b000110: begin branch_op = 3'b011; imm_signed = 1; end // BLEZ
                6'b000111: begin branch_op = 3'b100; imm_signed = 1; end // BGTZ
                6'b000001: begin
                    case (rt)
                        5'b00000: begin branch_op = 3'b101; imm_signed = 1; end // BLTZ
                        5'b00001: begin branch_op = 3'b110; imm_signed = 1; end // BGEZ
                        default:  begin illegal_inst = 1; end
                    endcase
                end
                default: begin illegal_inst = 1; end
            endcase
        endfunction

        virtual function void write(mips_id_stage_item item);
            reg [31:0] exp_rdata1;
            reg [31:0] exp_rdata2;
            reg [31:0] exp_val_rs;
            reg [31:0] exp_val_rt;

            bit [3:0]  exp_alu_op;
            bit [2:0]  exp_mdu_op;
            bit        exp_mdu_start;
            bit        exp_sel_mdu_out;
            bit        exp_alu_src;
            bit        exp_reg_write;
            bit [1:0]  exp_reg_dst;
            bit        exp_imm_signed;
            bit        exp_use_sa;
            bit        exp_mem_read;
            bit        exp_mem_write;
            bit [2:0]  exp_mem_op;
            bit [1:0]  exp_mem_to_reg;
            bit [2:0]  exp_branch_op;
            bit [1:0]  exp_jump_op;
            bit        exp_illegal_inst;

            bit [4:0]  exp_sa_out;
            bit [31:0] exp_imm_ext;
            bit [4:0]  exp_waddr_out;
            bit        exp_branch_taken;
            bit [31:0] exp_branch_target;
            bit        exp_jump_taken;
            bit [31:0] exp_jump_target;
            bit        exp_reads_rs;
            bit        exp_reads_rt;
            bit        exp_stall_req;

            bit        miscompare;
            string     errmsg;

            // 1. Evaluate Register file internal bypass (for golden model calculation)
            exp_rdata1 = (item.rs_addr == 0) ? 32'd0 : 
                         ((item.rf_we && (item.rf_waddr == item.rs_addr)) ? item.rf_wdata : regs[item.rs_addr]);
            exp_rdata2 = (item.rt_addr == 0) ? 32'd0 : 
                         ((item.rf_we && (item.rf_waddr == item.rt_addr)) ? item.rf_wdata : regs[item.rt_addr]);

            // 2. Evaluate forwarding path values
            exp_val_rs = (item.rs_addr == 0) ? 32'd0 :
                         ((item.fw_ex_we  && (item.fw_ex_waddr  == item.rs_addr)) ? item.fw_ex_val :
                          ((item.fw_mem_we && (item.fw_mem_waddr == item.rs_addr)) ? item.fw_mem_val :
                           ((item.fw_wb_we  && (item.fw_wb_waddr  == item.rs_addr)) ? item.fw_wb_val : exp_rdata1)));

            exp_val_rt = (item.rt_addr == 0) ? 32'd0 :
                         ((item.fw_ex_we  && (item.fw_ex_waddr  == item.rt_addr)) ? item.fw_ex_val :
                          ((item.fw_mem_we && (item.fw_mem_waddr == item.rt_addr)) ? item.fw_mem_val :
                           ((item.fw_wb_we  && (item.fw_wb_waddr  == item.rt_addr)) ? item.fw_wb_val : exp_rdata2)));

            // 3. Decode instruction in golden reference model
            golden_decode(
                item.inst, exp_alu_op, exp_mdu_op, exp_mdu_start, exp_sel_mdu_out,
                exp_alu_src, exp_reg_write, exp_reg_dst, exp_imm_signed, exp_use_sa,
                exp_mem_read, exp_mem_write, exp_mem_op, exp_mem_to_reg, exp_branch_op,
                exp_jump_op, exp_illegal_inst
            );

            // 4. Predict other hardware outputs
            exp_sa_out = exp_use_sa ? item.inst[10:6] : exp_val_rs[4:0];
            exp_imm_ext = exp_imm_signed ? { {16{item.inst[15]}}, item.inst[15:0] } : { 16'd0, item.inst[15:0] };
            exp_waddr_out = (exp_reg_dst == 2'b00) ? item.rt_addr :
                            (exp_reg_dst == 2'b01) ? item.rd_addr :
                            (exp_reg_dst == 2'b10) ? 5'd31        : 5'd0;

            // Branch Decision & Target
            case (exp_branch_op)
                3'b001:  exp_branch_taken = (exp_val_rs == exp_val_rt);                      // BEQ
                3'b010:  exp_branch_taken = (exp_val_rs != exp_val_rt);                      // BNE
                3'b011:  exp_branch_taken = ($signed(exp_val_rs) <= $signed(32'd0));     // BLEZ
                3'b100:  exp_branch_taken = ($signed(exp_val_rs) >  $signed(32'd0));     // BGTZ
                3'b101:  exp_branch_taken = ($signed(exp_val_rs) <  $signed(32'd0));     // BLTZ
                3'b110:  exp_branch_taken = ($signed(exp_val_rs) >= $signed(32'd0));     // BGEZ
                default: exp_branch_taken = 0;
            endcase
            exp_branch_target = item.pc_plus_4 + { {14{item.inst[15]}}, item.inst[15:0], 2'b00 };

            // Jump Decision & Target
            exp_jump_taken = (exp_jump_op != 2'b00);
            exp_jump_target = (exp_jump_op == 2'b01) ? {item.pc_plus_4[31:28], item.inst[25:0], 2'b00} : exp_val_rs;

            // Hazard stall detection
            exp_reads_rs = (item.inst[31:26] == 6'b000000) ? (item.inst[5:0] != 6'b000000 && item.inst[5:0] != 6'b000010 && item.inst[5:0] != 6'b000011 && item.inst[5:0] != 6'b010000 && item.inst[5:0] != 6'b010010) :
                           (item.inst[31:26] != 6'b000010 && item.inst[31:26] != 6'b000011 && item.inst[31:26] != 6'b001111);

            exp_reads_rt = (item.inst[31:26] == 6'b000000) ? (item.inst[5:0] != 6'b001000 && item.inst[5:0] != 6'b001001 && item.inst[5:0] != 6'b010000 && item.inst[5:0] != 6'b010001 && item.inst[5:0] != 6'b010010 && item.inst[5:0] != 6'b010011) :
                           (item.inst[31:26] == 6'b101011 || item.inst[31:26] == 6'b101001 || item.inst[31:26] == 6'b101000 || item.inst[31:26] == 6'b000100 || item.inst[31:26] == 6'b000101);

            exp_stall_req = item.ex_mem_read && (item.ex_waddr != 0) &&
                            ((exp_reads_rs && (item.ex_waddr == item.rs_addr)) ||
                             (exp_reads_rt && (item.ex_waddr == item.rt_addr)));

            // 5. Compare with actual outputs
            miscompare = 0;
            errmsg = "";

            if (item.rs_addr !== item.inst[25:21]) begin miscompare = 1; errmsg = {errmsg, $sformatf("rs_addr mismatch: exp=%0d, act=%0d; ", item.inst[25:21], item.rs_addr)}; end
            if (item.rt_addr !== item.inst[20:16]) begin miscompare = 1; errmsg = {errmsg, $sformatf("rt_addr mismatch: exp=%0d, act=%0d; ", item.inst[20:16], item.rt_addr)}; end
            if (item.rd_addr !== item.inst[15:11]) begin miscompare = 1; errmsg = {errmsg, $sformatf("rd_addr mismatch: exp=%0d, act=%0d; ", item.inst[15:11], item.rd_addr)}; end

            if (item.val_rs !== exp_val_rs) begin miscompare = 1; errmsg = {errmsg, $sformatf("val_rs mismatch: exp=0x%h, act=0x%h; ", exp_val_rs, item.val_rs)}; end
            if (item.val_rt !== exp_val_rt) begin miscompare = 1; errmsg = {errmsg, $sformatf("val_rt mismatch: exp=0x%h, act=0x%h; ", exp_val_rt, item.val_rt)}; end
            if (item.imm_ext !== exp_imm_ext) begin miscompare = 1; errmsg = {errmsg, $sformatf("imm_ext mismatch: exp=0x%h, act=0x%h; ", exp_imm_ext, item.imm_ext)}; end
            if (item.waddr_out !== exp_waddr_out) begin miscompare = 1; errmsg = {errmsg, $sformatf("waddr_out mismatch: exp=%0d, act=%0d; ", exp_waddr_out, item.waddr_out)}; end
            if (item.sa_out !== exp_sa_out) begin miscompare = 1; errmsg = {errmsg, $sformatf("sa_out mismatch: exp=%0d, act=%0d; ", exp_sa_out, item.sa_out)}; end

            if (item.alu_op !== exp_alu_op) begin miscompare = 1; errmsg = {errmsg, $sformatf("alu_op mismatch: exp=%b, act=%b; ", exp_alu_op, item.alu_op)}; end
            if (item.mdu_op !== exp_mdu_op) begin miscompare = 1; errmsg = {errmsg, $sformatf("mdu_op mismatch: exp=%b, act=%b; ", exp_mdu_op, item.mdu_op)}; end
            if (item.mdu_start !== exp_mdu_start) begin miscompare = 1; errmsg = {errmsg, $sformatf("mdu_start mismatch: exp=%b, act=%b; ", exp_mdu_start, item.mdu_start)}; end
            if (item.sel_mdu_out !== exp_sel_mdu_out) begin miscompare = 1; errmsg = {errmsg, $sformatf("sel_mdu_out mismatch: exp=%b, act=%b; ", exp_sel_mdu_out, item.sel_mdu_out)}; end
            if (item.alu_src !== exp_alu_src) begin miscompare = 1; errmsg = {errmsg, $sformatf("alu_src mismatch: exp=%b, act=%b; ", exp_alu_src, item.alu_src)}; end
            if (item.reg_write !== exp_reg_write) begin miscompare = 1; errmsg = {errmsg, $sformatf("reg_write mismatch: exp=%b, act=%b; ", exp_reg_write, item.reg_write)}; end
            if (item.mem_read !== exp_mem_read) begin miscompare = 1; errmsg = {errmsg, $sformatf("mem_read mismatch: exp=%b, act=%b; ", exp_mem_read, item.mem_read)}; end
            if (item.mem_write !== exp_mem_write) begin miscompare = 1; errmsg = {errmsg, $sformatf("mem_write mismatch: exp=%b, act=%b; ", exp_mem_write, item.mem_write)}; end
            if (item.mem_op !== exp_mem_op) begin miscompare = 1; errmsg = {errmsg, $sformatf("mem_op mismatch: exp=%b, act=%b; ", exp_mem_op, item.mem_op)}; end
            if (item.mem_to_reg !== exp_mem_to_reg) begin miscompare = 1; errmsg = {errmsg, $sformatf("mem_to_reg mismatch: exp=%b, act=%b; ", exp_mem_to_reg, item.mem_to_reg)}; end
            if (item.illegal_inst !== exp_illegal_inst) begin miscompare = 1; errmsg = {errmsg, $sformatf("illegal_inst mismatch: exp=%b, act=%b; ", exp_illegal_inst, item.illegal_inst)}; end

            if (item.branch_taken !== exp_branch_taken) begin miscompare = 1; errmsg = {errmsg, $sformatf("branch_taken mismatch: exp=%b, act=%b; ", exp_branch_taken, item.branch_taken)}; end
            if (exp_branch_taken && item.branch_target !== exp_branch_target) begin miscompare = 1; errmsg = {errmsg, $sformatf("branch_target mismatch: exp=0x%h, act=0x%h; ", exp_branch_target, item.branch_target)}; end
            if (item.jump_taken !== exp_jump_taken) begin miscompare = 1; errmsg = {errmsg, $sformatf("jump_taken mismatch: exp=%b, act=%b; ", exp_jump_taken, item.jump_taken)}; end
            if (exp_jump_taken && item.jump_target !== exp_jump_target) begin miscompare = 1; errmsg = {errmsg, $sformatf("jump_target mismatch: exp=0x%h, act=0x%h; ", exp_jump_target, item.jump_target)}; end
            if (item.stall_req !== exp_stall_req) begin miscompare = 1; errmsg = {errmsg, $sformatf("stall_req mismatch: exp=%b, act=%b; ", exp_stall_req, item.stall_req)}; end

            if (miscompare) begin
                `uvm_error("SB_ID_ERR", $sformatf("ID Stage Miscompare for Inst=0x%h! %s", item.inst, errmsg))
                error_cnt++;
            end else begin
                match_cnt++;
            end

            // 6. Update Register File mirror with current clock edge writes
            if (item.rf_we && (item.rf_waddr != 5'd0)) begin
                regs[item.rf_waddr] = item.rf_wdata;
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SB_ID_REPORT", $sformatf("ID Scoreboard finished. Matches: %0d, Errors: %0d", match_cnt, error_cnt), UVM_NONE)
            if (error_cnt > 0) begin
                `uvm_fatal("SB_ID_FAIL", "Verification failed due to ID scoreboard errors!")
            end
        endfunction
    endclass

    // =========================================================================
    // 5. Agent
    // =========================================================================
    class mips_id_stage_agent extends uvm_agent;
        `uvm_component_utils(mips_id_stage_agent)

        mips_id_stage_driver    driver;
        mips_id_stage_monitor   monitor;
        uvm_sequencer #(mips_id_stage_item) sequencer;

        function new(string name = "mips_id_stage_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = mips_id_stage_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver = mips_id_stage_driver::type_id::create("driver", this);
                sequencer = uvm_sequencer#(mips_id_stage_item)::type_id::create("sequencer", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass

    // =========================================================================
    // 6. Environment
    // =========================================================================
    class mips_id_stage_env extends uvm_env;
        `uvm_component_utils(mips_id_stage_env)

        mips_id_stage_agent      agent;
        mips_id_stage_scoreboard scoreboard;

        function new(string name = "mips_id_stage_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = mips_id_stage_agent::type_id::create("agent", this);
            scoreboard = mips_id_stage_scoreboard::type_id::create("scoreboard", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.item_collected_export);
        endfunction
    endclass

    // =========================================================================
    // 7. Test Sequences
    // =========================================================================
    class mips_id_stage_base_seq extends uvm_sequence #(mips_id_stage_item);
        `uvm_object_utils(mips_id_stage_base_seq)

        function new(string name = "mips_id_stage_base_seq");
            super.new(name);
        endfunction
    endclass

    // Test sequence driving random instructions and hazards
    class id_rand_seq extends mips_id_stage_base_seq;
        `uvm_object_utils(id_rand_seq)
        
        int num_items = 5000;

        function new(string name = "id_rand_seq");
            super.new(name);
        endfunction

        virtual task body();
            repeat (num_items) begin
                req = mips_id_stage_item::type_id::create("req");
                start_item(req);
                if (!req.randomize()) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);
            end
        endtask
    endclass

    // =========================================================================
    // 8. Test Cases
    // =========================================================================
    class mips_id_stage_base_test extends uvm_test;
        `uvm_component_utils(mips_id_stage_base_test)

        mips_id_stage_env env;

        function new(string name = "mips_id_stage_base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = mips_id_stage_env::type_id::create("env", this);
        endfunction

        virtual function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_top.print();
        endfunction
    endclass

    class id_test extends mips_id_stage_base_test;
        `uvm_component_utils(id_test)

        function new(string name = "id_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            id_rand_seq seq = id_rand_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
