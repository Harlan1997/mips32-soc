// =============================================================================
// File Name: mips_cpu.v
// Design:    MIPS32 CPU Core Pipeline Integration (Full)
// Author:    Antigravity
// =============================================================================

`include "soc_config.vh"

module mips_cpu #(
    parameter ENABLE_VEIC = 1'b0,
    parameter [9:0] CPUNUM = 10'd0,
    parameter ENABLE_PERF_COUNTERS = (`SOC_PERF_COUNTERS != 0)
) (
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
    output wire [3:0]  data_req_id,
    output wire        data_we,
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    output wire [3:0]  data_be,
    output wire        data_uncacheable,
    output wire        data_cache_op_valid,
    output wire [4:0]  data_cache_op,
    output wire [31:0] data_cache_op_addr,
    // CACHE I-cache invalidate and index-tag operations are routed by mips_core.
    // The raw operation and completion remain on the existing maintenance
    // handshake so the pipeline/CP0 ordering contract is unchanged.
    output wire        data_cache_op_is_icache,
    input  wire        data_cache_op_done,
    input  wire        data_cache_op_error,
    input  wire        data_addr_ok,
    input  wire        data_data_ok,
    input  wire [3:0]  data_resp_id,
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
    input  wire        sim_exception_req,
    input  wire [4:0]  sim_exception_code,
    input  wire [7:0]  external_vec_id,
    // A peer successful store invalidates reservations in the same cache line.
    input  wire        coh_snoop_valid,
    input  wire [31:0] coh_snoop_addr,

    input  wire        ctx_save_req,
    output wire        ctx_save_done,
    output wire [31:0] ctx_save_pc,
    output wire [31:0] ctx_save_status,
    output wire [7:0]  ctx_save_asid,
    output wire [31:0] ctx_save_srsctl,
    output wire [1023:0] ctx_save_gpr,
    output wire [16383:0] ctx_save_srs_gpr,
    output wire [1023:0] ctx_save_fpr,
    output wire [31:0] ctx_save_fcsr,
    input  wire        ctx_restore_req,
    input  wire [31:0] ctx_restore_pc,
    input  wire [31:0] ctx_restore_status,
    input  wire [7:0]  ctx_restore_asid,
    input  wire [31:0] ctx_restore_srsctl,
    input  wire [1023:0] ctx_restore_gpr,
    input  wire [16383:0] ctx_restore_srs_gpr,
    input  wire [3:0]  ctx_restore_set,
    input  wire [1023:0] ctx_restore_fpr,
    input  wire [31:0] ctx_restore_fcsr,
    output wire        ctx_restore_ack,

    input  wire        hardware_walker_enable,
    input  wire [31:0] hardware_walker_ptbr,
    output wire        ptw_mem_valid,
    output wire [31:0] ptw_mem_addr,
    input  wire        ptw_mem_ready,
    input  wire [31:0] ptw_mem_rdata,
    input  wire        ptw_mem_error,
    output wire        ptw_fault_valid,
    output wire [2:0]  ptw_fault_code,
    
    // Pipeline controls
    output wire        debug_stall,
    output wire        debug_flush,
    output wire [31:0] perf_cycle_count,
    output wire [31:0] perf_retire_count,
    output wire [31:0] perf_icache_miss_count,
    output wire [31:0] perf_dcache_miss_count,
    output wire [31:0] perf_branch_mispredict_count,
    output wire [31:0] perf_mdu_stall_count
);

    // =========================================================================
    // Pipeline Control Signals
    // =========================================================================
    wire stall_req_if;
    wire stall_req_id_raw;
    wire stall_req_id;
    wire stall_req_mem;
    wire mdu_ready;
    wire rob_backpressure;
    wire rob_head_ready;
    wire rob_busy;
    wire [1:0] rob_alloc_tag;
    wire rob_alloc_ready;
    wire [1:0] rob_retire_tag;
    wire [31:0] wb_pc_plus_8;
    wire [31:0] ex_inst;
    wire [31:0] mem_inst;
    wire        mem_double_mem = (`SOC_FPU_ENABLE != 0) &&
                                 ((mem_inst[31:26] == 6'b110101) ||
                                  (mem_inst[31:26] == 6'b111101));
    wire        mem_double_phase;
    wire        mem_done;
    wire        dmem_request_blocked;
    wire        id_is_wait;
    wire data_req_raw;
    wire data_addr_ok_effective;
    reg  [3:0] nb_load_busy;
    reg  [4:0] nb_load_rd [0:3];
    wire tagged_data_response = (`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                                (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                                (`SOC_ROB_FIFO_ENABLE != 0) &&
                                data_data_ok && data_resp_id[3];
    // Tagged late responses are consumed by the ROB, not by the instruction
    // currently occupying MEM.  Keeping a separate current-transaction
    // handshake prevents an older load response from completing a legacy
    // store or a newer load.
    wire data_data_ok_current = data_data_ok && !tagged_data_response;
    // A two-word COP1 access must also freeze the upstream pipeline on the
    // response cycles.  Otherwise ID/EX can advance the successor while
    // EX/MEM is still consuming the second beat, dropping that successor.
    wire double_response_stall = mem_double_mem && data_data_ok_current &&
                                  !mem_done;
    wire data_bus_error_current = data_bus_error && !tagged_data_response;
    wire data_cache_error_current = data_cache_error && !tagged_data_response;
    
    // Global stall if IF, MEM, or MDU stalls. Keep the ROB backpressure term
    // separate so the allocation event below can be defined without a
    // combinational self-dependency: the FIFO must stop a pipeline advance,
    // but it must not make an already-held EX/MEM instruction look newly
    // retired on every cycle.
    reg ptw_busy;
    reg ptw_refill_pending;
    reg ptw_fault_pending;
    reg ptw_fault_is_data;
    reg wait_state;
    reg [31:0] wait_resume_pc;
    wire walker_d_stall;
    wire context_active = (ctx_save_req === 1'b1) | (ctx_restore_req === 1'b1);
    wire global_stall_pre_rob = stall_req_if | stall_req_mem | double_response_stall |
                                ~mdu_ready |
                                context_active | ptw_busy | ptw_refill_pending |
                                walker_d_stall | wait_state;
    wire global_stall = global_stall_pre_rob | rob_backpressure;

    // WAIT is retired before entering the suspended state.  The CP0 interrupt
    // request remains combinational, so a pending enabled interrupt can wake
    // the core even though ordinary pipeline movement is frozen.
    // Exceptions
    wire wb_except_req;
    wire wb_valid;
    wire [4:0] wb_except_code;
    wire wb_except_is_tlb_refill;
    wire wb_tlb_refill_exception = wb_except_req & wb_except_is_tlb_refill;
    wire wb_is_eret;
    wire        intr_req;
    wire        cp0_exl;
    wire exception_flush;
    wire [31:0] epc_out;
    wire [31:0] wb_inst;
    wire [31:0] wb_val_rt;
    wire [3:0]  srs_current_set;
    wire [3:0]  srs_previous_set;
    wire        srs_shadow_we;
    wire [3:0]  srs_shadow_wset = srs_previous_set;
    wire [4:0]  srs_shadow_waddr = wb_inst[15:11];
    wire [31:0] srs_shadow_wdata = wb_val_rt;
    
    // Exception PC redirection
    wire sim_exception_active = (sim_exception_req === 1'b1);
    // Ordinary writes use the one-cycle ROB retirement pulse.  A legacy
    // depth-1 ROB can hold a fault or ERET bundle while it suppresses the
    // duplicate data retirement pulse; those control-flow events are still
    // architectural commits and must remain visible to CP0.  The exception
    // flush clears the bundle on the same edge, so including the held event
    // here does not re-accept it after the flush.
    wire wb_arch_valid = wb_valid || wb_except_req || wb_is_eret;
    // EXL suppresses CP0 state overwrite inside mips_cp0, but it must not
    // suppress the architectural redirect: nested synchronous faults (the
    // product refill ROM deliberately uses SYSCALL to enter its general
    // handler) still need to reach the general vector.  wb_arch_valid is the
    // precise-retirement guard against replaying a flushed fault.
    wire effective_except_req = (wb_except_req && wb_arch_valid) |
                                sim_exception_active;
    wire [4:0] effective_except_code = sim_exception_active ? sim_exception_code : wb_except_code;
    // MIPS Cause.CE identifies the coprocessor that raised CpU.  The
    // pipeline retains the faulting instruction through WB, so the opt-in
    // COP1 unusable path can report CE=1 without affecting CP0/RI traps.
    wire [1:0] effective_except_ce = (!sim_exception_active &&
                                      effective_except_code == 5'h0B &&
                                      wb_inst[31:26] == 6'b010001) ? 2'b01 : 2'b00;
    // A tagged load must retire before an asynchronous interrupt can flush
    // the pipeline. Otherwise the handler may observe a pre-load register
    // value while the response is still in the ROB.
    wire interrupt_accept = intr_req &&
                            // WAIT must reach retirement before a pending
                            // interrupt is accepted.  Otherwise the interrupt
                            // can preempt the instruction in an earlier stage
                            // and leave WAIT with no wakeup source.
                            !(id_is_wait || ex_inst == 32'h42000020 ||
                              mem_inst == 32'h42000020 ||
                              (wb_valid && wb_arch_valid &&
                               wb_inst == 32'h42000020)) &&
                            // An interrupt sampled while an uncached or
                            // blocking load/store is still in MEM can race
                            // the response edge.  Defer acceptance until the
                            // current transaction has completed so its APB
                            // side effect and load data retire precisely.
                            !stall_req_mem &&
                            !((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_ROB_FIFO_ENABLE != 0) &&
                              ((|nb_load_busy) || rob_busy));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_state <= 1'b0;
            wait_resume_pc <= 32'd0;
        end
        else if (interrupt_accept || ctx_restore_req || exception_flush)
            wait_state <= 1'b0;
        else if (wb_valid && wb_arch_valid &&
                 wb_inst == 32'h42000020) begin
            wait_state <= 1'b1;
            wait_resume_pc <= wb_pc_plus_8 - 32'd4;
        end
    end
    assign exception_flush = effective_except_req |
                            (wb_is_eret && wb_arch_valid) |
                            interrupt_accept;
    wire [31:0] ebase_out;
    wire        cp0_bev;
    wire        cp0_vint_enabled;
    wire [31:0] cp0_vint_offset;
    wire [3:0]  cp0_vint_srs_set;
    wire [31:0] cp0_taglo;
    wire [31:0] cp0_taghi;
    // LL/SC reservation state. A peer store clears a reservation at line
    // granularity, matching the coherency write-invalidate contract.
    reg         ll_reservation_valid;
    reg [31:0]  ll_reservation_addr;
    // A synchronous WB exception always takes precedence over an interrupt;
    // only an accepted interrupt may use the Cause.IV vector table.
    wire take_interrupt = interrupt_accept &&
                          !(wb_except_req && wb_arch_valid && !cp0_exl) &&
                          !(wb_is_eret && wb_arch_valid);
    wire wb_cache_error_exception = wb_except_req && wb_arch_valid &&
                                    (wb_except_code == 5'h1E);
    // MMU-enabled prototype firmware is linked in kseg0 so reset and the
    // general exception handler remain executable before software has created
    // any useg TLB entry. Product boot follows the CP0 bootstrap/general-vector
    // contract. TLB refill is distinct from Invalid even though both report
    // TLBL/TLBS; its sideband survives the pipeline to select the refill slot.
    wire [31:0] veic_offset = 32'h0000_0200 + ({24'd0, external_vec_id} << 5);
    wire [31:0] exception_vector = wb_is_eret ? epc_out :
                                  (`SOC_PRODUCT_BOOT_ENABLE != 0) ?
                                  (cp0_bev ? (wb_cache_error_exception ? 32'hBFC0_0100 :
                                              wb_tlb_refill_exception ? 32'hBFC0_0200 : 32'hBFC0_0380) :
                                             (wb_cache_error_exception ? (ebase_out + 32'h0000_0100) :
                                              wb_tlb_refill_exception ? ebase_out :
                                              ((take_interrupt && ENABLE_VEIC && (external_vec_id != 8'hff)) ?
                                               (ebase_out + veic_offset) :
                                              ((take_interrupt && cp0_vint_enabled) ?
                                               (ebase_out + cp0_vint_offset) :
                                               (ebase_out + 32'h0000_0180))))) :
                                  (`SOC_MMU_BOOTSTRAP_ENABLE != 0) ? 32'h8000_0180 :
                                  32'h0000_0180;
    
    // ID stage outputs (for flush logic)
    wire        id_branch_taken;
    wire        id_branch_likely_annul;
    wire        id_branch_likely_taken;
    wire        id_fpu_branch_invert;
    wire [31:0] id_branch_target;
    wire        id_jump_taken;
    wire [31:0] id_jump_target;
    wire        id_control_valid;
    wire        id_control_taken;
    wire [31:0] id_control_target;
    wire [1:0]  id_control_type;
    wire [31:0] id_pc_plus_4;

    wire        bpu_predict_hit;
    wire        bpu_predict_taken;
    wire [31:0] bpu_predict_target;
    wire [1:0]  bpu_predict_type;
    wire        id_bpu_valid;
    wire        id_bpu_taken;
    wire [31:0] id_bpu_target;
    wire [1:0]  id_bpu_type;
    wire        bpu_mispredict;
    wire [31:0] bpu_actual_next_pc = id_branch_likely_annul ? (id_pc_plus_4 + 32'd4) :
                                     (id_control_taken ? id_control_target : id_pc_plus_4);
    wire [31:0] bpu_predicted_next_pc = id_bpu_taken ? id_bpu_target :
                                        id_pc_plus_4;
    assign bpu_mispredict = (`SOC_BPU_ENABLE != 0) && id_control_valid &&
                            id_bpu_valid &&
                            (bpu_actual_next_pc != bpu_predicted_next_pc);

    mips_perf_counters u_perf_counters (
        .clk(clk), .rst_n(rst_n), .enable(ENABLE_PERF_COUNTERS), .clear(1'b0),
        .retire_event(!global_stall && id_control_valid),
        .icache_miss_event(inst_req && inst_addr_ok && !inst_data_ok),
        .dcache_miss_event(data_req && data_addr_ok && !data_data_ok_current),
        .branch_mispredict_event(bpu_mispredict),
        .mdu_stall_event(!mdu_ready),
        .cycle_count(perf_cycle_count), .retire_count(perf_retire_count),
        .icache_miss_count(perf_icache_miss_count),
        .dcache_miss_count(perf_dcache_miss_count),
        .branch_mispredict_count(perf_branch_mispredict_count),
        .mdu_stall_count(perf_mdu_stall_count)
    );

    
    // WB stage signals (for ID regfile write)
    wire [4:0]  wb_waddr;
    wire [4:0]  wb_rd_addr;
    wire [4:0]  wb_cp0_raddr;
    wire [31:0] wb_wdata;

    // PC and IF/ID stall if global_stall or load-use hazard
    wire stall_pc = global_stall | stall_req_id;
    
    // IF flush on exception/eret
    wire if_flush = exception_flush | ctx_restore_req;
    
    // Ordinary branches retain their architectural delay slot.  A not-taken
    // branch-likely is the exception: the already-fetched slot must be
    // annulled, while the current branch itself continues into ID/EX.
    wire if_id_flush = exception_flush | ctx_restore_req |
                        id_branch_likely_annul | id_branch_likely_taken;
    
    // ID/EX flushes (inserts bubble) if load-use hazard occurs without global stall, or on exception
    wire flush_id_ex = (stall_req_id & ~global_stall) | exception_flush | ctx_restore_req;
    
    // EX/MEM and MEM/WB flush on exception
    wire flush_ex_mem = exception_flush | ctx_restore_req;
    wire flush_mem_wb = exception_flush | ctx_restore_req;
    
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
    wire        cpu_cu1;
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
    // Translation is requested from the MEM-stage operation itself rather
    // than from data_req.  data_req is intentionally suppressed below when
    // translation fails, so deriving the MMU request from it would hide the
    // fault and deadlock the pipeline waiting for data_data_ok.
    wire dmem_translate_req;
    wire dmem_translation_fault;

    wire hw_walker_i_miss = (hardware_walker_enable === 1'b1) &&
                             inst_req && !mmu_i_ok &&
                             (mmu_i_fault_type == 3'b001);
    wire hw_walker_d_miss = (hardware_walker_enable === 1'b1) &&
                             dmem_translate_req && !mmu_d_ok &&
                             ((mmu_d_fault_type == 3'b001) ||
                             (mmu_d_fault_type == 3'b010));
    assign walker_d_stall = hw_walker_d_miss && !ptw_fault_pending;
    wire ptw_req_valid = !ptw_busy && !ptw_refill_pending && !ptw_fault_pending &&
                         (hw_walker_i_miss || hw_walker_d_miss);
    wire ptw_req_ready;
    wire ptw_resp_valid;
    wire [31:0] ptw_pa;
    wire ptw_fault_i;
    wire [2:0] ptw_fault_code_i;
    wire [31:0] ptw_leaf_pte;
    wire [31:0] ptw_req_va = hw_walker_i_miss ? if_vaddr : mem_vaddr;
    wire [1:0] ptw_req_access = hw_walker_i_miss ? 2'd0 :
                                 (data_we ? 2'd2 : 2'd1);
    wire ptw_req_user = !cpu_kernel_mode;
    reg [31:0] ptw_va_q;
    wire hw_tlb_wr_ready;
    wire hw_tlb_wr_en = ptw_refill_pending && hw_tlb_wr_ready;
    // Use the low VPN2 bits as a deterministic hardware-refill slot.  A
    // fixed slot lets an instruction refill evict the D-side translation
    // immediately (and vice versa), preventing the original operation from
    // retrying when both pages are active.
    wire [5:0] hw_tlb_wr_index = {2'b00, ptw_va_q[16:13]};
    wire hw_walker_i_fault = ptw_fault_pending && !ptw_fault_is_data;
    wire hw_walker_d_fault = ptw_fault_pending && ptw_fault_is_data;
    // The walker owns one 4KB leaf at a time.  Do not mirror that PFN into
    // both halves of the 8KB TLB pair: doing so aliases the adjacent page and
    // prevents a later fault/refill for the other half.
    wire [31:0] hw_tlb_entrylo_leaf = {2'b0, 4'b0, ptw_leaf_pte[31:12],
                                       3'b011, ptw_leaf_pte[1], ptw_leaf_pte[0], 1'b0};
    function automatic [5:0] hw_page_odd_bit;
        input [15:0] mask;
        begin
            case (mask)
                16'h0003: hw_page_odd_bit = 6'd14;
                16'h000f: hw_page_odd_bit = 6'd16;
                16'h003f: hw_page_odd_bit = 6'd18;
                default:  hw_page_odd_bit = 6'd12;
            endcase
        end
    endfunction
    wire hw_tlb_odd = ptw_va_q[hw_page_odd_bit(`SOC_HARDWARE_WALKER_PAGE_MASK)];
    wire [31:0] hw_tlb_entrylo0 = hw_tlb_odd ? 32'd0 : hw_tlb_entrylo_leaf;
    wire [31:0] hw_tlb_entrylo1 = hw_tlb_odd ? hw_tlb_entrylo_leaf : 32'd0;
    
    // =========================================================================
    // IF Stage
    // =========================================================================
    mips_if_stage #(
        .RESET_ADDR((`SOC_PRODUCT_BOOT_ENABLE != 0) ? `SOC_BOOT_ROM_KSEG1 :
                    ((`SOC_MMU_BOOTSTRAP_ENABLE != 0) ? 32'h8000_0000 : `SOC_BOOT_BASE))
    ) u_mips_if_stage (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall_pc),
        .branch_taken     (id_branch_taken),
        .branch_likely_annul(id_branch_likely_annul),
        .branch_likely_taken(id_branch_likely_taken),
        .branch_target    (id_branch_target),
        .jump_taken       (id_jump_taken),
        .jump_target      (id_jump_target),
        .bpu_enable       (`SOC_BPU_ENABLE != 0),
        .bpu_predict_valid(bpu_predict_hit),
        .bpu_predict_taken(bpu_predict_taken),
        .bpu_predict_target(bpu_predict_target),
        .bpu_recover      (bpu_mispredict),
        .bpu_recover_target(bpu_actual_next_pc),
        .exception_req    (exception_flush),
        .exception_vector (exception_vector),
        
        .inst_req         (inst_req),
        .inst_addr        (if_vaddr),
        .inst_addr_ok     (inst_addr_ok),
        .inst_data_ok     (inst_data_ok),
        
        .stall_req_if     (stall_req_if),
        
        .pc               (ctx_save_pc),
        .pc_plus_4        (if_pc_plus_4),
        .adel_exception   (if_adel_exception),
        .ctx_save_req     (ctx_save_req),
        .ctx_save_done    (),
        .ctx_restore_req  (ctx_restore_req),
        .ctx_restore_pc   (ctx_restore_pc),
        .ctx_restore_done ()
    );
    
    // =========================================================================
    // IF/ID Pipeline Register
    // =========================================================================
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
    wire        if_fault_req  = if_adel_exception | if_cache_fault | if_bus_fault |
                                hw_walker_i_fault |
                                ((~mmu_i_ok & inst_req) & !hw_walker_i_miss);
    wire [4:0]  if_fault_code = hw_walker_i_fault            ? 5'h02 :  // walker TLBL
                                if_adel_exception            ? 5'h04 :  // misaligned PC
                                if_cache_fault                ? 5'h1E :  // CacheErr
                                if_bus_fault                  ? 5'h06 :  // IBE
                                (mmu_i_fault_type == 3'b110) ? 5'h18 :  // MCheck
                                (mmu_i_fault_type == 3'b100) ? 5'h04 :  // AdEL from MMU
                                                                5'h02;  // TLBL default
    // A lookup miss is a refill candidate. A lookup hit with V=0 is Invalid
    // and must use the general exception vector despite the shared TLBL code.
    wire if_except_is_tlb_refill = ~if_adel_exception & inst_req & ~mmu_i_ok &
                                   !hw_walker_i_fault &
                                   (mmu_i_fault_type == 3'b001) & ~mmu_ilookup_hit;

    // IF faults are carried through the pipeline as control-only metadata.
    // Once the exception reaches WB, the fetch PC has already redirected to
    // the vector, so except_pc may describe an older kseg0 instruction rather
    // than the virtual address that missed translation. Hold the first fault
    // until CP0 consumes the exception bundle.
    reg        if_fault_pending_q;
    reg [31:0] if_fault_vaddr_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_fault_pending_q <= 1'b0;
            if_fault_vaddr_q   <= 32'd0;
        end else if (exception_flush) begin
            if_fault_pending_q <= 1'b0;
        end else if (if_fault_req && !if_fault_pending_q) begin
            if_fault_pending_q <= 1'b1;
            if_fault_vaddr_q   <= if_vaddr;
        end
    end

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
        .if_bpu_valid  (bpu_predict_hit),
        .if_bpu_taken  (bpu_predict_taken),
        .if_bpu_target (bpu_predict_target),
        .if_bpu_type   (bpu_predict_type),
        .id_pc_plus_4 (id_pc_plus_4),
        .id_inst      (id_inst),
        .id_except_req  (id_except_req_in),
        .id_except_code (id_except_code_in),
        .id_except_is_tlb_refill (id_except_is_tlb_refill_in),
        .id_bpu_valid  (id_bpu_valid),
        .id_bpu_taken  (id_bpu_taken),
        .id_bpu_target (id_bpu_target),
        .id_bpu_type   (id_bpu_type)
    );
    
    // PC+8 calculation for link instructions
    wire [31:0] id_pc_plus_8 = id_pc_plus_4 + 32'd4;
    
    // =========================================================================
    // ID Stage
    // =========================================================================
    wire [31:0] id_val_rs;
    wire [31:0] id_val_rt;
    wire [31:0] nb_pending_reg;
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
    wire        id_is_break;
    wire        id_is_di;
    wire        id_is_ei;
    wire        id_is_trap;
    wire [3:0]  id_trap_op;
    
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
    wire        fpu_mem_lwc1;
    wire        fpu_mem_swc1;
    wire        fpu_mem_lwc1_commit;
    wire        fpu_mem_ldc1_commit;
    wire [31:0] mem_fpu_store_data;
    // Phase B.5: delay-slot marker propagated with each instruction so an
    // exception on a delay-slot instruction can drive Cause.BD=1 and EPC=PC-4.
    wire        id_bd;
    reg  [31:0] id_delay_slot_next_pc_r;
    wire [31:0] id_delay_slot_next_pc = id_delay_slot_next_pc_r;
    wire        ex_bd;
    wire [31:0] ex_delay_slot_next_pc;
    wire        mem_bd;
    wire [31:0] mem_delay_slot_next_pc;
    wire        wb_bd;
    wire [31:0] wb_delay_slot_next_pc;
    wire        ex_cp0_we;
    wire        ex_is_eret;
    wire [1:0]  ex_mem_to_reg;
    wire [1:0]  mem_mem_to_reg;

    // Opt-in COP1 development slice. State is committed in ID because the
    // existing integer pipeline has no CP1 payload fields. MFC1/CFC1 use the
    // single integer register-file write port and wait on an older WB write.
    wire        fpu_id_cop1x = (id_inst[31:26] == 6'b010011);
    wire        fpu_id_cop1 = (id_inst[31:26] == 6'b010001);
    wire        fpu_id_valid = (`SOC_FPU_ENABLE != 0) &&
                               (fpu_id_cop1 || fpu_id_cop1x);
    wire        fpu_mem_id_valid = (`SOC_FPU_ENABLE != 0) &&
                                   ((id_inst[31:26] == 6'b110001) ||
                                    (id_inst[31:26] == 6'b111001) ||
                                    (id_inst[31:26] == 6'b110101) ||
                                    (id_inst[31:26] == 6'b111101));
    wire        fpu_id_mfc1 = fpu_id_cop1 && (id_inst[25:21] == 5'b00000);
    wire        fpu_id_cfc1 = fpu_id_cop1 && (id_inst[25:21] == 5'b00010);
    wire        fpu_id_mtc1 = fpu_id_cop1 && (id_inst[25:21] == 5'b00100);
    wire        fpu_id_ctc1 = fpu_id_cop1 && (id_inst[25:21] == 5'b00110);
    wire        fpu_id_arith = fpu_id_cop1x ||
                               (fpu_id_cop1 &&
                               ((id_inst[25:21] == 5'b10000) ||
                                (id_inst[25:21] == 5'b10001) ||
                                (id_inst[25:21] == 5'b10100)));
    wire        fpu_id_cond_move = fpu_id_cop1 &&
                                   (id_inst[5:0] == 6'h12 ||
                                    id_inst[5:0] == 6'h13);
    wire        fpu_id_cond_move_ok = !fpu_id_cond_move ||
                                      ((id_inst[5:0] == 6'h12) ?
                                       (id_val_rt == 32'd0) :
                                       (id_val_rt != 32'd0));
    wire        fpu_id_double = (fpu_id_cop1 &&
                                (id_inst[25:21] == 5'b10001)) ||
                                (fpu_id_cop1x && id_inst[0]);
    wire        fpu_id_double_result =
                         (fpu_id_cop1x && id_inst[0]) ||
                         (fpu_id_double && (id_inst[5:0] <= 6'h07)) ||
                               (fpu_id_double && (id_inst[5:0] == 6'h12 ||
                                                  id_inst[5:0] == 6'h13)) ||
                               (fpu_id_double && (id_inst[5:0] == 6'h15 ||
                                                  id_inst[5:0] == 6'h16)) ||
                               ((fpu_id_cop1 &&
                                 (id_inst[25:21] == 5'b10000 ||
                                 id_inst[25:21] == 5'b10100) &&
                                id_inst[5:0] == 6'h21));
    wire        fpu_id_gpr_write = fpu_id_mfc1 | fpu_id_cfc1;
    wire        fpu_rf_conflict = fpu_id_gpr_write && wb_reg_write;
    wire        id_fpu_unusable = (fpu_id_valid || fpu_mem_id_valid) && !cpu_cu1;
    // FCSR Enables[11:7] correspond to the primitive flag order
    // {invalid, div0, overflow, underflow, inexact}.  An enabled flag is a
    // precise FPE exception: the FPU result must not commit and CP0 receives
    // ExcCode 15 through the normal exception pipeline.
    reg  [31:0] fcsr;
    wire [4:0]  fpu_exception_flags;
    wire [4:0] fpu_enabled_flags = fpu_exception_flags & fcsr[11:7];
    wire       id_fpu_exception = (`SOC_FPU_ENABLE != 0) &&
                                  fpu_id_valid && !id_fpu_unusable &&
                                  (|fpu_enabled_flags);
    // LWC1 completes through the ordinary MEM response edge, while COP1
    // consumers read the FPR array combinationally in ID. Hold a dependent
    // COP1 instruction until the load has committed to avoid observing the
    // previous FPR value.
    wire        ex_fpu_word_load = (ex_inst[31:26] == 6'b110001) ||
                                    (ex_inst[31:26] == 6'b110101);
    wire        mem_fpu_word_load = (mem_inst[31:26] == 6'b110001) ||
                                     (mem_inst[31:26] == 6'b110101);
    wire        fpu_lwc1_hazard = fpu_id_valid &&
                                  ((ex_fpu_word_load &&
                                    (ex_inst[20:16] != 5'd0) &&
                                    ((ex_inst[20:16] == id_inst[15:11]) ||
                                     (ex_inst[20:16] == id_inst[20:16]))) ||
                                   (mem_fpu_word_load &&
                                    (mem_inst[20:16] != 5'd0) &&
                                    ((mem_inst[20:16] == id_inst[15:11]) ||
                                     (mem_inst[20:16] == id_inst[20:16]))));
    reg [31:0]  fpr [0:31];
    // FCSR condition-code layout: FCC0 is bit 23, FCC1..FCC7 are bits
    // 25..31 (bit 24 is reserved) in this vector order.  Keep the architectural selector local to
    // the decoder so all COP1 consumers use the same mapping.
    wire [7:0] fpu_conditions = {fcsr[31:25], fcsr[23]};
    reg [31:0]  fpu_double_low;
    integer     fpu_i;
    wire [4:0]  fpu_op = (fpu_id_cop1x &&
                          (id_inst[5:0] == 6'h20 || id_inst[5:0] == 6'h21)) ? 5'd25 :
                         (fpu_id_cop1x &&
                          (id_inst[5:0] == 6'h28 || id_inst[5:0] == 6'h29)) ? 5'd26 :
                         (fpu_id_cop1x &&
                          (id_inst[5:0] == 6'h30 || id_inst[5:0] == 6'h31)) ? 5'd27 :
                         (fpu_id_cop1x &&
                          (id_inst[5:0] == 6'h38 || id_inst[5:0] == 6'h39)) ? 5'd28 :
                         (id_inst[25:21] == 5'b10100 &&
                         id_inst[5:0] == 6'h20) ? 5'd9 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h20) ? 5'd15 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h21) ? 5'd16 :
                         (id_inst[25:21] == 5'b10100 &&
                          id_inst[5:0] == 6'h21) ? 5'd17 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h24) ? 5'd18 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h0c) ? 5'd19 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h0d) ? 5'd20 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h0e) ? 5'd21 :
                         (id_inst[25:21] == 5'b10001 &&
                          id_inst[5:0] == 6'h0f) ? 5'd22 :
                         (id_inst[5:0] == 6'h15) ? 5'd23 :
                         (id_inst[5:0] == 6'h16) ? 5'd24 :
                         ((id_inst[25:21] == 5'b10000 ||
                           id_inst[25:21] == 5'b10001) &&
                          (id_inst[5:0] == 6'h12 ||
                           id_inst[5:0] == 6'h13)) ? 5'd6 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h24) ? 5'd10 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h0c) ? 5'd11 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h0d) ? 5'd12 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h0e) ? 5'd13 :
                         (id_inst[25:21] == 5'b10000 &&
                          id_inst[5:0] == 6'h0f) ? 5'd14 :
                         (id_inst[5:0] <= 6'h07) ? {1'b0, id_inst[3:0]} :
                         ((fpu_id_cop1 && id_inst[5:0] >= 6'h30) ? 5'd8 : 5'd31);
    wire [31:0] fpu_result;
    wire [63:0] fpu_result_double;
    wire [31:0] fpu_result_word;
    wire        fpu_compare_true;
    wire [3:0]  fpu_compare_condition = id_inst[3:0];
    // COP1X arithmetic is fs * ft +/- fr; the encoding names these as
    // rd, rt, and rs respectively, with sa as fd.
    wire [4:0] fpu_a_index = id_inst[15:11];
    wire [4:0] fpu_b_index = id_inst[20:16];
    wire [4:0] fpu_c_index = fpu_id_cop1x ? id_inst[25:21] : id_inst[10:6];
    wire [63:0] fpu_a_double = {fpr[fpu_a_index + 1], fpr[fpu_a_index]};
    wire [63:0] fpu_b_double = {fpr[fpu_b_index + 1], fpr[fpu_b_index]};
    wire [31:0] fpu_c = fpr[fpu_c_index];
    wire [63:0] fpu_c_double = {fpr[fpu_c_index + 1], fpr[fpu_c_index]};
    mips_fpu u_mips_fpu (
        .op           (fpu_op),
        .a            (fpr[fpu_a_index]),
        .b            (fpr[fpu_b_index]),
        .result       (fpu_result),
        .compare_true (fpu_compare_true),
        .compare_condition(fpu_compare_condition),
        .fmt_double   (fpu_id_double),
        .rounding_mode(fcsr[1:0]),
        .a_double     (fpu_a_double),
        .b_double     (fpu_b_double),
        .c            (fpu_c),
        .c_double     (fpu_c_double),
        .result_double(fpu_result_double),
        .result_word  (fpu_result_word),
        .exception_flags(fpu_exception_flags)
    );
    wire fpu_id_commit = fpu_id_valid && !global_stall && !stall_req_id &&
                         !exception_flush && !ctx_restore_req &&
                         !id_fpu_unusable && !id_illegal_inst &&
                         !id_fpu_exception &&
                         fpu_id_cond_move_ok;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fcsr <= 32'd0;
            fpu_double_low <= 32'd0;
            for (fpu_i = 0; fpu_i < 32; fpu_i = fpu_i + 1)
                fpr[fpu_i] <= 32'd0;
        end else if (ctx_restore_req) begin
            fcsr <= ctx_restore_fcsr;
            fpu_double_low <= 32'd0;
            for (fpu_i = 0; fpu_i < 32; fpu_i = fpu_i + 1)
                fpr[fpu_i] <= ctx_restore_fpr[fpu_i*32 +: 32];
        end else if (mem_double_mem && (mem_inst[31:26] == 6'b110101) &&
                     !mem_double_phase && data_data_ok_current &&
                     !(data_bus_error_current === 1'b1) &&
                     !(data_cache_error_current === 1'b1) &&
                     !dmem_request_blocked) begin
            fpu_double_low <= mem_rdata_fmt;
        end else if (fpu_mem_lwc1_commit) begin
            // LWC1 is a normal word memory transaction; its architectural
            // destination is the FPR named by rt, not the GPR file.
            fpr[mem_inst[20:16]] <= mem_rdata_fmt;
        end else if (fpu_mem_ldc1_commit) begin
            fpr[mem_inst[20:16]] <= fpu_double_low;
            fpr[mem_inst[20:16] + 1'b1] <= mem_rdata_fmt;
        end else if (id_fpu_exception && fpu_id_valid && !global_stall &&
                     !stall_req_id && !exception_flush && !ctx_restore_req) begin
            // The operation is trapped before architectural FPR commit, but
            // the sticky flag and most-recent Cause field are still visible
            // to the FPE handler through CFC1.
            fcsr[6:2] <= fcsr[6:2] | fpu_exception_flags;
            fcsr[16:12] <= fpu_exception_flags;
        end else if (fpu_id_commit) begin
            if (fpu_id_mtc1)
                fpr[id_inst[15:11]] <= id_val_rt;
            else if (fpu_id_ctc1)
                fcsr <= id_val_rt;
            else if (fpu_id_arith) begin
                if (fpu_id_cop1 && id_inst[5:0] >= 6'h30) begin
                    case (id_inst[10:8])
                        3'd0: fcsr[23] <= fpu_compare_true;
                        3'd1: fcsr[25] <= fpu_compare_true;
                        3'd2: fcsr[26] <= fpu_compare_true;
                        3'd3: fcsr[27] <= fpu_compare_true;
                        3'd4: fcsr[28] <= fpu_compare_true;
                        3'd5: fcsr[29] <= fpu_compare_true;
                        3'd6: fcsr[30] <= fpu_compare_true;
                        3'd7: fcsr[31] <= fpu_compare_true;
                    endcase
                end
                else if (fpu_id_double_result) begin
                    fpr[id_inst[10:6]] <= fpu_result_double[31:0];
                    fpr[id_inst[10:6] + 1] <= fpu_result_double[63:32];
                end else if ((fpu_op >= 5'd10 && fpu_op <= 5'd14) ||
                             (fpu_op >= 5'd18 && fpu_op <= 5'd22))
                    fpr[id_inst[10:6]] <= fpu_result_word;
                else
                    fpr[id_inst[10:6]] <= fpu_result;
                // FCSR Flags[6:2] are sticky; Cause[16:12] describes the
                // exception from the most recent completed operation.
                // Precise FPE trap delivery, enable masking, and rounding
                // remain separate contracts.
                fcsr[6:2] <= fcsr[6:2] | fpu_exception_flags;
                fcsr[16:12] <= fpu_exception_flags;
            end
        end
    end

    wire [4:0]  rf_waddr_selected = fpu_id_gpr_write ? id_inst[20:16] : wb_waddr;
    wire [31:0] rf_wdata_selected = fpu_id_mfc1 ? fpr[id_inst[15:11]] :
                                    fpu_id_cfc1 ? fcsr : wb_wdata;
    // The nonblocking retirement FIFO keeps its control bundle registered,
    // while wb_valid is the one-cycle commit pulse.  Gate GPR writes with
    // that pulse or an older load/store control word will be replayed into
    // later instructions after the FIFO goes empty.
    wire        rf_we_selected = (fpu_id_gpr_write && !wb_reg_write) ?
                                 (!global_stall && !stall_req_id &&
                                  !exception_flush && !ctx_restore_req) :
                                 (wb_reg_write && wb_arch_valid &&
                                  !(wb_except_req && wb_arch_valid));

    wire id_is_rdhwr = (id_inst[31:26] == 6'b011111) &&
                       (id_inst[25:21] == 5'b00011) &&
                       ((id_inst[15:11] == 5'd0) || (id_inst[15:11] == 5'd1) ||
                        (id_inst[15:11] == 5'd2) || (id_inst[15:11] == 5'd3) ||
                        (id_inst[15:11] == 5'd29)) &&
                       (id_inst[5:0] == 6'b111011);

    // CP0 reads are serialized through the WB read-data mux.  Treat them as
    // a distinct one-entry resource so adjacent MFC0 instructions
    // cannot observe the previous instruction's CP0 address/selector.
    wire cp0_read_hazard = id_is_mfc0 &&
                           ((ex_mem_to_reg == 2'b11) ||
                            (mem_mem_to_reg == 2'b11) ||
                            (wb_mem_to_reg == 2'b11));
    wire nb_load_use_hazard = (`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                               id_control_valid &&
                               ((nb_load_busy[0] && (nb_load_rd[0] != 0) &&
                                 ((nb_load_rd[0] == id_rs_addr) ||
                                  (nb_load_rd[0] == id_rt_addr))) ||
                                (nb_load_busy[1] && (nb_load_rd[1] != 0) &&
                                 ((nb_load_rd[1] == id_rs_addr) ||
                                  (nb_load_rd[1] == id_rt_addr))) ||
                                (nb_load_busy[2] && (nb_load_rd[2] != 0) &&
                                 ((nb_load_rd[2] == id_rs_addr) ||
                                  (nb_load_rd[2] == id_rt_addr))) ||
                                (nb_load_busy[3] && (nb_load_rd[3] != 0) &&
                                 ((nb_load_rd[3] == id_rs_addr) ||
                                  (nb_load_rd[3] == id_rt_addr))));
    assign stall_req_id = stall_req_id_raw | fpu_rf_conflict |
                          fpu_lwc1_hazard |
                          cp0_read_hazard |
                          nb_load_use_hazard;
    
    mips_id_stage u_mips_id_stage (
        .clk           (clk),
        .rst_n         (rst_n),
        .fpu_condition (fpu_conditions),
        .fpu_branch_invert (id_fpu_branch_invert),
        .inst          (id_inst),
        .pc_plus_4     (id_pc_plus_4),
        
        // Writeback port
        .rf_waddr      (rf_waddr_selected),
        .rf_wdata      (rf_wdata_selected),
        .rf_we         (rf_we_selected),
        .srs_current_set(srs_current_set),
        .srs_previous_set(srs_previous_set),
        .srs_shadow_we(srs_shadow_we),
        .srs_shadow_wset(srs_shadow_wset),
        .srs_shadow_waddr(srs_shadow_waddr),
        .srs_shadow_wdata(srs_shadow_wdata),
        .ctx_save_req  (ctx_save_req),
        .ctx_save_done (),
        .ctx_save_data (ctx_save_gpr),
        .ctx_save_srs_data (ctx_save_srs_gpr),
        .ctx_restore_req(ctx_restore_req),
        .ctx_restore_data(ctx_restore_gpr),
        .ctx_restore_srs_data(ctx_restore_srs_gpr),
        .ctx_restore_set(ctx_restore_set),
        .ctx_restore_done(),
        
        // Forwarding
        .fw_ex_we      (ex_reg_write),
        .fw_ex_waddr   (ex_waddr),
        .fw_ex_val     (ex_out),
        .fw_mem_we     (mem_reg_write),
        .fw_mem_waddr  (mem_waddr),
        .fw_mem_val    (mem_mem_read ? mem_rdata_fmt : mem_ex_out),
        .fw_wb_we      (rf_we_selected),
        .fw_wb_waddr   (rf_waddr_selected),
        .fw_wb_val     (rf_wdata_selected),
        
        // Hazard detection
        .ex_mem_read   (ex_mem_read),
        .ex_waddr      (ex_waddr),
        .mem_mem_read  (mem_mem_read),
        .ex_mem_to_reg (ex_mem_to_reg),
        .mem_mem_to_reg(mem_mem_to_reg),
        .nb_pending_reg(nb_pending_reg),
        .stall_req     (stall_req_id_raw),
        
        // Branch & Jump
        .branch_taken  (id_branch_taken),
        .branch_likely_annul(id_branch_likely_annul),
        .branch_likely_taken(id_branch_likely_taken),
        .branch_target (id_branch_target),
        .jump_taken    (id_jump_taken),
        .jump_target   (id_jump_target),
        .control_valid (id_control_valid),
        .control_taken (id_control_taken),
        .control_target(id_control_target),
        .control_type  (id_control_type),
        
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
        .is_break      (id_is_break),
        .is_di        (id_is_di),
        .is_ei        (id_is_ei),
        .is_wait      (id_is_wait),
        .is_trap       (id_is_trap),
        .trap_op       (id_trap_op),
        .tlb_op        (id_tlb_op)
    );

    // Phase B.4: privileged instruction detection + CU0 gate. If the current
    // ID instruction is MTC0/MFC0/ERET/TLB* and the effective mode is user-mode
    // without Status.CU0 override, raise Coprocessor Unusable (ExcCode 11).
    wire id_is_priv     = id_cp0_we | id_is_mfc0 | id_is_eret | id_is_wait | (|id_tlb_op);
    wire id_rdhwr_allowed = id_is_rdhwr && cpu_hwrena[id_inst[15:11]];
    wire id_cpu_unusable = id_is_priv & ~cpu_kernel_mode & ~cpu_cu0 &
                           ~id_rdhwr_allowed;

    wire id_trap_imm = (id_inst[31:26] == 6'b000001) && (id_trap_op >= 4'd6);
    wire [31:0] id_trap_rhs = id_trap_imm ? id_imm_ext : id_val_rt;
    wire id_trap_taken = id_is_trap &&
                         ((id_trap_op == 4'd0 || id_trap_op == 4'd6) ? ($signed(id_val_rs) >= $signed(id_trap_rhs)) :
                          (id_trap_op == 4'd1 || id_trap_op == 4'd7) ? (id_val_rs >= id_trap_rhs) :
                          (id_trap_op == 4'd2 || id_trap_op == 4'd8) ? ($signed(id_val_rs) < $signed(id_trap_rhs)) :
                          (id_trap_op == 4'd3 || id_trap_op == 4'd9) ? (id_val_rs < id_trap_rhs) :
                          (id_trap_op == 4'd4 || id_trap_op == 4'd10) ? (id_val_rs == id_trap_rhs) :
                                                                        (id_val_rs != id_trap_rhs));

    // Exception priority at ID: upstream (IF-origin) > CpU > BREAK > TRAP > SYSCALL > RI.
    wire id_except_req_out = id_except_req_in | id_illegal_inst | id_is_syscall | id_is_break | id_trap_taken
                           | id_cpu_unusable | id_fpu_unusable | id_fpu_exception;
    wire [4:0] id_except_code_out = id_except_req_in ? id_except_code_in :
                                    (id_cpu_unusable || id_fpu_unusable) ? 5'h0B : // CpU
                                    id_fpu_exception ? 5'h0F : // FPE
                                    id_is_break     ? 5'h09 :   // Breakpoint
                                    id_trap_taken   ? 5'h0D :   // Trap
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || if_id_flush) begin
            id_delay_slot_next_pc_r <= 32'd0;
        end else if (!global_stall) begin
            if (id_branch_taken || id_jump_taken) begin
                id_delay_slot_next_pc_r <= id_control_taken ? id_control_target :
                                           id_pc_plus_4 + 32'd4;
            end else begin
                id_delay_slot_next_pc_r <= 32'd0;
            end
        end
    end
    
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
        .id_inst        (id_inst),
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
        .id_delay_slot_next_pc(id_delay_slot_next_pc),
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
        .ex_inst        (ex_inst),
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
        .ex_delay_slot_next_pc(ex_delay_slot_next_pc),
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
        .flush       (exception_flush | ctx_restore_req),
        .op_a        (ex_op_a),
        .op_b        (ex_op_b),
        .sa          (ex_sa),
        .msbd        (ex_rd_addr),
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
    wire [31:0] ex_fpu_store_data =
                ((`SOC_FPU_ENABLE != 0) && (ex_inst[31:26] == 6'b111001)) ?
                fpr[ex_inst[20:16]] : ex_val_rt;
    wire [31:0] mem_pc_plus_8;
    wire        mem_mem_write;
    wire [2:0]  mem_mem_op;
    wire [4:0]  mem_rd_addr;
    wire [4:0]  mem_cp0_raddr;

    // Only cacheable loads use the decoupled issue path.  MMU faults,
    // uncached accesses, stores and CACHE operations remain blocking.
    wire [31:0] mem_access_addr = mem_ex_out + (mem_double_phase ? 32'd4 : 32'd0);
    wire mem_double_align_fault = mem_double_mem && (mem_ex_out[2:0] != 3'b000);
    wire mem_enable_nb_load = (`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_ROB_FIFO_ENABLE != 0) &&
                              (mem_inst[31:26] != 6'b110001) &&
                              !mem_double_mem &&
                              !data_uncacheable &&
                              // The integrated prototype L1 is limited to
                              // the 64KB on-chip SRAM window. Other physical
                              // regions use the blocking/legacy response
                              // contract and must not allocate tagged ROB
                              // entries.
                              (data_addr[31:16] == 16'h0000);

    assign dmem_translate_req = ((mem_mem_read | mem_mem_write) & ~mem_done) |
                                (mem_cache_op_valid & ~mem_done);
    assign dmem_translation_fault = (~mmu_d_ok & dmem_translate_req &
                                     !hw_walker_d_miss) || hw_walker_d_fault;
    // A D-side walker miss must hold the MEM operation without exposing the
    // untranslated address to the data fabric.  The architectural exception
    // remains deferred until the walker returns a latched fault.
    assign dmem_request_blocked = dmem_translation_fault | hw_walker_d_miss;
    assign fpu_mem_lwc1 = (`SOC_FPU_ENABLE != 0) &&
                          mem_mem_read && (mem_inst[31:26] == 6'b110001);
    assign fpu_mem_swc1 = (`SOC_FPU_ENABLE != 0) &&
                          mem_mem_write && (mem_inst[31:26] == 6'b111001);
    assign fpu_mem_lwc1_commit = fpu_mem_lwc1 && data_data_ok_current &&
                                 !(data_bus_error_current === 1'b1) &&
                                 !(data_cache_error_current === 1'b1) &&
                                 !dmem_request_blocked;
    assign fpu_mem_ldc1_commit = mem_double_mem &&
                                 (mem_inst[31:26] == 6'b110101) &&
                                 mem_double_phase && data_data_ok_current &&
                                 !(data_bus_error_current === 1'b1) &&
                                 !(data_cache_error_current === 1'b1) &&
                                 !dmem_request_blocked;
    assign mem_fpu_store_data = fpu_mem_swc1 ?
                                fpr[mem_inst[20:16]] :
                                (mem_double_mem && (mem_inst[31:26] == 6'b111101) ?
                                 (mem_double_phase ? fpr[mem_inst[20:16] + 1'b1] :
                                                      fpr[mem_inst[20:16]]) : mem_val_rt);
    
    mips_ex_mem_reg u_mips_ex_mem_reg (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (global_stall),
        .flush           (flush_ex_mem),
        .dmem_addr_ok    (data_addr_ok_effective),
        .dmem_data_ok    (data_data_ok_current),
        .enable_nonblocking_load(mem_enable_nb_load),
        .cache_op_done   (data_cache_op_done),
        
        .ex_out          (ex_out),
        .ex_val_rt       (ex_fpu_store_data),
        .ex_pc_plus_8    (ex_pc_plus_8),
        .ex_inst         (ex_inst),
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
        .ex_delay_slot_next_pc(ex_delay_slot_next_pc),
        .ex_mem_read     (ex_mem_read),
        .ex_mem_write    (ex_mem_write),
        .ex_mem_op       (ex_mem_op),
        .ex_mem_to_reg   (ex_mem_to_reg),
        .ex_cache_op_valid(ex_cache_op_valid),
        .ex_cache_op     (ex_cache_op),
        
        .mem_ex_out      (mem_ex_out),
        .mem_val_rt      (mem_val_rt),
        .mem_pc_plus_8   (mem_pc_plus_8),
        .mem_inst        (mem_inst),
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
        .mem_delay_slot_next_pc(mem_delay_slot_next_pc),
        .mem_mem_read    (mem_mem_read),
        .mem_mem_write   (mem_mem_write),
        .mem_mem_op      (mem_mem_op),
        .mem_mem_to_reg  (mem_mem_to_reg),
        .mem_cache_op_valid(mem_cache_op_valid),
        .mem_cache_op    (mem_cache_op),
        .mem_done        (mem_done),
        .mem_double_phase(mem_double_phase)
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
        .mem_ex_out      (mem_access_addr),
        .mem_val_rt      (mem_fpu_store_data),
        .mem_read        (mem_mem_read),
        .mem_write       (mem_mem_write),
        .mem_op          (mem_mem_op),
        .mem_done        (mem_done),
        .enable_nonblocking_load(mem_enable_nb_load),
        .mem_cache_op_valid(mem_cache_op_valid),
        .mem_cache_op    (mem_cache_op),
        
        .dmem_rdata      (data_rdata),
        .dmem_addr       (mem_vaddr),
        .dmem_wdata      (data_wdata),
        .dmem_we         (data_we_raw),
        .dmem_be         (data_be),
        .dmem_en         (data_req_raw),
        .dmem_addr_ok    (data_addr_ok_effective),
        .dmem_data_ok    (data_data_ok_current),
        .translation_fault(dmem_request_blocked | mem_double_align_fault),
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
        end else if (ctx_restore_req) begin
            // A reservation belongs to the executing thread, not to the
            // destination task. Never carry LL/SC state across a switch.
            ll_reservation_valid <= 1'b0;
            ll_reservation_addr  <= 32'd0;
        end else if (exception_flush) begin
            // An exception boundary terminates the atomic sequence.  This
            // prevents an SC after SYSCALL/interrupt/ERET from inheriting an
            // LL reservation created before the handler ran.
            ll_reservation_valid <= 1'b0;
            ll_reservation_addr  <= 32'd0;
        end else if (coh_snoop_valid &&
                     (ll_reservation_addr[31:5] == coh_snoop_addr[31:5])) begin
            ll_reservation_valid <= 1'b0;
        end else if (data_data_ok_current) begin
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
    wire        mem_mmu_fault      = dmem_translation_fault;
    wire [4:0]  mem_mmu_fault_code = hw_walker_d_fault ?
                                     (mem_mem_write ? 5'h03 : 5'h02) :
                                     (mmu_d_fault_type == 3'b010) ? 5'h03 :  // TLBS
                                     (mmu_d_fault_type == 3'b011) ? 5'h01 :  // Mod
                                     (mmu_d_fault_type == 3'b110) ? 5'h18 :  // MCheck
                                     (mmu_d_fault_type == 3'b100) ? 5'h04 :  // AdEL (user kseg)
                                     (mmu_d_fault_type == 3'b101) ? 5'h05 :  // AdES (user kseg)
                                                                     5'h02;  // TLBL
    wire mem_mmu_refill = mem_mmu_fault & !hw_walker_d_fault &
                          ((mmu_d_fault_type == 3'b001) || (mmu_d_fault_type == 3'b010)) &
                          ~mmu_dlookup_hit;
    wire mem_bus_fault      = data_req & data_data_ok_current & (data_bus_error_current === 1'b1);
    wire mem_cache_fault    = data_req & data_data_ok_current & (data_cache_error_current === 1'b1);
    wire mem_cache_op_fault_seen = mem_cache_op_fault |
                                   (data_cache_op_valid & data_cache_op_done &
                                    (data_cache_op_error === 1'b1));
    wire mem_except_req_out  = mem_except_req | mem_mmu_fault | mem_double_align_fault | mem_cache_fault |
                               mem_cache_op_fault_seen | mem_bus_fault
                             | mem_adel_exception | mem_ades_exception;
    wire [4:0] mem_except_code_out = mem_except_req      ? mem_except_code
                                   : mem_mmu_fault       ? mem_mmu_fault_code
                                   : mem_double_align_fault ? (mem_mem_write ? 5'h05 : 5'h04)
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
    wire        wb_mem_read_trace;
    wire        wb_mem_write_trace;
    wire [2:0]  wb_mem_op_trace;
    reg  [31:0] completed_load_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            completed_load_data <= 32'd0;
        else if (data_data_ok_current && mem_mem_read)
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
    // The opt-in nonblocking path reserves the full architectural commit
    // depth before a late-response cache is connected.  The blocking default
    // remains DEPTH=1 and retains its cycle-for-cycle retirement behavior.
    localparam integer ROB_DEPTH = ((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                                    (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                                    (`SOC_ROB_FIFO_ENABLE != 0)) ? 4 : 1;
    // Couple a cacheable load address handshake to ROB capacity. A load may
    // be accepted while an unrelated front-end stall is active, but the ROB
    // must be allowed to allocate that same request. Conversely, a full ROB
    // must hide addr_ok from MEM/cache so a response cannot arrive for a
    // nonexistent slot.
    wire nb_rob_issue = mem_enable_nb_load && data_req_raw &&
                        data_addr_ok_effective && rob_alloc_ready;
    // A blocking response is a one-cycle architectural event.  It must be
    // captured even when an unrelated IF/exception stall is asserted in the
    // same cycle; otherwise the cache drops data_ok and MEM/WB later samples
    // an invalid bus value.  Nonblocking issue/ROB backpressure retains its
    // original priority.
    wire blocking_response_commit = data_data_ok_current &&
                                    (mem_mem_read || mem_mem_write);
    wire rob_stall = global_stall && !rob_head_ready && !nb_rob_issue &&
                     !blocking_response_commit;
    wire nb_rob_block = mem_enable_nb_load && data_req_raw && !rob_alloc_ready;
    assign data_req = data_req_raw && !nb_rob_block;
    assign data_addr_ok_effective = data_addr_ok && !nb_rob_block;
    // A nonblocking load must not occupy a ROB slot until its cache request
    // has actually handshaken.  `mem_done` is the legacy MEM-stage completion
    // signal and may be asserted while the cache is still backpressuring the
    // request; admitting that bubble creates an unmatchable, permanently
    // unready ROB entry.  Faulted requests are admitted so exception ordering
    // remains precise.
    wire nb_load_alloc_eligible = dmem_translation_fault ||
                                  mem_adel_exception || mem_ades_exception ||
                                  (data_req && data_addr_ok_effective);
    // The FIFO must not admit a blocking/uncached load at address acceptance:
    // its data is not available until the later data_ok edge, and no tagged
    // response will ever complete that entry.  Nonblocking cacheable loads
    // are the one exception: their address handshake allocates an unready
    // entry which is completed by the tagged response path.
    // This must match the advance condition in mips_ex_mem_reg. In
    // particular, an IF-side stall can hold EX/MEM while the FIFO head is
    // ready; allocating the held bundle again would create duplicate retire
    // records and duplicate architectural writes. A tagged nonblocking load
    // is the one intentional exception: its address handshake transfers the
    // instruction to the ROB before the late data response arrives.
    wire mem_pipeline_advance = (!global_stall_pre_rob) ||
                                (mem_enable_nb_load && mem_mem_read &&
                                 !mem_done && data_addr_ok_effective);
    wire rob_alloc_valid = (mem_pc_plus_8 >= 32'd8) && mem_pipeline_advance &&
                           (mem_enable_nb_load && mem_mem_read ?
                            nb_load_alloc_eligible :
                            (mem_mem_read ?
                             (mem_done || data_data_ok_current ||
                              dmem_translation_fault || mem_adel_exception ||
                              mem_ades_exception) :
                             ((!mem_mem_write) || mem_done ||
                              data_data_ok_current || dmem_translation_fault ||
                              mem_adel_exception || mem_ades_exception)));
    wire rob_ready_at_alloc = !mem_mem_read ||
                              ((!mem_enable_nb_load) && data_data_ok_current) ||
                              mem_done ||
                              dmem_translation_fault || mem_adel_exception;
    wire rob_complete_valid = (`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_ROB_FIFO_ENABLE != 0) && data_data_ok &&
                              data_resp_id[3];
    wire [1:0] rob_complete_tag = data_resp_id[1:0];
    wire nb_load_alloc = (`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                         (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                         (`SOC_ROB_FIFO_ENABLE != 0) &&
                         mem_enable_nb_load && mem_mem_read && data_req &&
                         data_addr_ok_effective && (mem_waddr != 0);

    // Track only loads that have left MEM before their data response. The
    // scoreboard is indexed by the same ROB tag carried on the cache request;
    // this blocks dependent ID instructions without stalling independent work.
    integer nb_load_i;
    reg [31:0] nb_pending_reg_q;
    assign nb_pending_reg = nb_pending_reg_q;

    integer nb_pending_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_mem_wb) begin
            nb_pending_reg_q <= 32'd0;
        end else begin
            if (wb_valid && wb_reg_write && (wb_waddr != 5'd0))
                nb_pending_reg_q[wb_waddr] <= 1'b0;
            if (rob_alloc_valid && rob_alloc_ready && !rob_stall &&
                mem_reg_write && (mem_waddr != 5'd0))
                nb_pending_reg_q[mem_waddr] <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_mem_wb) begin
            nb_load_busy <= 4'b0;
            for (nb_load_i = 0; nb_load_i < 4; nb_load_i = nb_load_i + 1)
                nb_load_rd[nb_load_i] <= 5'd0;
        end else begin
            // The FIFO is the source of truth for outstanding tagged loads.
            // Clear stale slot bits before processing a same-cycle allocation;
            // the allocation update below then wins for a genuinely new load.
            if (!rob_busy)
                nb_load_busy <= 4'b0;
            // A response makes the entry ready, but it is not architectural
            // state yet. Keep interrupts behind the FIFO retirement edge so
            // an exception flush cannot discard a completed load before WB.
            // The scoreboard is keyed by the ROB slot, so retirement of
            // that slot is the authoritative clear event.  Do not depend on
            // the delayed MEM-read trace bit: at a wrap/reuse boundary that
            // bit can describe the following bubble while the tag has
            // already retired, leaving a stale dependency that deadlocks ID.
            if (wb_valid)
                nb_load_busy[rob_retire_tag] <= 1'b0;
            if (nb_load_alloc) begin
                nb_load_busy[rob_alloc_tag] <= 1'b1;
                nb_load_rd[rob_alloc_tag] <= mem_waddr;
            end
            // Once the FIFO is empty there cannot be an outstanding tagged
            // load.  This also closes the same-cycle retire/tag-reuse corner:
            // a stale scoreboard bit must not hold the whole front end after
            // its ROB entry has already retired.
        end
    end
    assign rob_backpressure = (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                              (`SOC_ROB_FIFO_ENABLE != 0) &&
                              rob_alloc_valid && !rob_alloc_ready;
    assign data_req_id = ((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                          (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
                          (`SOC_ROB_FIFO_ENABLE != 0) &&
                          mem_enable_nb_load && mem_mem_read && data_req) ?
                         {1'b1, 1'b0, rob_alloc_tag} : 4'd0;

    generate
    if ((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
        (`SOC_L1_NONBLOCKING_ENABLE != 0) &&
        (`SOC_ROB_FIFO_ENABLE != 0)) begin : g_fifo_rob
    mips_rob_fifo #(.DEPTH(ROB_DEPTH), .READY_AT_ALLOC(1'b1)) u_mips_rob (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (rob_stall),
        .flush           (flush_mem_wb),
        .complete_valid  (rob_complete_valid),
        .complete_tag    (rob_complete_tag),
        .complete_rdata  (data_rdata),
        .complete_error  (data_bus_error | data_cache_error),
        .mem_alloc_valid (rob_alloc_valid),
        .mem_ready_at_alloc(rob_ready_at_alloc),

        .mem_rdata_fmt   (mem_rdata_fmt),
        .mem_ex_out      (mem_ex_out_wb),
        .mem_pc_plus_8   (mem_pc_plus_8),
        .mem_inst        (mem_inst),
        .mem_val_rt      (mem_val_rt),
        .mem_mem_read    (mem_mem_read),
        .mem_mem_write   (mem_mem_write),
        .mem_mem_op      (mem_mem_op),
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
        .mem_delay_slot_next_pc(mem_delay_slot_next_pc),
        .mem_mem_to_reg  (mem_mem_to_reg),
        
        .wb_rdata_fmt    (wb_rdata_fmt),
        .wb_ex_out       (wb_ex_out),
        .wb_pc_plus_8    (wb_pc_plus_8),
        .wb_valid        (wb_valid),
        .wb_inst         (wb_inst),
        .wb_val_rt       (wb_val_rt),
        .wb_mem_read     (wb_mem_read_trace),
        .wb_mem_write    (wb_mem_write_trace),
        .wb_mem_op       (wb_mem_op_trace),
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
        .wb_delay_slot_next_pc(wb_delay_slot_next_pc),
        .wb_mem_to_reg   (wb_mem_to_reg),
        .alloc_tag       (rob_alloc_tag),
        .alloc_ready     (rob_alloc_ready),
        .head_ready      (rob_head_ready),
        .busy            (rob_busy),
        .wb_tag          (rob_retire_tag)
    );
    end else begin : g_legacy_rob
    assign rob_alloc_tag = 2'd0;
    assign rob_alloc_ready = 1'b1;
    assign rob_head_ready = 1'b0;
    mips_rob #(.DEPTH(ROB_DEPTH)) u_mips_rob (
        .clk(clk), .rst_n(rst_n), .stall(rob_stall), .flush(flush_mem_wb),
        .mem_rdata_fmt(mem_rdata_fmt), .mem_ex_out(mem_ex_out_wb),
        .mem_pc_plus_8(mem_pc_plus_8), .mem_inst(mem_inst), .mem_val_rt(mem_val_rt),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write), .mem_mem_op(mem_mem_op),
        .mem_waddr(mem_waddr), .mem_rd_addr(mem_rd_addr), .mem_cp0_raddr(mem_cp0_raddr),
        .mem_cp0_sel(mem_cp0_sel), .mem_reg_write(mem_reg_write), .mem_cp0_we(mem_cp0_we),
        .mem_is_eret(mem_is_eret), .mem_tlb_op(mem_tlb_op),
        .mem_except_req(mem_except_req_out), .mem_except_code(mem_except_code_out),
        .mem_except_is_data(mem_except_is_data_out),
        .mem_except_is_tlb_refill(mem_except_is_tlb_refill_out), .mem_bd(mem_bd),
        .mem_delay_slot_next_pc(mem_delay_slot_next_pc), .mem_mem_to_reg(mem_mem_to_reg),
        .wb_rdata_fmt(wb_rdata_fmt), .wb_ex_out(wb_ex_out), .wb_pc_plus_8(wb_pc_plus_8),
        .wb_inst(wb_inst), .wb_val_rt(wb_val_rt), .wb_mem_read(wb_mem_read_trace),
        .wb_mem_write(wb_mem_write_trace), .wb_mem_op(wb_mem_op_trace), .wb_valid(wb_valid),
        .wb_waddr(wb_waddr), .wb_rd_addr(wb_rd_addr), .wb_cp0_raddr(wb_cp0_raddr),
        .wb_cp0_sel(wb_cp0_sel), .wb_reg_write(wb_reg_write), .wb_cp0_we(wb_cp0_we),
        .wb_is_eret(wb_is_eret), .wb_tlb_op(wb_tlb_op), .wb_except_req(wb_except_req),
        .wb_except_code(wb_except_code), .wb_except_is_data(wb_except_is_data),
        .wb_except_is_tlb_refill(wb_except_is_tlb_refill), .wb_bd(wb_bd),
        .wb_delay_slot_next_pc(wb_delay_slot_next_pc), .wb_mem_to_reg(wb_mem_to_reg)
    );
    end
    endgenerate
    
    // =========================================================================
    // Write Back (WB) Stage
    // =========================================================================
    wire [31:0] cp0_rdata;
    wire wb_di = wb_arch_valid && wb_reg_write && (wb_mem_to_reg == 2'b11) &&
                 (wb_inst[31:26] == 6'b010000) &&
                 (wb_inst[25:21] == 5'b01011) &&
                 (wb_inst[15:11] == 5'd12) &&
                 (wb_inst[10:6] == 5'd0) && !wb_inst[5];
    wire wb_ei = wb_arch_valid && wb_reg_write && (wb_mem_to_reg == 2'b11) &&
                 (wb_inst[31:26] == 6'b010000) &&
                 (wb_inst[25:21] == 5'b01011) &&
                 (wb_inst[15:11] == 5'd12) &&
                 (wb_inst[10:6] == 5'd0) && wb_inst[5];
    // WRPGPR has no ordinary GPR destination. Commit its source value to the
    // bank selected by SRSCtl.PSS at the same architectural WB edge.
    assign srs_shadow_we = (`SOC_SRS_ENABLE != 0) && wb_arch_valid &&
                           !wb_except_req &&
                           (wb_inst[31:26] == 6'b010000) &&
                           (wb_inst[25:21] == 5'b01110) &&
                           (wb_inst[10:6] == 5'd0) &&
                           (wb_inst[5:0] == 6'd0);
    
    // The retirement buffer already owns the formatted load value for both
    // blocking and tagged nonblocking paths. A separate completion register
    // can be overwritten by the next load before the older WB entry consumes
    // it, which aliases adjacent LB/LBU/LH/LHU results.
    wire [31:0] wb_rdata_selected = wb_rdata_fmt;

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
    wire [31:0] wb_next_pc = (wb_except_req && wb_arch_valid) ? exception_vector :
                             ((wb_is_eret && wb_arch_valid) ? epc_out :
                              (wb_bd && wb_delay_slot_next_pc != 32'd0 ?
                               wb_delay_slot_next_pc : wb_pc + 32'd4));
    
    wire [31:0] oldest_flushed_pc = 
        (mem_pc_plus_8 != 32'd0) ? mem_pc :
        (ex_pc_plus_8  != 32'd0) ? ex_pc :
        (id_pc_plus_4  != 32'd0) ? id_pc :
        if_pc_plus_4 - 32'd4;
        
    // An interrupt accepted while the core is suspended by WAIT is taken
    // after WAIT has retired.  Save the sequential PC so ERET resumes at the
    // instruction following WAIT instead of re-executing it forever.
    wire [31:0] wait_interrupt_epc = wait_resume_pc;
    wire [31:0] except_pc = sim_exception_active ? inst_addr :
                             ((interrupt_accept && wait_state) ?
                              wait_interrupt_epc :
                             ((wb_except_req && wb_arch_valid) ? wb_pc : oldest_flushed_pc));
    // Phase B.3.d: BadVAddr source. MEM-side faults (is_data=1) latch the data
    // address that reached MEM (wb_ex_out is the pipelined mem_ex_out); IF-side
    // address exceptions use the held faulting fetch VA.
    wire wb_if_address_exception = !wb_except_is_data &&
                                   ((wb_except_code == 5'h02) ||
                                    (wb_except_code == 5'h03) ||
                                    (wb_except_code == 5'h04));
    wire [31:0] bad_vaddr = wb_except_is_data ? wb_ex_out :
                            (wb_if_address_exception && if_fault_pending_q ?
                             if_fault_vaddr_q : except_pc);
    mips_cp0 #(.ENABLE_VEIC(ENABLE_VEIC), .CPUNUM(CPUNUM)) u_mips_cp0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .hw_int       (ext_int), // Connect hardware interrupt
        .we           (wb_cp0_we && wb_arch_valid &&
                       !(wb_except_req && wb_arch_valid)),
        .waddr        (wb_rd_addr),
        .wsel         (wb_cp0_sel),
        .wdata        (wb_ex_out),
        .raddr        (wb_cp0_raddr),
        .rsel         (wb_cp0_sel),
        .rdata        (cp0_rdata),
        .tlb_op       (wb_arch_valid ? wb_tlb_op : 3'd0),
        .cache_op_done(data_cache_op_done),
        .cache_op     (data_cache_op),
        .cache_tag_rdata(data_cache_tag_rdata),
        .except_req   (effective_except_req | interrupt_accept),
        .except_code  (effective_except_req ? effective_except_code : 5'h00), // 0x00 for INT
        .except_ce    (effective_except_req ? effective_except_ce : 2'b00),
        .except_pc    (except_pc),
        .except_bd    (wb_bd && wb_arch_valid),
        .eret         (wb_is_eret && wb_arch_valid),
        .di           (wb_di),
        .ei           (wb_ei),
        .bad_vaddr    (bad_vaddr),
        .lladdr_in    (ll_reservation_addr),
        .ctx_save_req (ctx_save_req),
        .ctx_save_done(),
        .ctx_save_status(ctx_save_status),
        .ctx_save_asid(ctx_save_asid),
        .ctx_save_srsctl(ctx_save_srsctl),
        .ctx_restore_req(ctx_restore_req),
        .ctx_restore_status(ctx_restore_status),
        .ctx_restore_asid(ctx_restore_asid),
        .ctx_restore_srsctl(ctx_restore_srsctl),
        .ctx_restore_done(),
        .interrupt_srs_set(cp0_vint_srs_set),
        .interrupt_accept_in(interrupt_accept),
        .hw_tlb_wr_en(hw_tlb_wr_en),
        .hw_tlb_wr_index(hw_tlb_wr_index),
        .hw_tlb_wr_vpn2(ptw_va_q[31:13]),
        .hw_tlb_wr_asid(cp0_asid),
        .hw_tlb_wr_mask(`SOC_HARDWARE_WALKER_PAGE_MASK),
        .hw_tlb_wr_entrylo0(hw_tlb_entrylo0),
        .hw_tlb_wr_entrylo1(hw_tlb_entrylo1),
        .hw_tlb_wr_ready(hw_tlb_wr_ready),
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
        .vint_srs_set_out (cp0_vint_srs_set),
        .kernel_mode  (cpu_kernel_mode),
        .cu0_enable   (cpu_cu0),
        .cu1_enable   (cpu_cu1),
        .exl_out      (cp0_exl),
        .hwrena_out   (cpu_hwrena),

        // MMU pass-through
        .cp0_asid_out       (cp0_asid),
        .cp0_config_k0_out  (cp0_config_k0),
        .taglo_out          (cp0_taglo),
        .taghi_out          (cp0_taghi),
        .srs_current_set_out(srs_current_set),
        .srs_previous_set_out(srs_previous_set),
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

    assign ctx_save_done = ctx_save_req;
    assign ctx_restore_ack = ctx_restore_req;

    genvar fpu_ctx_i;
    generate
        for (fpu_ctx_i = 0; fpu_ctx_i < 32; fpu_ctx_i = fpu_ctx_i + 1) begin : gen_fpu_context
            assign ctx_save_fpr[fpu_ctx_i*32 +: 32] = fpr[fpu_ctx_i];
        end
    endgenerate
    assign ctx_save_fcsr = fcsr;

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

    mips_page_table_walker #(.PAGE_MASK(`SOC_HARDWARE_WALKER_PAGE_MASK)) u_hardware_walker (
        .clk(clk), .rst_n(rst_n),
        .req_valid(ptw_req_valid), .req_ready(ptw_req_ready),
        .ptbr(hardware_walker_ptbr), .va(ptw_req_va),
        .access(ptw_req_access), .user_mode(ptw_req_user),
        .mem_valid(ptw_mem_valid), .mem_addr(ptw_mem_addr),
        .mem_ready(ptw_mem_ready), .mem_rdata(ptw_mem_rdata),
        .mem_error(ptw_mem_error), .resp_valid(ptw_resp_valid),
        .pa(ptw_pa), .fault_valid(ptw_fault_i),
        .fault_code(ptw_fault_code_i), .leaf_pte(ptw_leaf_pte)
    );

    assign ptw_fault_valid = ptw_resp_valid && ptw_fault_i;
    assign ptw_fault_code = ptw_fault_code_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptw_busy <= 1'b0;
            ptw_refill_pending <= 1'b0;
            ptw_fault_pending <= 1'b0;
            ptw_fault_is_data <= 1'b0;
            ptw_va_q <= 32'd0;
        end else begin
            if (ptw_req_valid && ptw_req_ready) begin
                ptw_busy <= 1'b1;
                ptw_va_q <= ptw_req_va;
            end
            if (ptw_busy && ptw_resp_valid) begin
                if (ptw_fault_i) begin
                    ptw_busy <= 1'b0;
                    ptw_fault_pending <= 1'b1;
                    ptw_fault_is_data <= hw_walker_d_miss;
                end else begin
                    ptw_refill_pending <= 1'b1;
                end
            end
            if (ptw_refill_pending && hw_tlb_wr_ready) begin
                ptw_refill_pending <= 1'b0;
                ptw_busy <= 1'b0;
            end
            if (ptw_fault_pending && wb_except_req)
                ptw_fault_pending <= 1'b0;
        end
    end

    // D-cache consumes the MIPS C=2 uncached attribute. In the prototype
    // (MMU disabled), the translation path strips kseg1's A-segment bit before
    // the cache sees the address, so preserve the legacy alias attribute from
    // the original virtual address here. Otherwise control/peripheral reads
    // such as 0xA0002100 can incorrectly become cached line bursts.
    wire legacy_data_uncacheable = (`SOC_MMU_ENABLE == 0) &&
                                   ((mem_vaddr[31:28] == 4'h4) ||
                                    (mem_vaddr[31:28] == 4'hA) ||
                                    (data_addr[31:28] == 4'h4) ||
                                    (data_addr[31:28] == 4'hA));
    assign data_uncacheable = (mmu_d_cache_attr == 3'b010) ||
                              legacy_data_uncacheable;
    assign data_cache_op_addr = data_addr;
    assign data_cache_op_is_icache = data_cache_op_valid &&
                                     ((data_cache_op == 5'b00000) ||
                                      (data_cache_op == 5'b00100) ||
                                      (data_cache_op == 5'b01000) ||
                                      (data_cache_op == 5'b10000));
    assign data_cache_tag_wdata = cp0_taglo;
    wire _mmu_unused = &{1'b0, mmu_i_cache_attr,
                              mmu_i_ok, mmu_d_ok,
                              mmu_i_fault_type, mmu_d_fault_type};

    // -------------------------------------------------------------------------
    // Phase B.6 — Branch Prediction Unit
    // -------------------------------------------------------------------------
    // The architectural result is still resolved in ID. BPU state is updated
    // for every control transfer, including not-taken conditional branches;
    // the optional IF path uses the prediction only when explicitly enabled.
    wire        bpu_resolve_v     = id_control_valid & ~global_stall;
    wire [1:0]  bpu_resolve_type  = id_control_type;
    wire [31:0] bpu_resolve_pc    = id_pc;
    wire [31:0] bpu_resolve_tgt   = id_control_target;
    wire        bpu_resolve_taken = id_control_taken;

    mips_bpu #(.ENABLE_BPU(`SOC_BPU_ENABLE != 0)) u_mips_bpu (
        .clk               (clk),
        .rst_n             (rst_n),
        .if_valid          (inst_req),
        // IF/ID's instruction PC is the registered IF pc.  if_vaddr is the
        // look-ahead cache address and would associate a prediction with the
        // following instruction rather than the one entering ID.
        .if_pc             (ctx_save_pc),
        .predict_hit       (bpu_predict_hit),
        .predict_taken     (bpu_predict_taken),
        .predict_target    (bpu_predict_target),
        .predict_type      (bpu_predict_type),
        .resolve_valid     (bpu_resolve_v),
        .resolve_pc        (bpu_resolve_pc),
        .resolve_taken     (bpu_resolve_taken),
        .resolve_target    (bpu_resolve_tgt),
        .resolve_type      (bpu_resolve_type),
        .resolve_mispredict(bpu_mispredict),
        .flush_if          (bpu_mispredict)
    );

endmodule
