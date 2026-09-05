// =============================================================================
// File Name: mips_core.v
// Design:    MIPS32 CPU Core with L1 Caches
// Author:    Antigravity
// =============================================================================

`include "soc_config.vh"

module mips_core #(
    parameter ENABLE_COHERENCY = 1'b0,
    parameter ENABLE_SCHEDULER = 1'b0,
    parameter ENABLE_VEIC = 1'b0,
    parameter [9:0] CPUNUM = 10'd0,
    parameter ENABLE_PERF_COUNTERS = (`SOC_PERF_COUNTERS != 0)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  ext_int,
    input  wire        tlb_inv_en,
    input  wire [18:0] tlb_inv_vpn2,
    input  wire [7:0]  tlb_inv_asid,
    input  wire [1:0]  tlb_inv_scope,
    input  wire [5:0]  tlb_inv_wired_floor,
    input  wire        sim_exception_req,
    input  wire [4:0]  sim_exception_code,
    input  wire [7:0]  external_vec_id,
    output wire        coh_store_valid,
    output wire [31:0] coh_store_addr,
    input  wire        coh_snoop_valid,
    input  wire [31:0] coh_snoop_addr,
    input  wire        scheduler_enable,
    input  wire        scheduler_timer_tick,
    input  wire        scheduler_ipi_resched,
    input  wire        scheduler_yield_req,
    input  wire [3:0]  scheduler_active_mask,
    input  wire        hardware_walker_enable,
    input  wire [31:0] hardware_walker_ptbr,
    output wire        ptw_mem_valid,
    output wire [31:0] ptw_mem_addr,
    output wire        ptw_mem_write_valid,
    output wire [31:0] ptw_mem_write_addr,
    output wire [31:0] ptw_mem_write_data,
    input  wire        ptw_mem_ready,
    input  wire [31:0] ptw_mem_rdata,
    input  wire        ptw_mem_error,
    input  wire        ptw_mem_write_ready,
    input  wire        ptw_mem_write_error,
    output wire        ptw_fault_valid,
    output wire [2:0]  ptw_fault_code,
    output wire        tlb_inv_applied,
    
    // AXI4 Master Interface (Instruction Cache)
    output wire [3:0]  inst_awid,
    output wire [31:0] inst_awaddr,
    output wire [7:0]  inst_awlen,
    output wire [2:0]  inst_awsize,
    output wire [1:0]  inst_awburst,
    output wire [1:0]  inst_awlock,
    output wire [3:0]  inst_awcache,
    output wire [2:0]  inst_awprot,
    output wire        inst_awvalid,
    input  wire        inst_awready,
    
    output wire [31:0] inst_wdata,
    output wire [3:0]  inst_wstrb,
    output wire        inst_wlast,
    output wire        inst_wvalid,
    input  wire        inst_wready,
    
    input  wire [3:0]  inst_bid,
    input  wire [1:0]  inst_bresp,
    input  wire        inst_bvalid,
    output wire        inst_bready,
    
    output wire [3:0]  inst_arid,
    output wire [31:0] inst_araddr,
    output wire [7:0]  inst_arlen,
    output wire [2:0]  inst_arsize,
    output wire [1:0]  inst_arburst,
    output wire [1:0]  inst_arlock,
    output wire [3:0]  inst_arcache,
    output wire [2:0]  inst_arprot,
    output wire        inst_arvalid,
    input  wire        inst_arready,
    
    input  wire [3:0]  inst_rid,
    input  wire [31:0] inst_rdata,
    input  wire [1:0]  inst_rresp,
    input  wire        inst_rlast,
    input  wire        inst_rvalid,
    output wire        inst_rready,
    
    // AXI4 Master Interface (Data Cache)
    output wire [3:0]  data_awid,
    output wire [31:0] data_awaddr,
    output wire [7:0]  data_awlen,
    output wire [2:0]  data_awsize,
    output wire [1:0]  data_awburst,
    output wire [1:0]  data_awlock,
    output wire [3:0]  data_awcache,
    output wire [2:0]  data_awprot,
    output wire        data_awvalid,
    input  wire        data_awready,
    
    output wire [31:0] data_wdata,
    output wire [3:0]  data_wstrb,
    output wire        data_wlast,
    output wire        data_wvalid,
    input  wire        data_wready,
    
    input  wire [3:0]  data_bid,
    input  wire [1:0]  data_bresp,
    input  wire        data_bvalid,
    output wire        data_bready,
    
    output wire [3:0]  data_arid,
    output wire [31:0] data_araddr,
    output wire [7:0]  data_arlen,
    output wire [2:0]  data_arsize,
    output wire [1:0]  data_arburst,
    output wire [1:0]  data_arlock,
    output wire [3:0]  data_arcache,
    output wire [2:0]  data_arprot,
    output wire        data_arvalid,
    input  wire        data_arready,
    
    input  wire [3:0]  data_rid,
    input  wire [31:0] data_rdata,
    input  wire [1:0]  data_rresp,
    input  wire        data_rlast,
    input  wire        data_rvalid,
    output wire        data_rready,
    
    // Debug interface
    output wire        debug_stall,
    output wire        debug_flush,
    output wire [31:0] perf_cycle_count,
    output wire [31:0] perf_retire_count,
    output wire [31:0] perf_icache_miss_count,
    output wire [31:0] perf_dcache_miss_count,
    output wire [31:0] perf_branch_mispredict_count,
    output wire [31:0] perf_mdu_stall_count
);

    // CPU to I-Cache Interface
    wire        cpu_inst_req;
    wire [31:0] cpu_inst_addr;
    wire        cpu_inst_addr_ok;
    wire        cpu_inst_data_ok;
    wire        cpu_inst_bus_error;
    wire        cpu_inst_cache_error;
    wire [31:0] cpu_inst_rdata;
    wire        cpu_inst_flush;
    
    // CPU to D-Cache Interface
    wire        cpu_data_req;
    wire [3:0]  cpu_data_req_id;
    wire [3:0]  cpu_data_resp_id;
    wire        cpu_data_we;
    wire [31:0] cpu_data_addr;
    wire [31:0] cpu_data_wdata;
    wire [3:0]  cpu_data_be;
    wire        cpu_data_uncacheable;
    wire        cpu_data_cache_op_valid;
    wire [4:0]  cpu_data_cache_op;
    wire [31:0] cpu_data_cache_op_addr;
    wire        cpu_data_cache_op_is_icache;
    wire        cpu_data_cache_op_done;
    wire        cpu_data_cache_op_error;
    wire [31:0] cpu_data_cache_tag_rdata;
    wire [31:0] cpu_data_cache_tag_wdata;
    wire        cpu_data_addr_ok;
    wire        cpu_data_data_ok;
    wire        cpu_data_bus_error;
    wire        cpu_data_cache_error;
    wire [31:0] cpu_data_rdata;

    wire        icache_op_valid = cpu_data_cache_op_valid &&
                                  cpu_data_cache_op_is_icache;
    wire        dcache_op_valid = cpu_data_cache_op_valid &&
                                  !cpu_data_cache_op_is_icache;
    wire        icache_op_done;
    wire        icache_op_error;
    wire [31:0] icache_tag_rdata;
    wire        dcache_op_done;
    wire        dcache_op_error;
    wire [31:0] cpu_data_cache_tag_rdata_d;

    // The CPU MEM-stage handshake is shared by both caches. Select completion
    // and TagLo readback from the cache selected by the raw CACHE opcode.
    assign cpu_data_cache_op_done  = cpu_data_cache_op_is_icache ?
                                     icache_op_done : dcache_op_done;
    assign cpu_data_cache_op_error = cpu_data_cache_op_is_icache ?
                                     icache_op_error : dcache_op_error;
    assign cpu_data_cache_tag_rdata = cpu_data_cache_op_is_icache ?
                                      icache_tag_rdata :
                                      cpu_data_cache_tag_rdata_d;

    wire        icache_cpu_req = cpu_inst_req & ~cpu_data_cache_op_valid;

    wire sched_enable_i = ENABLE_SCHEDULER && (scheduler_enable === 1'b1);
    wire [3:0] sched_active_mask_i = sched_enable_i ? scheduler_active_mask : 4'b0001;
    wire sched_save_req, sched_save_done;
    wire [7:0] sched_save_task;
    wire [31:0] sched_save_pc, sched_save_sp, sched_save_status;
    wire [7:0] sched_save_asid;
    wire [31:0] sched_save_ptebase;
    wire [31:0] sched_save_srsctl;
    wire [1023:0] sched_save_gpr;
    wire [16383:0] sched_save_srs_gpr;
    wire [1023:0] sched_save_fpr;
    wire [31:0] sched_save_fcsr;
    wire sched_restore_req, sched_restore_ack;
    wire [7:0] sched_restore_task;
    wire [31:0] sched_restore_pc, sched_restore_sp, sched_restore_status;
    wire [7:0] sched_restore_asid;
    wire [31:0] sched_restore_ptebase;
    wire sched_restore_ptebase_valid;
    wire [31:0] sched_restore_srsctl;
    wire [1023:0] sched_restore_gpr;
    wire [16383:0] sched_restore_srs_gpr;
    wire [1023:0] sched_restore_fpr;
    wire [31:0] sched_restore_fcsr;
    wire sched_unused_ack;

    // SP is architecturally GPR29; keep the scheduler's explicit SP field
    // coherent with the packed register image used by the CPU boundary.
    assign sched_save_sp = sched_save_gpr[29*32 +: 32];

    cpu_scheduler #(.TASKS(4)) u_cpu_scheduler (
        .clk(clk), .rst_n(rst_n), .enable(sched_enable_i),
        .timer_tick(scheduler_timer_tick === 1'b1),
        .ipi_resched(scheduler_ipi_resched === 1'b1),
        .yield_req(scheduler_yield_req === 1'b1),
        .active_mask(sched_active_mask_i),
        .resched_ack(sched_unused_ack), .scheduler_busy(), .current_task(),
        .switch_valid(), .switch_from(), .switch_to(),
        .ctx_save_req(sched_save_req), .ctx_save_task(sched_save_task),
        .ctx_save_done(sched_save_done), .ctx_save_pc(sched_save_pc),
        .ctx_save_sp(sched_save_sp), .ctx_save_status(sched_save_status),
        .ctx_save_asid(sched_save_asid), .ctx_save_srsctl(sched_save_srsctl),
        .ctx_save_ptebase(sched_save_ptebase),
        .ctx_save_gpr(sched_save_gpr),
        .ctx_save_srs_gpr(sched_save_srs_gpr),
        .ctx_save_fpr(sched_save_fpr), .ctx_save_fcsr(sched_save_fcsr),
        .ctx_restore_req(sched_restore_req), .ctx_restore_task(sched_restore_task),
        .ctx_restore_ack(sched_restore_ack), .ctx_restore_pc(sched_restore_pc),
        .ctx_restore_sp(sched_restore_sp), .ctx_restore_status(sched_restore_status),
        .ctx_restore_asid(sched_restore_asid), .ctx_restore_srsctl(sched_restore_srsctl),
        .ctx_restore_ptebase(sched_restore_ptebase),
        .ctx_restore_ptebase_valid(sched_restore_ptebase_valid),
        .ctx_restore_gpr(sched_restore_gpr),
        .ctx_restore_srs_gpr(sched_restore_srs_gpr),
        .ctx_restore_fpr(sched_restore_fpr), .ctx_restore_fcsr(sched_restore_fcsr)
    );
    
    // Instantiating the CPU Pipeline
    mips_cpu #(.ENABLE_VEIC(ENABLE_VEIC), .CPUNUM(CPUNUM),
               .ENABLE_PERF_COUNTERS(ENABLE_PERF_COUNTERS)) u_cpu (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .inst_req        (cpu_inst_req),
        .inst_addr       (cpu_inst_addr),
        .inst_addr_ok    (cpu_inst_addr_ok),
        .inst_data_ok    (cpu_inst_data_ok),
        .inst_bus_error  (cpu_inst_bus_error),
        .inst_cache_error(cpu_inst_cache_error),
        .inst_rdata      (cpu_inst_rdata),
        .inst_flush      (cpu_inst_flush),
        
        .data_req        (cpu_data_req),
        .data_req_id     (cpu_data_req_id),
        .data_we         (cpu_data_we),
        .data_addr       (cpu_data_addr),
        .ext_int         (ext_int),
        .tlb_inv_en      (tlb_inv_en),
        .tlb_inv_vpn2    (tlb_inv_vpn2),
        .tlb_inv_asid    (tlb_inv_asid),
        .tlb_inv_scope   (tlb_inv_scope),
        .tlb_inv_wired_floor(tlb_inv_wired_floor),
        .sim_exception_req(sim_exception_req),
        .sim_exception_code(sim_exception_code),
        .external_vec_id(external_vec_id),
        .ctx_save_req(sched_save_req), .ctx_save_done(sched_save_done),
        .ctx_save_pc(sched_save_pc), .ctx_save_status(sched_save_status),
        .ctx_save_asid(sched_save_asid), .ctx_save_srsctl(sched_save_srsctl),
        .ctx_save_ptebase(sched_save_ptebase),
        .ctx_save_gpr(sched_save_gpr),
        .ctx_save_srs_gpr(sched_save_srs_gpr),
        .ctx_save_fpr(sched_save_fpr), .ctx_save_fcsr(sched_save_fcsr),
        .ctx_restore_req(sched_restore_req), .ctx_restore_pc(sched_restore_pc),
        .ctx_restore_status(sched_restore_status), .ctx_restore_asid(sched_restore_asid),
        .ctx_restore_ptebase(sched_restore_ptebase),
        .ctx_restore_ptebase_valid(sched_restore_ptebase_valid),
        .ctx_restore_srsctl(sched_restore_srsctl),
        .ctx_restore_gpr(sched_restore_gpr), .ctx_restore_srs_gpr(sched_restore_srs_gpr),
        .ctx_restore_set(sched_restore_srsctl[3:0]),
        .ctx_restore_fpr(sched_restore_fpr),
        .ctx_restore_fcsr(sched_restore_fcsr), .ctx_restore_ack(sched_restore_ack),
        .hardware_walker_enable(hardware_walker_enable),
        .hardware_walker_ptbr(hardware_walker_ptbr),
        .ptw_mem_valid(ptw_mem_valid), .ptw_mem_addr(ptw_mem_addr),
        .ptw_mem_write_valid(ptw_mem_write_valid),
        .ptw_mem_write_addr(ptw_mem_write_addr),
        .ptw_mem_write_data(ptw_mem_write_data),
        .ptw_mem_ready(ptw_mem_ready), .ptw_mem_rdata(ptw_mem_rdata),
        .ptw_mem_error(ptw_mem_error), .ptw_fault_valid(ptw_fault_valid),
        .ptw_fault_code(ptw_fault_code),
        .ptw_mem_write_ready(ptw_mem_write_ready),
        .ptw_mem_write_error(ptw_mem_write_error),
        .tlb_inv_applied(tlb_inv_applied),
        .coh_snoop_valid (coh_snoop_valid),
        .coh_snoop_addr  (coh_snoop_addr),
        .data_wdata      (cpu_data_wdata),
        .data_be         (cpu_data_be),
        .data_uncacheable(cpu_data_uncacheable),
        .data_cache_op_valid(cpu_data_cache_op_valid),
        .data_cache_op   (cpu_data_cache_op),
        .data_cache_op_addr(cpu_data_cache_op_addr),
        .data_cache_op_is_icache(cpu_data_cache_op_is_icache),
        .data_cache_op_done(cpu_data_cache_op_done),
        .data_cache_op_error(cpu_data_cache_op_error),
        .data_cache_tag_rdata(cpu_data_cache_tag_rdata),
        .data_cache_tag_wdata(cpu_data_cache_tag_wdata),
        .data_addr_ok    (cpu_data_addr_ok),
        .data_data_ok    (cpu_data_data_ok),
        .data_resp_id    (cpu_data_resp_id),
        .data_bus_error  (cpu_data_bus_error),
        .data_cache_error(cpu_data_cache_error),
        .data_rdata      (cpu_data_rdata),
        
        .debug_stall     (debug_stall),
        .debug_flush     (debug_flush),
        .perf_cycle_count(perf_cycle_count),
        .perf_retire_count(perf_retire_count),
        .perf_icache_miss_count(perf_icache_miss_count),
        .perf_dcache_miss_count(perf_dcache_miss_count),
        .perf_branch_mispredict_count(perf_branch_mispredict_count),
        .perf_mdu_stall_count(perf_mdu_stall_count)
    );
    
    // Instantiating the I-Cache
    // Note: I-Cache is read-only, so we tie off the AW/W/B channels
    assign inst_awid    = 4'd0;
    assign inst_awaddr  = 32'd0;
    assign inst_awlen   = 8'd0;
    assign inst_awsize  = 3'd0;
    assign inst_awburst = 2'd0;
    assign inst_awlock  = 2'd0;
    assign inst_awcache = 4'd0;
    assign inst_awprot  = 3'd0;
    assign inst_awvalid = 1'b0;
    
    assign inst_wdata   = 32'd0;
    assign inst_wstrb   = 4'd0;
    assign inst_wlast   = 1'b0;
    assign inst_wvalid  = 1'b0;
    
    assign inst_bready  = 1'b0;
    
    icache u_icache (
        .clk          (clk),
        .rst_n        (rst_n),
        
        .cpu_req      (icache_cpu_req),
        .cpu_addr     (cpu_inst_addr),
        .cpu_rdata    (cpu_inst_rdata),
        .cpu_addr_ok  (cpu_inst_addr_ok),
        .cpu_data_ok  (cpu_inst_data_ok),
        .cpu_bus_error(cpu_inst_bus_error),
        .cpu_cache_error(cpu_inst_cache_error),
        .flush        (cpu_inst_flush),

        .cache_op_valid(icache_op_valid),
        .cache_op      (cpu_data_cache_op),
        .cache_op_addr (cpu_data_cache_op_addr),
        .cache_op_ready(),
        .cache_op_done (icache_op_done),
        .cache_op_error(icache_op_error),
        .cache_tag_wdata(cpu_data_cache_tag_wdata),
        .cache_tag_rdata(icache_tag_rdata),

        .sim_parity_inject_valid(1'b0),
        .sim_parity_inject_tag  (1'b0),
        .sim_parity_inject_data (1'b0),
        .sim_parity_inject_way  (2'b0),
        .sim_parity_inject_index(6'b0),
        
        .arid         (inst_arid),
        .araddr       (inst_araddr),
        .arlen        (inst_arlen),
        .arsize       (inst_arsize),
        .arburst      (inst_arburst),
        .arlock       (inst_arlock),
        .arcache      (inst_arcache),
        .arprot       (inst_arprot),
        .arvalid      (inst_arvalid),
        .arready      (inst_arready),
        
        .rid          (inst_rid),
        .rdata        (inst_rdata),
        .rresp        (inst_rresp),
        .rlast        (inst_rlast),
        .rvalid       (inst_rvalid),
        .rready       (inst_rready)
    );
    
    // The nonblocking cache is opt-in.  Its uncached and maintenance traffic
    // remains on the legacy dcache inside the adapter, preserving the default
    // CPU/AXI contract while allowing cacheable misses to complete late.
    generate
    if ((`SOC_L1_NONBLOCKING_ENABLE != 0) &&
        (`SOC_CPU_NONBLOCKING_ENABLE != 0)) begin : g_l1_nonblocking
        l1_cache_nb_cpu_axi #(
            .ENABLE_LEGACY_ADDR_HEURISTIC((`SOC_MMU_ENABLE == 0) &&
                                           (`SOC_PRODUCT_BOOT_ENABLE == 0)),
            .ENABLE_COHERENCY(ENABLE_COHERENCY),
            .ENABLE_L1((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                       (`SOC_L1_NONBLOCKING_ENABLE != 0)),
            .ENABLE_MULTI_OUTSTANDING((`SOC_CPU_NONBLOCKING_ENABLE != 0) &&
                                       (`SOC_ROB_FIFO_ENABLE != 0)),
            .WRITE_THROUGH_STORES(1'b1)
        ) u_dcache (
            .clk(clk), .rst_n(rst_n), .cpu_req(cpu_data_req),
            .cpu_id(cpu_data_req_id),
            .cpu_we(cpu_data_we), .cpu_addr(cpu_data_addr),
            .cpu_wdata(cpu_data_wdata), .cpu_be(cpu_data_be),
            .cpu_uncacheable(cpu_data_uncacheable),
            .cpu_rdata(cpu_data_rdata), .cpu_addr_ok(cpu_data_addr_ok),
            .cpu_data_ok(cpu_data_data_ok), .cpu_bus_error(cpu_data_bus_error),
            .cpu_cache_error(cpu_data_cache_error),
            .cpu_response_id(cpu_data_resp_id),
            .cache_op_valid(dcache_op_valid), .cache_op(cpu_data_cache_op),
            .cache_op_addr(cpu_data_cache_op_addr), .cache_op_ready(),
            .cache_op_done(dcache_op_done), .cache_op_error(dcache_op_error),
            .cache_tag_wdata(cpu_data_cache_tag_wdata),
            .cache_tag_rdata(cpu_data_cache_tag_rdata_d),
            .awid(data_awid), .awaddr(data_awaddr), .awlen(data_awlen),
            .awsize(data_awsize), .awburst(data_awburst), .awlock(data_awlock),
            .awcache(data_awcache), .awprot(data_awprot), .awvalid(data_awvalid),
            .awready(data_awready), .wdata(data_wdata), .wstrb(data_wstrb),
            .wlast(data_wlast), .wvalid(data_wvalid), .wready(data_wready),
            .bid(data_bid), .bresp(data_bresp), .bvalid(data_bvalid),
            .bready(data_bready), .arid(data_arid), .araddr(data_araddr),
            .arlen(data_arlen), .arsize(data_arsize), .arburst(data_arburst),
            .arlock(data_arlock), .arcache(data_arcache), .arprot(data_arprot),
            .arvalid(data_arvalid), .arready(data_arready), .rid(data_rid),
            .rdata(data_rdata), .rresp(data_rresp), .rlast(data_rlast),
            .rvalid(data_rvalid), .rready(data_rready),
            .coh_store_valid(coh_store_valid), .coh_store_addr(coh_store_addr),
            .coh_snoop_valid(coh_snoop_valid), .coh_snoop_addr(coh_snoop_addr)
        );
    end else begin : g_blocking
    // Instantiating the legacy blocking D-Cache
    dcache #(
        .ENABLE_LEGACY_ADDR_HEURISTIC ((`SOC_MMU_ENABLE == 0) &&
                                        (`SOC_PRODUCT_BOOT_ENABLE == 0)),
        .ENABLE_COHERENCY             (ENABLE_COHERENCY)
    ) u_dcache (
        .clk          (clk),
        .rst_n        (rst_n),
        
        .cpu_req      (cpu_data_req),
        .cpu_we       (cpu_data_we),
        .cpu_addr     (cpu_data_addr),
        .cpu_wdata    (cpu_data_wdata),
        .cpu_be       (cpu_data_be),
        .cpu_uncacheable(cpu_data_uncacheable),
        .cpu_rdata    (cpu_data_rdata),
        .cpu_addr_ok  (cpu_data_addr_ok),
        .cpu_data_ok  (cpu_data_data_ok),
        .cpu_bus_error(cpu_data_bus_error),
        .cpu_cache_error(cpu_data_cache_error),
        .sim_parity_inject_valid(1'b0), .sim_parity_inject_tag(1'b0),
        .sim_parity_inject_data(1'b0), .sim_parity_inject_way(2'b0),
        .sim_parity_inject_index(6'b0),
        .cache_op_valid(dcache_op_valid),
        .cache_op      (cpu_data_cache_op),
        .cache_op_addr (cpu_data_cache_op_addr),
        .cache_op_ready(),
        .cache_op_done (dcache_op_done),
        .cache_op_error(dcache_op_error),
        .cache_tag_rdata(cpu_data_cache_tag_rdata_d),
        .cache_tag_wdata(cpu_data_cache_tag_wdata),
        
        .awid         (data_awid),
        .awaddr       (data_awaddr),
        .awlen        (data_awlen),
        .awsize       (data_awsize),
        .awburst      (data_awburst),
        .awlock       (data_awlock),
        .awcache      (data_awcache),
        .awprot       (data_awprot),
        .awvalid      (data_awvalid),
        .awready      (data_awready),
        
        .wdata        (data_wdata),
        .wstrb        (data_wstrb),
        .wlast        (data_wlast),
        .wvalid       (data_wvalid),
        .wready       (data_wready),
        
        .bid          (data_bid),
        .bresp        (data_bresp),
        .bvalid       (data_bvalid),
        .bready       (data_bready),
        
        .arid         (data_arid),
        .araddr       (data_araddr),
        .arlen        (data_arlen),
        .arsize       (data_arsize),
        .arburst      (data_arburst),
        .arlock       (data_arlock),
        .arcache      (data_arcache),
        .arprot       (data_arprot),
        .arvalid      (data_arvalid),
        .arready      (data_arready),
        
        .rid          (data_rid),
        .rdata        (data_rdata),
        .rresp        (data_rresp),
        .rlast        (data_rlast),
        .rvalid       (data_rvalid),
        .rready       (data_rready),
        .coh_store_valid(coh_store_valid),
        .coh_store_addr (coh_store_addr),
        .coh_snoop_valid(coh_snoop_valid),
        .coh_snoop_addr (coh_snoop_addr)
    );
    assign cpu_data_resp_id = 4'd0;
    end
    endgenerate

endmodule
