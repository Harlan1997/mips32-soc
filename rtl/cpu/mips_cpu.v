// =============================================================================
// File Name: mips_cpu.v
// Design:    MIPS32 CPU Core Pipeline Integration (Full)
// Author:    Antigravity
// =============================================================================

`include "soc_config.vh"

module mips_cpu (
    input  wire        clk,
    input  wire        rst_n,
    
    // Instruction Cache Interface (to be connected to icache)
    output wire        inst_req,
    output wire [31:0] inst_addr,
    input  wire        inst_addr_ok,
    input  wire        inst_data_ok,
    input  wire        inst_bus_error,
    // I-cache refill failure; kept separate from an ordinary IBE response.
    input  wire        inst_cache_error,
    input  wire [31:0] inst_rdata,
    
    // Data Cache Interface (to be connected to dcache)
    output wire        data_req,
    output wire        data_we,
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    output wire [3:0]  data_be,
    output wire        data_uncacheable,
    output wire        data_cache_op_valid,
    output wire [4:0]  data_cache_op,
    output wire [31:0] data_cache_op_addr,
    // CACHE Index_Load/Store_Tag_I are routed to the I-cache by mips_core.
    // The raw operation and completion remain on the existing maintenance
    // handshake so the pipeline/CP0 ordering contract is unchanged.
    output wire        data_cache_op_is_icache,
    input  wire        data_cache_op_done,
    input  wire        data_cache_op_error,
    input  wire        data_addr_ok,
    input  wire        data_data_ok,
    input  wire        data_bus_error,
    // Cached D-side refill/writeback failure; uncached errors remain DBE.
    input  wire        data_cache_error,
    input  wire [31:0] data_cache_tag_rdata,
    output wire [31:0] data_cache_tag_wdata,
    input  wire [31:0] data_rdata,
    
    input  wire [5:0]  ext_int,
    input  wire        tlb_inv_en,
    input  wire [18:0] tlb_inv_vpn2,
    input  wire [7:0]  tlb_inv_asid,
    input  wire [1:0]  tlb_inv_scope,
    input  wire [5:0]  tlb_inv_wired_floor,
    
    // Pipeline controls
    output wire        debug_stall,
    output wire        debug_flush
);

    // =========================================================================
    // Pipeline Control Signals
    // =========================================================================
    wire stall_req_if;
    wire stall_req_id;
    wire stall_req_mem;
    wire mdu_ready;
    
    // Global stall if IF, MEM, or MDU stalls
    wire global_stall = stall_req_if | stall_req_mem | ~mdu_ready;
    
    // Exceptions
    wire wb_except_req;
    wire [4:0] wb_except_code;
    wire wb_except_is_tlb_refill;
    wire wb_tlb_refill_exception = wb_except_req & wb_except_is_tlb_refill;
    wire wb_is_eret;
    wire        intr_req;
    wire [31:0] epc_out;
    
    // Exception PC redirection
    wire exception_flush = wb_except_req | wb_is_eret | intr_req;
    wire [31:0] ebase_out;
    wire        cp0_bev;
    wire        cp0_vint_enabled;
    wire [31:0] cp0_vint_offset;
    wire [31:0] cp0_taglo;
    wire [31:0] cp0_taghi;
    // Single-core LL/SC reservation state. External snoops are not present in
    // the current fabric, so any completed store clears the reservation.
    reg         ll_reservation_valid;
    reg [31:0]  ll_reservation_addr;
    // A synchronous WB exception always takes precedence over an interrupt;
    // only an accepted interrupt may use the Cause.IV vector table.
    wire take_interrupt = intr_req && !wb_except_req && !wb_is_eret;
    wire wb_cache_error_exception = wb_except_req && (wb_except_code == 5'h1E);
    // The prototype firmware remains linked at the legacy useg vector.  The
    // product configuration instead follows the CP0 bootstrap/general-vector
    // contract. TLB refill is distinct from Invalid even though both report
    // TLBL/TLBS; its sideband survives the pipeline to select the refill slot.
    wire [31:0] exception_vector = wb_is_eret ? epc_out :
                                  (`SOC_PRODUCT_BOOT_ENABLE != 0) ?
                                  (cp0_bev ? (wb_cache_error_exception ? 32'hBFC0_0100 :
                                              wb_tlb_refill_exception ? 32'hBFC0_0200 : 32'hBFC0_0380) :
                                             (wb_cache_error_exception ? (ebase_out + 32'h0000_0100) :
                                              wb_tlb_refill_exception ? ebase_out :
                                              ((take_interrupt && cp0_vint_enabled) ?
                                               (ebase_out + cp0_vint_offset) :
                                               (ebase_out + 32'h0000_0180)))) :
                                  32'h0000_0180;
    
    // ID stage outputs (for flush logic)
    wire        id_branch_taken;
    wire [31:0] id_branch_target;
    wire        id_jump_taken;
    wire [31:0] id_jump_target;
    
    // WB stage signals (for ID regfile write)
    wire [4:0]  wb_waddr;
    wire [4:0]  wb_rd_addr;
    wire [4:0]  wb_cp0_raddr;
    wire [31:0] wb_wdata;
    
    // PC and IF/ID stall if global_stall or load-use hazard
    wire stall_pc = global_stall | stall_req_id;
    
    // IF flush on exception/eret
    wire if_flush = exception_flush;
    
    // IF/ID flush on exception only (MIPS has branch delay slots, so we DO NOT flush on branch/jump)
    wire if_id_flush = exception_flush;
    
    // ID/EX flushes (inserts bubble) if load-use hazard occurs without global stall, or on exception
    wire flush_id_ex = (stall_req_id & ~global_stall) | exception_flush;
    
    // EX/MEM and MEM/WB flush on exception
    wire flush_ex_mem = exception_flush;
    wire flush_mem_wb = exception_flush;
    
    assign debug_stall = global_stall;
    assign debug_flush = if_id_flush;

    // IF stage outputs
    wire [31:0] if_pc_plus_4;
    wire        if_adel_exception;

    // Phase B.3.c: MMU translation intermediate wires. Stages drive VA; MMU
    // combinationally translates to the PA that leaves the CPU boundary.
    wire [31:0] if_vaddr;
    wire [31:0] mem_vaddr;
    wire [2:0]  mmu_i_cache_attr;
    wire [2:0]  mmu_d_cache_attr;
    wire        mmu_i_ok;
    wire        mmu_d_ok;
    wire [2:0]  mmu_i_fault_type;
    wire [2:0]  mmu_d_fault_type;
    wire [7:0]  cp0_asid;
    wire [2:0]  cp0_config_k0;
    // Phase B.4: effective privilege from CP0 (combinational readback)
    wire        cpu_kernel_mode;
    wire        cpu_cu0;
    wire [31:0] cpu_hwrena;
    wire [31:0] mmu_ilookup_va;
    wire        mmu_ilookup_hit;
    wire        mmu_ilookup_multi_hit;
    wire        mmu_ilookup_v;
    wire        mmu_ilookup_d;
    wire [2:0]  mmu_ilookup_c;
    wire [19:0] mmu_ilookup_pfn;
    wire [31:0] mmu_dlookup_va;
    wire        mmu_dlookup_hit;
    wire        mmu_dlookup_multi_hit;
    wire        mmu_dlookup_v;
    wire        mmu_dlookup_d;
    wire [2:0]  mmu_dlookup_c;
    wire [19:0] mmu_dlookup_pfn;
    
    // =========================================================================
    // IF Stage
    // =========================================================================
    mips_if_stage #(
        .RESET_ADDR((`SOC_PRODUCT_BOOT_ENABLE != 0) ? `SOC_BOOT_ROM_KSEG1 : `SOC_BOOT_BASE)
    ) u_mips_if_stage (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall_pc),
        .branch_taken     (id_branch_taken),
        .branch_target    (id_branch_target),
        .jump_taken       (id_jump_taken),
        .jump_target      (id_jump_target),
        .exception_req    (exception_flush),
        .exception_vector (exception_vector),
        
        .inst_req         (inst_req),
        .inst_addr        (if_vaddr),
        .inst_addr_ok     (inst_addr_ok),
        .inst_data_ok     (inst_data_ok),
        
        .stall_req_if     (stall_req_if),
        
        .pc               (),
        .pc_plus_4        (if_pc_plus_4),
        .adel_exception   (if_adel_exception)
    );
    
    // =========================================================================
    // IF/ID Pipeline Register
    // =========================================================================
    wire [31:0] id_pc_plus_4;
    wire [31:0] id_inst;
    wire        id_except_req_in;
    wire [4:0]  id_except_code_in;
    wire        id_except_is_tlb_refill_in;
    
    // Phase B.3.d + B.4: fold MMU I-side fault into the IF-stage exception path.
    // AdEL (misaligned PC) wins over MMU-TLBL because misalignment is detected
    // before translation would run in a real pipeline. MMU can additionally
    // report AdEL when a user-mode fetch hits kseg (Phase B.4). Under
    // SOC_MMU_ENABLE=0 with kernel-mode default, mmu_i_ok is always 1 → this
    // reduces to the pre-B.3.d AdEL-only behaviour and no regression is
    // possible.
    // Case equality keeps legacy standalone CPU harnesses that omit the new
    // optional cache-error sideband electrically quiet rather than X-active.
    wire        if_bus_fault  = inst_req & inst_data_ok & (inst_bus_error === 1'b1);
    wire        if_cache_fault = inst_req & inst_data_ok & (inst_cache_error === 1'b1);
    wire        if_fault_req  = if_adel_exception | if_cache_fault | if_bus_fault | (~mmu_i_ok & inst_req);
    wire [4:0]  if_fault_code = if_adel_exception            ? 5'h04 :  // misaligned PC
                                if_cache_fault                ? 5'h1E :  // CacheErr
                                if_bus_fault                  ? 5'h06 :  // IBE
                                (mmu_i_fault_type == 3'b110) ? 5'h18 :  // MCheck
                                (mmu_i_fault_type == 3'b100) ? 5'h04 :  // AdEL from MMU
                                                                5'h02;  // TLBL default
    // A lookup miss is a refill candidate. A lookup hit with V=0 is Invalid
    // and must use the general exception vector despite the shared TLBL code.
    wire if_except_is_tlb_refill = ~if_adel_exception & inst_req & ~mmu_i_ok &
                                   (mmu_i_fault_type == 3'b001) & ~mmu_ilookup_hit;

    mips_if_id_reg u_mips_if_id_reg (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (stall_pc),
        .flush        (if_id_flush),
        .if_pc_plus_4 (if_pc_plus_4),
        .if_inst      (inst_rdata),
        .if_except_req  (if_fault_req),
        .if_except_code (if_fault_code),
        .if_except_is_tlb_refill (if_except_is_tlb_refill),
        .id_pc_plus_4 (id_pc_plus_4),
        .id_inst      (id_inst),
        .id_except_req  (id_except_req_in),
        .id_except_code (id_except_code_in),
        .id_except_is_tlb_refill (id_except_is_tlb_refill_in)
    );
    
    // PC+8 calculation for link instructions
    wire [31:0] id_pc_plus_8 = id_pc_plus_4 + 32'd4;
    
    // =========================================================================
    // ID Stage
    // =========================================================================
    wire [31:0] id_val_rs;
    wire [31:0] id_val_rt;
    wire [31:0] id_imm_ext;
    wire [31:0] mem_rdata_fmt;
    wire [4:0]  id_waddr;
    wire [4:0]  id_sa;
    
    wire [4:0]  id_alu_op;
    wire [3:0]  id_mdu_op;
    wire        id_mdu_start;
    wire        id_sel_mdu_out;
    wire        id_alu_src;
    wire        id_reg_write;
    wire        id_mem_read;
    wire        id_mem_write;
    wire [2:0]  id_mem_op;
    wire        id_cache_op_valid;
    wire [4:0]  id_cache_op;

    wire        id_illegal_inst;
    wire        id_cp0_we;
    wire        id_is_mfc0;
    wire        id_is_eret;
    wire        id_is_syscall;
    
    wire [4:0]  id_rs_addr;
    wire [4:0]  id_rt_addr;
    wire [4:0]  id_rd_addr;
    wire [4:0]  id_cp0_raddr;
    wire [2:0]  id_cp0_sel;
    wire [2:0]  ex_cp0_sel;
    wire [2:0]  mem_cp0_sel;
    wire [2:0]  wb_cp0_sel;
    wire [2:0]  id_tlb_op;
    wire [2:0]  ex_tlb_op;
    wire [2:0]  mem_tlb_op;
    wire [2:0]  wb_tlb_op;
    
    // Pipeline outputs for forwarding and hazard
    wire        ex_reg_write;
    wire [4:0]  ex_waddr;
    wire [31:0] ex_out; // from EX stage output
    wire        ex_mem_read;
    
    wire        mem_reg_write;
    wire        mem_cp0_we;
    wire        mem_is_eret;
    wire        mem_except_req;
    wire [4:0]  mem_except_code;
    wire [4:0]  mem_waddr;
    wire [31:0] mem_ex_out;
    wire        mem_mem_read;
    wire        mem_cache_op_valid;
    wire [4:0]  mem_cache_op;
    
    wire        wb_reg_write;
    wire        wb_cp0_we;
    wire [1:0]  wb_mem_to_reg;
    wire [1:0]  id_mem_to_reg;
    
    wire        ex_illegal_inst;
    wire        ex_except_req;
    wire [4:0]  ex_except_code;
    wire        ex_except_is_data;    // Phase B.3.d
    wire        mem_except_is_data;
    wire        wb_except_is_data;
    wire        ex_except_is_tlb_refill;
    wire        mem_except_is_tlb_refill;
    // Phase B.5: delay-slot marker propagated with each instruction so an
    // exception on a delay-slot instruction can drive Cause.BD=1 and EPC=PC-4.
    wire        id_bd;
    wire        ex_bd;
    wire        mem_bd;
    wire        wb_bd;
    wire        ex_cp0_we;
    wire        ex_is_eret;
    wire [1:0]  ex_mem_to_reg;
    wire [1:0]  mem_mem_to_reg;
    
    mips_id_stage u_mips_id_stage (
        .clk           (clk),
        .rst_n         (rst_n),
        .inst          (id_inst),
        .pc_plus_4     (id_pc_plus_4),
        
        // Writeback port
        .rf_waddr      (wb_waddr),
        .rf_wdata      (wb_wdata),
        .rf_we         (wb_reg_write),
        
        // Forwarding
        .fw_ex_we      (ex_reg_write),
        .fw_ex_waddr   (ex_waddr),
        .fw_ex_val     (ex_out),
        .fw_mem_we     (mem_reg_write),
        .fw_mem_waddr  (mem_waddr),
        // MEM-stage forwarding carries the formatted load result for loads;
        // ALU results continue to come from the EX/MEM address/result bus.
        .fw_mem_val    (mem_mem_read ? mem_rdata_fmt : mem_ex_out),
        .fw_wb_we      (wb_reg_write),
        .fw_wb_waddr   (wb_waddr),
        .fw_wb_val     (wb_wdata),
        
        // Hazard detection
        .ex_mem_read   (ex_mem_read),
        .ex_waddr      (ex_waddr),
        .mem_mem_read  (mem_mem_read),
        .ex_mem_to_reg (ex_mem_to_reg),
        .mem_mem_to_reg(mem_mem_to_reg),
        .stall_req     (stall_req_id),
        
        // Branch & Jump
        .branch_taken  (id_branch_taken),
        .branch_target (id_branch_target),
        .jump_taken    (id_jump_taken),
        .jump_target   (id_jump_target),
        
        // Outputs to ID/EX
        .val_rs        (id_val_rs),
        .val_rt        (id_val_rt),
        .imm_ext       (id_imm_ext),
        .waddr_out     (id_waddr),
        .sa_out        (id_sa),
        .rs_addr       (id_rs_addr),
        .rt_addr       (id_rt_addr),
        .rd_addr       (id_rd_addr),
        .id_cp0_raddr  (id_cp0_raddr),
        .id_cp0_sel    (id_cp0_sel),
        
        // Controls to ID/EX
        .alu_op        (id_alu_op),
        .mdu_op        (id_mdu_op),
        .mdu_start     (id_mdu_start),
        .sel_mdu_out   (id_sel_mdu_out),
        .alu_src       (id_alu_src),
        .reg_write     (id_reg_write),
        .mem_read      (id_mem_read),
        .mem_write     (id_mem_write),
        .mem_op        (id_mem_op),
        .mem_to_reg    (id_mem_to_reg),
        .cache_op_valid(id_cache_op_valid),
        .cache_op      (id_cache_op),

        .illegal_inst  (id_illegal_inst),
        .cp0_we        (id_cp0_we),
        .is_mfc0       (id_is_mfc0),
        .is_eret       (id_is_eret),
        .is_syscall    (id_is_syscall),
        .tlb_op        (id_tlb_op)
    );
    
    // Phase B.4: privileged instruction detection + CU0 gate. If the current
    // ID instruction is MTC0/MFC0/ERET/TLB* and the effective mode is user-mode
    // without Status.CU0 override, raise Coprocessor Unusable (ExcCode 11).
    wire id_is_rdhwr_userlocal = (id_inst[31:26] == 6'b011111) &&
                                 (id_inst[25:21] == 5'b00011) &&
                                 (id_inst[15:11] == 5'd29) &&
                                 (id_inst[5:0] == 6'b111011);
    wire id_is_priv     = id_cp0_we | id_is_mfc0 | id_is_eret | (|id_tlb_op);
    wire id_rdhwr_allowed = id_is_rdhwr_userlocal && cpu_hwrena[29];
    wire id_cpu_unusable = id_is_priv & ~cpu_kernel_mode & ~cpu_cu0 &
                           ~id_rdhwr_allowed;

    // Exception priority at ID: upstream (IF-origin) > CpU > SYSCALL > RI.
    wire id_except_req_out = id_except_req_in | id_illegal_inst | id_is_syscall
                           | id_cpu_unusable;
    wire [4:0] id_except_code_out = id_except_req_in ? id_except_code_in :
                                    id_cpu_unusable  ? 5'h0B :   // CpU
                                    id_is_syscall    ? 5'h08 :   // Sys
                                    id_illegal_inst  ? 5'h0A :   // RI
                                                        5'h00;
    wire id_except_is_tlb_refill_out = id_except_req_in & id_except_is_tlb_refill_in;

    // Phase B.5: delay-slot detector. The current ID-stage instruction is in a
    // delay slot iff the *previous* cycle's ID decoded a branch or jump (both
    // conditional branches and jumps require the following instruction to be
    // executed per MIPS ISA). The pipeline advances when !global_stall.
    reg id_bd_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            id_bd_r <= 1'b0;
        else if (if_id_flush)
            id_bd_r <= 1'b0;
        else if (!global_stall)
            id_bd_r <= id_branch_taken | id_jump_taken;
    end
    assign id_bd = id_bd_r;
    
    // =========================================================================
    // ID/EX Pipeline Register
    // =========================================================================
    wire [31:0] ex_val_rs;
    wire [31:0] ex_val_rt;
    wire [31:0] ex_imm_ext;
    wire [31:0] ex_pc_plus_8;
    wire [4:0]  ex_rd_addr;
    wire [4:0]  ex_cp0_raddr;
    wire [4:0]  ex_sa;
    
    wire [4:0]  ex_alu_op;
    wire [3:0]  ex_mdu_op;
    wire        ex_mdu_start;
    wire        ex_sel_mdu_out;
    wire        ex_alu_src;
    wire        ex_mem_write;
    wire [2:0]  ex_mem_op;
    wire        ex_cache_op_valid;
    wire [4:0]  ex_cache_op;
    
    mips_id_ex_reg u_mips_id_ex_reg (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (global_stall),
        .flush          (flush_id_ex), // bubble
        
        .id_val_rs      (id_val_rs),
        .id_val_rt      (id_val_rt),
        .id_imm_ext     (id_imm_ext),
        .id_pc_plus_8   (id_pc_plus_8),
        .id_waddr       (id_waddr),
        .id_rd_addr     (id_rd_addr),
        .id_cp0_raddr   (id_cp0_raddr),
        .id_cp0_sel     (id_cp0_sel),
        .id_sa          (id_sa),
        .id_alu_op      (id_alu_op),
        .id_mdu_op      (id_mdu_op),
        .id_mdu_start   (id_mdu_start),
        .id_illegal_inst(id_illegal_inst),
        .id_except_req  (id_except_req_out),
        .id_except_code (id_except_code_out),
        .id_except_is_data (1'b0),  // IF-origin faults + ID-added (RI/SYS) are never MEM-side
        .id_except_is_tlb_refill (id_except_is_tlb_refill_out),
        .id_bd          (id_bd),
        .id_cp0_we      (id_cp0_we),
        .id_is_eret     (id_is_eret),
        .id_tlb_op      (id_tlb_op),
        .id_sel_mdu_out (id_sel_mdu_out),
        .id_alu_src     (id_alu_src),
        .id_reg_write   (id_reg_write),
        .id_mem_read    (id_mem_read),
        .id_mem_write   (id_mem_write),
        .id_mem_op      (id_mem_op),
        .id_mem_to_reg  (id_mem_to_reg),
        .id_cache_op_valid(id_cache_op_valid),
        .id_cache_op    (id_cache_op),
        
        .ex_val_rs      (ex_val_rs),
        .ex_val_rt      (ex_val_rt),
        .ex_imm_ext     (ex_imm_ext),
        .ex_pc_plus_8   (ex_pc_plus_8),
        .ex_waddr       (ex_waddr),
        .ex_rd_addr     (ex_rd_addr),
        .ex_cp0_raddr   (ex_cp0_raddr),
        .ex_cp0_sel     (ex_cp0_sel),
        .ex_sa          (ex_sa),
        .ex_alu_op      (ex_alu_op),
        .ex_mdu_op      (ex_mdu_op),
        .ex_mdu_start   (ex_mdu_start),
        .ex_illegal_inst(ex_illegal_inst),
        .ex_except_req  (ex_except_req),
        .ex_except_code (ex_except_code),
        .ex_except_is_data (ex_except_is_data),
        .ex_except_is_tlb_refill (ex_except_is_tlb_refill),
        .ex_bd          (ex_bd),
        .ex_cp0_we      (ex_cp0_we),
        .ex_is_eret     (ex_is_eret),
        .ex_tlb_op      (ex_tlb_op),
        .ex_sel_mdu_out (ex_sel_mdu_out),
        .ex_alu_src     (ex_alu_src),
        .ex_reg_write   (ex_reg_write),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_mem_op      (ex_mem_op),
        .ex_mem_to_reg  (ex_mem_to_reg),
        .ex_cache_op_valid(ex_cache_op_valid),
        .ex_cache_op    (ex_cache_op)
    );
    
    // =========================================================================
    // EX Stage
    // =========================================================================
    wire [31:0] ex_op_a = ex_val_rs;
    wire [31:0] ex_op_b = ex_alu_src ? ex_imm_ext : ex_val_rt;
    
    wire        ex_overflow;
    wire        ex_zero;
    wire [31:0] ex_hi_val;
    wire [31:0] ex_lo_val;
    
    mips_ex_stage u_mips_ex_stage (
        .clk         (clk),
        .rst_n       (rst_n),
        .op_a        (ex_op_a),
        .op_b        (ex_op_b),
        .sa          (ex_sa),
        .alu_op      (ex_alu_op),
        .mdu_op      (ex_mdu_op),
        .mdu_start   (ex_mdu_start),
        .sel_mdu_out (ex_sel_mdu_out),
        
        .ex_out      (ex_out),
        .overflow    (ex_overflow),
        .zero        (ex_zero),
        .mdu_ready   (mdu_ready),
        .hi_val      (ex_hi_val),
        .lo_val      (ex_lo_val)
    );
    
    // =========================================================================
    // EX/MEM Pipeline Register
    // =========================================================================
    wire [31:0] mem_val_rt;
    wire [31:0] mem_pc_plus_8;
    wire        mem_mem_write;
    wire [2:0]  mem_mem_op;
    wire [4:0]  mem_rd_addr;
    wire [4:0]  mem_cp0_raddr;
    wire        mem_done;
    
    mips_ex_mem_reg u_mips_ex_mem_reg (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (global_stall),
        .flush           (flush_ex_mem),
        .dmem_data_ok    (data_data_ok),
        .cache_op_done   (data_cache_op_done),
        
        .ex_out          (ex_out),
        .ex_val_rt       (ex_val_rt),
        .ex_pc_plus_8    (ex_pc_plus_8),
        .ex_waddr        (ex_waddr),
        .ex_rd_addr      (ex_rd_addr),
        .ex_cp0_raddr    (ex_cp0_raddr),
        .ex_cp0_sel      (ex_cp0_sel),
        .ex_reg_write    (ex_reg_write),
        .ex_cp0_we       (ex_cp0_we),
        .ex_is_eret      (ex_is_eret),
        .ex_tlb_op       (ex_tlb_op),
        .ex_except_req   (ex_except_req),
        .ex_except_code  (ex_except_code),
        .ex_except_is_data (ex_except_is_data),
        .ex_except_is_tlb_refill (ex_except_is_tlb_refill),
        .ex_bd           (ex_bd),
        .ex_mem_read     (ex_mem_read),
        .ex_mem_write    (ex_mem_write),
        .ex_mem_op       (ex_mem_op),
        .ex_mem_to_reg   (ex_mem_to_reg),
        .ex_cache_op_valid(ex_cache_op_valid),
        .ex_cache_op     (ex_cache_op),
        
        .mem_ex_out      (mem_ex_out),
        .mem_val_rt      (mem_val_rt),
        .mem_pc_plus_8   (mem_pc_plus_8),
        .mem_waddr       (mem_waddr),
        .mem_rd_addr     (mem_rd_addr),
        .mem_cp0_raddr   (mem_cp0_raddr),
        .mem_cp0_sel     (mem_cp0_sel),
        .mem_reg_write   (mem_reg_write),
        .mem_cp0_we      (mem_cp0_we),
        .mem_is_eret     (mem_is_eret),
        .mem_tlb_op      (mem_tlb_op),
        .mem_except_req  (mem_except_req),
        .mem_except_code (mem_except_code),
        .mem_except_is_data (mem_except_is_data),
        .mem_except_is_tlb_refill (mem_except_is_tlb_refill),
        .mem_bd          (mem_bd),
        .mem_mem_read    (mem_mem_read),
        .mem_mem_write   (mem_mem_write),
        .mem_mem_op      (mem_mem_op),
        .mem_mem_to_reg  (mem_mem_to_reg),
        .mem_cache_op_valid(mem_cache_op_valid),
        .mem_cache_op    (mem_cache_op),
        .mem_done        (mem_done)
    );
    
    // =========================================================================
    // MEM Stage
    // =========================================================================
    wire        mem_adel_exception;
    wire        mem_ades_exception;
    wire        mem_cache_op_fault;
    wire [31:0] cache_op_vaddr;
    wire        data_we_raw;
    
    mips_mem_stage u_mips_mem_stage (
        .mem_ex_out      (mem_ex_out),
        .mem_val_rt      (mem_val_rt),
        .mem_read        (mem_mem_read),
        .mem_write       (mem_mem_write),
        .mem_op          (mem_mem_op),
        .mem_done        (mem_done),
        .mem_cache_op_valid(mem_cache_op_valid),
        .mem_cache_op    (mem_cache_op),
        
        .dmem_rdata      (data_rdata),
        .dmem_addr       (mem_vaddr),
        .dmem_wdata      (data_wdata),
        .dmem_we         (data_we_raw),
        .dmem_be         (data_be),
        .dmem_en         (data_req),
        .dmem_addr_ok    (data_addr_ok),
        .dmem_data_ok    (data_data_ok),
        .cache_op_done   (data_cache_op_done),
        .cache_op_error  (data_cache_op_error),
        
        .stall_req_mem   (stall_req_mem),
        .cache_op_valid  (data_cache_op_valid),
        .cache_op        (data_cache_op),
        .cache_op_addr   (cache_op_vaddr),
        .cache_op_fault  (mem_cache_op_fault),
        
        .mem_rdata_ext   (mem_rdata_fmt),
        .adel_exception  (mem_adel_exception),
        .ades_exception  (mem_ades_exception)
    );

    wire is_ll_mem = mem_mem_read  && (mem_mem_op == 3'b111);
    wire is_sc_mem = mem_mem_write && (mem_mem_op == 3'b111);
    wire sc_reservation_match = ll_reservation_valid &&
                                 (ll_reservation_addr == {mem_vaddr[31:2], 2'b00});
    assign data_we = data_we_raw && (!is_sc_mem || sc_reservation_match);
    wire [31:0] mem_ex_out_wb = is_sc_mem ? {31'd0, sc_reservation_match} : mem_ex_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ll_reservation_valid <= 1'b0;
            ll_reservation_addr  <= 32'd0;
        end else if (data_data_ok) begin
            if (is_ll_mem) begin
                ll_reservation_valid <= 1'b1;
                ll_reservation_addr  <= {mem_vaddr[31:2], 2'b00};
            end else if (mem_mem_write) begin
                ll_reservation_valid <= 1'b0;
            end
        end
    end

    // Phase B.3.d: fold MMU D-side fault into MEM-stage exception path.
    // Priority within MEM stage: upstream (mem_except_req) > MMU fault >
    // AdEL/AdES. Under SOC_MMU_ENABLE=0 mmu_d_ok is always 1 → this reduces
    // to the pre-B.3.d AdEL/AdES-only behaviour.
    //   MMU fault_type encoding: 010=TLBS, 011=Mod, else (001) → TLBL.
    wire        dmem_translate_req = data_req | data_cache_op_valid;
    wire        mem_mmu_fault      = ~mmu_d_ok & dmem_translate_req;
    wire [4:0]  mem_mmu_fault_code = (mmu_d_fault_type == 3'b010) ? 5'h03 :  // TLBS
                                     (mmu_d_fault_type == 3'b011) ? 5'h01 :  // Mod
                                     (mmu_d_fault_type == 3'b110) ? 5'h18 :  // MCheck
                                     (mmu_d_fault_type == 3'b100) ? 5'h04 :  // AdEL (user kseg)
                                     (mmu_d_fault_type == 3'b101) ? 5'h05 :  // AdES (user kseg)
                                                                     5'h02;  // TLBL
    wire mem_mmu_refill = mem_mmu_fault &
                          ((mmu_d_fault_type == 3'b001) || (mmu_d_fault_type == 3'b010)) &
                          ~mmu_dlookup_hit;
    wire mem_bus_fault      = data_req & data_data_ok & (data_bus_error === 1'b1);
    wire mem_cache_fault    = data_req & data_data_ok & (data_cache_error === 1'b1);
    wire mem_cache_op_fault_seen = mem_cache_op_fault |
                                   (data_cache_op_valid & data_cache_op_done &
                                    (data_cache_op_error === 1'b1));
    wire mem_except_req_out  = mem_except_req | mem_mmu_fault | mem_cache_fault |
                               mem_cache_op_fault_seen | mem_bus_fault
                             | mem_adel_exception | mem_ades_exception;
    wire [4:0] mem_except_code_out = mem_except_req      ? mem_except_code
                                   : mem_mmu_fault       ? mem_mmu_fault_code
                                   : (mem_cache_fault || mem_cache_op_fault_seen) ? 5'h1E // CacheErr
                                   : mem_bus_fault       ? 5'h07 // DBE
                                   : mem_adel_exception  ? 5'h04
                                   : mem_ades_exception  ? 5'h05
                                                          : 5'h00;
    // Upstream (IF-origin) faults keep their is_data (=0); any fault added at
    // MEM stage is MEM-origin (data-address related), so is_data becomes 1.
    wire mem_except_is_data_out = mem_except_req ? mem_except_is_data : 1'b1;
    wire mem_except_is_tlb_refill_out = mem_except_req ? mem_except_is_tlb_refill
                                                        : mem_mmu_refill;
    
    // =========================================================================
    // MEM/WB Pipeline Register
    // =========================================================================
    wire [31:0] wb_rdata_fmt;
    wire [31:0] wb_ex_out;
    wire [31:0] wb_pc_plus_8;
    reg  [31:0] completed_load_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            completed_load_data <= 32'd0;
        else if (data_data_ok && mem_mem_read)
            completed_load_data <= mem_rdata_fmt;
    end
    
    // In-order-retirement completion buffer (mini-ROB). Stage 2: DEPTH=2,
    // real circular-buffer bookkeeping now runs, but is still a bit-exact
    // drop-in for the old MEM/WB register because the D-cache is still
    // blocking (see mips_rob.v header comment). Ports match mips_mem_wb_reg
    // exactly.
    // The current D-cache is blocking, so use the proven single-entry
    // retirement path. The depth-2 bookkeeping path remains opt-in until its
    // late-response capture semantics are closed.
    wire rob_stall = global_stall && !(data_data_ok || data_cache_op_done);

    mips_rob #(.DEPTH(1)) u_mips_rob (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (rob_stall),
        .flush           (flush_mem_wb),

        .mem_rdata_fmt   (mem_rdata_fmt),
        .mem_ex_out      (mem_ex_out_wb),
        .mem_pc_plus_8   (mem_pc_plus_8),
        .mem_waddr       (mem_waddr),
        .mem_rd_addr     (mem_rd_addr),
        .mem_cp0_raddr   (mem_cp0_raddr),
        .mem_cp0_sel     (mem_cp0_sel),

        .mem_reg_write   (mem_reg_write),
        .mem_cp0_we      (mem_cp0_we),
        .mem_is_eret     (mem_is_eret),
        .mem_tlb_op      (mem_tlb_op),
        .mem_except_req  (mem_except_req_out),
        .mem_except_code (mem_except_code_out),
        .mem_except_is_data (mem_except_is_data_out),
        .mem_except_is_tlb_refill (mem_except_is_tlb_refill_out),
        .mem_bd          (mem_bd),
        .mem_mem_to_reg  (mem_mem_to_reg),
        
        .wb_rdata_fmt    (wb_rdata_fmt),
        .wb_ex_out       (wb_ex_out),
        .wb_pc_plus_8    (wb_pc_plus_8),
        .wb_waddr        (wb_waddr),
        .wb_rd_addr      (wb_rd_addr),
        .wb_cp0_raddr    (wb_cp0_raddr),
        .wb_cp0_sel      (wb_cp0_sel),

        .wb_reg_write    (wb_reg_write),
        .wb_cp0_we       (wb_cp0_we),
        .wb_is_eret      (wb_is_eret),
        .wb_tlb_op       (wb_tlb_op),
        .wb_except_req   (wb_except_req),
        .wb_except_code  (wb_except_code),
        .wb_except_is_data (wb_except_is_data),
        .wb_except_is_tlb_refill (wb_except_is_tlb_refill),
        .wb_bd           (wb_bd),
        .wb_mem_to_reg   (wb_mem_to_reg)
    );
    
    // =========================================================================
    // Write Back (WB) Stage
    // =========================================================================
    wire [31:0] cp0_rdata;
    
    wire [31:0] wb_rdata_selected = (wb_mem_to_reg == 2'b01) ? completed_load_data : wb_rdata_fmt;

    mips_wb_stage u_mips_wb_stage (
        .mem_rdata_fmt (wb_rdata_selected),
        .ex_out      (wb_ex_out),
        .pc_plus_8   (wb_pc_plus_8),
        .mem_to_reg  (wb_mem_to_reg),
        .cp0_data    (cp0_rdata),
        
        .wb_wdata    (wb_wdata)
    );
    
    // =========================================================================
    // Coprocessor 0
    // =========================================================================

    wire [31:0] id_pc  = id_pc_plus_4 - 32'd4;
    wire [31:0] ex_pc  = ex_pc_plus_8 - 32'd8;
    wire [31:0] mem_pc = mem_pc_plus_8 - 32'd8;
    wire [31:0] wb_pc  = wb_pc_plus_8 - 32'd8;
    
    wire [31:0] oldest_flushed_pc = 
        (mem_pc_plus_8 != 32'd0) ? mem_pc :
        (ex_pc_plus_8  != 32'd0) ? ex_pc :
        (id_pc_plus_4  != 32'd0) ? id_pc :
        if_pc_plus_4 - 32'd4;
        
    wire [31:0] except_pc = wb_except_req ? wb_pc : oldest_flushed_pc;
    // Phase B.3.d: BadVAddr source. MEM-side faults (is_data=1) latch the data
    // address that reached MEM (wb_ex_out is the pipelined mem_ex_out); IF-side
    // faults latch the faulting fetch PC.
    wire [31:0] bad_vaddr = wb_except_is_data ? wb_ex_out : except_pc;
    mips_cp0 u_mips_cp0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .hw_int       (ext_int), // Connect hardware interrupt
        .we           (wb_cp0_we),
        .waddr        (wb_rd_addr),
        .wsel         (wb_cp0_sel),
        .wdata        (wb_ex_out),
        .raddr        (wb_cp0_raddr),
        .rsel         (wb_cp0_sel),
        .rdata        (cp0_rdata),
        .tlb_op       (wb_tlb_op),
        .cache_op_done(data_cache_op_done),
        .cache_op     (data_cache_op),
        .cache_tag_rdata(data_cache_tag_rdata),
        .except_req   (wb_except_req | intr_req),
        .except_code  (wb_except_req ? wb_except_code : 5'h00), // 0x00 for INT
        .except_pc    (except_pc),
        .except_bd    (wb_bd),
        .eret         (wb_is_eret),
        .bad_vaddr    (bad_vaddr),
        .tlb_inv_en   (tlb_inv_en),
        .tlb_inv_vpn2 (tlb_inv_vpn2),
        .tlb_inv_asid (tlb_inv_asid),
        .tlb_inv_scope(tlb_inv_scope),
        .tlb_inv_wired_floor(tlb_inv_wired_floor),
        .epc_out      (epc_out),
        .ebase_out    (ebase_out),
        .bev_out      (cp0_bev),
        .intr_req     (intr_req),
        .vint_enabled_out (cp0_vint_enabled),
        .vint_offset_out  (cp0_vint_offset),
        .kernel_mode  (cpu_kernel_mode),
        .cu0_enable   (cpu_cu0),
        .hwrena_out   (cpu_hwrena),

        // MMU pass-through
        .cp0_asid_out       (cp0_asid),
        .cp0_config_k0_out  (cp0_config_k0),
        .taglo_out          (cp0_taglo),
        .taghi_out          (cp0_taghi),
        .mmu_ilookup_va     (mmu_ilookup_va),
        .mmu_ilookup_hit    (mmu_ilookup_hit),
        .mmu_ilookup_multi_hit (mmu_ilookup_multi_hit),
        .mmu_ilookup_v      (mmu_ilookup_v),
        .mmu_ilookup_d      (mmu_ilookup_d),
        .mmu_ilookup_c      (mmu_ilookup_c),
        .mmu_ilookup_pfn    (mmu_ilookup_pfn),
        .mmu_dlookup_va     (mmu_dlookup_va),
        .mmu_dlookup_hit    (mmu_dlookup_hit),
        .mmu_dlookup_multi_hit (mmu_dlookup_multi_hit),
        .mmu_dlookup_v      (mmu_dlookup_v),
        .mmu_dlookup_d      (mmu_dlookup_d),
        .mmu_dlookup_c      (mmu_dlookup_c),
        .mmu_dlookup_pfn    (mmu_dlookup_pfn)
    );

    // -------------------------------------------------------------------------
    // Phase B.3.c: address translation for I-fetch and D-load/store.
    // With SOC_MMU_ENABLE=0 (default) both MMUs act as identity translators —
    // the CPU output PA equals the pipeline VA and downstream caches are
    // completely unaffected. When MMU is enabled, kseg0/1 direct-map is
    // active and useg/kseg2/kseg3 consult the CP0 TLB via the dual lookup
    // ports above.
    // -------------------------------------------------------------------------
    mips_mmu u_mmu_i (
        .req_valid       (inst_req),
        .req_va          (if_vaddr),
        .req_is_store    (1'b0),
        .req_is_fetch    (1'b1),
        .asid            (cp0_asid),
        .config_k0       (cp0_config_k0),
        .is_kernel       (cpu_kernel_mode),
        .tlb_lookup_va   (mmu_ilookup_va),
        .tlb_lookup_asid (),                 // driven internally by CP0 (asid)
        .tlb_lookup_hit  (mmu_ilookup_hit),
        .tlb_lookup_multi_hit (mmu_ilookup_multi_hit),
        .tlb_lookup_v    (mmu_ilookup_v),
        .tlb_lookup_d    (mmu_ilookup_d),
        .tlb_lookup_c    (mmu_ilookup_c),
        .tlb_lookup_pfn  (mmu_ilookup_pfn),
        .pa              (inst_addr),
        .cache_attr      (mmu_i_cache_attr),
        .translation_ok  (mmu_i_ok),
        .fault_type      (mmu_i_fault_type)
    );

    mips_mmu u_mmu_d (
        .req_valid       (dmem_translate_req),
        .req_va          (mem_vaddr),
        .req_is_store    (data_we),
        .req_is_fetch    (1'b0),
        .asid            (cp0_asid),
        .config_k0       (cp0_config_k0),
        .is_kernel       (cpu_kernel_mode),
        .tlb_lookup_va   (mmu_dlookup_va),
        .tlb_lookup_asid (),                 // driven internally by CP0 (asid)
        .tlb_lookup_hit  (mmu_dlookup_hit),
        .tlb_lookup_multi_hit (mmu_dlookup_multi_hit),
        .tlb_lookup_v    (mmu_dlookup_v),
        .tlb_lookup_d    (mmu_dlookup_d),
        .tlb_lookup_c    (mmu_dlookup_c),
        .tlb_lookup_pfn  (mmu_dlookup_pfn),
        .pa              (data_addr),
        .cache_attr      (mmu_d_cache_attr),
        .translation_ok  (mmu_d_ok),
        .fault_type      (mmu_d_fault_type)
    );

    // D-cache consumes the MIPS C=2 uncached attribute. I-cache routing and
    // the remaining cache attributes are still outside this integration slice.
    assign data_uncacheable = (mmu_d_cache_attr == 3'b010);
    assign data_cache_op_addr = data_addr;
    assign data_cache_op_is_icache = data_cache_op_valid &&
                                     ((data_cache_op == 5'b00100) ||
                                      (data_cache_op == 5'b01000));
    assign data_cache_tag_wdata = cp0_taglo;
    wire _mmu_unused = &{1'b0, mmu_i_cache_attr,
                              mmu_i_ok, mmu_d_ok,
                              mmu_i_fault_type, mmu_d_fault_type};

    // -------------------------------------------------------------------------
    // Phase B.6 — Branch Prediction Unit
    // -------------------------------------------------------------------------
    // Instantiated as an observation-side predictor: it maintains BTB/BHT/RAS
    // state driven by ID-stage resolution and produces per-fetch predictions.
    // The predictions are NOT routed into mips_if_stage.next_pc yet because
    // the current 5-stage pipeline already resolves branches in ID for zero
    // taken-branch penalty. A future phase that adds a fetch queue or moves
    // branch resolution later can flip SOC_BPU_ENABLE=1 and wire
    // predict_target into IF.
    wire        bpu_predict_hit;
    wire        bpu_predict_taken;
    wire [31:0] bpu_predict_target;
    wire [1:0]  bpu_predict_type;

    // Resolve interface: fire whenever ID resolves a branch or jump (not on
    // stalled cycles). Encoded BTB type follows the mips_bpu spec:
    //   00 conditional, 01 direct jump (J/JAL), 10 register jump (JR),
    //   11 register-and-link (JALR).
    // The decoder does not currently distinguish JAL from J or JALR from JR
    // at ID output, so we approximate:
    //   - Any conditional (branch_op != 0) → type 00
    //   - jump_op == 01 (direct J or JAL) → type 01
    //   - jump_op == 10 (JR or JALR)      → type 10 (return heuristic)
    // This is coarse but adequate for BPU state maintenance; refinement lands
    // when a JAL/JALR-specific decode bit is added.
    wire        bpu_id_is_cond   = id_branch_taken | ((~global_stall) & 1'b0);  // taken cond branch
    wire        bpu_id_is_jump   = id_jump_taken;
    wire        bpu_resolve_v    = (id_branch_taken | id_jump_taken) & ~global_stall;
    wire [1:0]  bpu_resolve_type = id_branch_taken ? 2'b00 :
                                   /*id_jump_taken*/ 2'b01;  // JR heuristic subsumed for now
    wire [31:0] bpu_resolve_pc   = id_pc;
    wire [31:0] bpu_resolve_tgt  = id_branch_taken ? id_branch_target : id_jump_target;
    wire        bpu_resolve_taken = 1'b1;   // only firing on taken cases (see above)

    mips_bpu u_mips_bpu (
        .clk               (clk),
        .rst_n             (rst_n),
        .if_valid          (inst_req),
        .if_pc             (if_vaddr),
        .predict_hit       (bpu_predict_hit),
        .predict_taken     (bpu_predict_taken),
        .predict_target    (bpu_predict_target),
        .predict_type      (bpu_predict_type),
        .resolve_valid     (bpu_resolve_v),
        .resolve_pc        (bpu_resolve_pc),
        .resolve_taken     (bpu_resolve_taken),
        .resolve_target    (bpu_resolve_tgt),
        .resolve_type      (bpu_resolve_type),
        .resolve_mispredict(1'b0)
    );

    // BPU outputs currently observability-only; suppress unused lint.
    wire _bpu_unused = &{1'b0, bpu_predict_hit, bpu_predict_taken,
                               bpu_predict_target, bpu_predict_type,
                               bpu_id_is_cond, bpu_id_is_jump};

    always @(posedge clk) begin
        if ($time > 324400 && $time < 324600) begin
            $display("[%t] PIPE: IF=%x ID=%x EX=%x MEM=%x WB=%x | stall_if=%b stall_mem=%b mdu_ready=%b global_stall=%b", 
                     $time,
                     if_pc_plus_4 - 32'd4,
                     id_pc,
                     ex_pc,
                     mem_pc,
                     wb_pc,
                     stall_req_if,
                     stall_req_mem,
                     mdu_ready,
                     global_stall);
        end
    end
endmodule
