// =============================================================================
// File Name: tb_mips_soc.v
// Design:    Testbench for MIPS32 SoC Top
// Author:    Antigravity
// =============================================================================

`timescale 1ns/1ps
`include "soc_legacy_observation_if.sv"
`ifdef TB_RETIRE_TRACE
`include "../uvm_tb/tb_top/soc_observation_if.sv"
`include "../uvm_tb/tb_top/soc_observation_bind.sv"
`include "../isa_ref/retire_trace_capture.sv"
`endif

`ifdef TB_L1_NONBLOCKING
`ifdef SOC_CPU_NONBLOCKING_ENABLE
`define TB_DCACHE_PATH u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache
`else
`define TB_DCACHE_PATH u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache
`endif
`else
`define TB_DCACHE_PATH u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache
`endif
`include "soc_legacy_observation_bind.sv"

module tb_mips_soc;

    reg tck_r = 0;
    reg tms_r = 1;
    reg tdi_r = 0;
    wire tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire [3:0] qspi_io;
    wire uart_tx;
    wire uart_rts_n;
    wire uart_dtr_n;

    reg clk;
    reg rst_n;
    integer soc_timeout_ns;

    wire        legacy_uart_tx_valid;
    wire [7:0]  legacy_uart_tx_data;

    soc_legacy_observation_if legacy_obs_if(clk, rst_n);
`ifdef TB_RETIRE_TRACE
    soc_observation_if retire_obs_if(clk, rst_n);
    retire_trace_capture u_retire_trace_capture(.clk(clk), .rst_n(rst_n),
                                                 .obs_if(retire_obs_if));
`endif
    reg [1023:0] firmware_hex;
`ifdef TB_LINUX_BOOT
    reg [1023:0] ddr_hex;
`endif
`ifdef TB_LINUX_BOOT_TRACE
    integer linux_trace_cycle;
    integer linux_trace_limit;
    integer linux_refill_trace;
    integer linux_progress_trace;
    integer linux_stall_trace;
    integer linux_stall_trace_limit;
    integer linux_stall_trace_count;
    integer linux_stall_trace_cycle_start;
    reg [31:0] linux_stall_trace_pc;
    reg linux_global_stall_prev;
    reg linux_wait_trace_prev;
    reg linux_intr_trace_prev;
    integer linux_exception_trace;
    integer linux_exception_trace_limit;
    integer linux_exception_trace_count;
    integer linux_exception_frame_trace;
    integer linux_exception_frame_trace_limit;
    integer linux_exception_frame_trace_count;
    integer linux_exception_frame_trace_cycle_start;
    integer linux_exception_frame_trace_cycle_end;
    integer linux_exception_frame_pending;
    integer linux_exception_frame_pending_cycle;
    reg [31:0] linux_exception_frame_pending_pc;
    reg [4:0]  linux_exception_frame_pending_code;
    reg        linux_exception_frame_pending_interrupt;
    reg        linux_exception_frame_pending_bd;
    integer linux_ebase_trace;
    integer linux_ebase_trace_limit;
    integer linux_ebase_trace_count;
    integer linux_wb_trace;
    integer linux_wb_trace_limit;
    integer linux_wb_trace_count;
    integer linux_mode_trace;
    integer linux_mode_trace_limit;
    integer linux_mode_trace_count;
    reg     linux_cpu_kernel_prev;
    integer linux_pc_trace;
    integer linux_pc_trace_limit;
    integer linux_pc_trace_count;
    integer linux_pc_trace_retire_only;
    integer linux_pc_trace_cycle_start;
    integer linux_pc_trace_cycle_end;
    reg [31:0] linux_pc_trace_start;
    reg [31:0] linux_pc_trace_end;
    integer linux_wait_trace;
    integer linux_wait_trace_limit;
    integer linux_wait_trace_count;
    reg     linux_wait_state_prev;
    integer linux_vector_trace;
    integer linux_vector_trace_limit;
    integer linux_vector_trace_count;
    integer linux_cacheop_trace_limit;
    integer linux_cacheop_trace_count;
    reg [26:0] linux_cacheop_trace_line;
    integer linux_cp0_trace_limit;
    integer linux_cp0_trace_count;
    integer linux_ddr_trace;
    integer linux_ddr_trace_limit;
    integer linux_ddr_trace_count;
    integer linux_late_icache_trace;
    integer linux_late_icache_trace_limit;
    integer linux_late_icache_trace_count;
    integer linux_ddr_write_trace;
    integer linux_ddr_write_trace_limit;
    integer linux_ddr_write_trace_count;
    integer linux_target_dside_trace;
    integer linux_target_dside_trace_limit;
    integer linux_target_dside_trace_count;
    reg [26:0] linux_target_trace_line;
    integer linux_target_trace_cycle_start;
    integer linux_target_trace_cycle_end;
    integer linux_delay_trace;
    integer linux_delay_trace_limit;
    integer linux_delay_trace_count;
    integer linux_delay_trace_cycle_start;
    integer linux_delay_trace_cycle_end;
    reg [31:0] linux_delay_trace_start;
    reg [31:0] linux_delay_trace_end;
    integer linux_gpr_trace;
    integer linux_gpr_trace_limit;
    integer linux_gpr_trace_count;
    integer linux_gpr_trace_cycle_start;
    integer linux_gpr_trace_cycle_end;
    reg [4:0] linux_gpr_trace_reg;
    integer linux_uart_trace;
    integer linux_uart_trace_limit;
    integer linux_uart_trace_count;
    integer linux_panic_trace;
    integer linux_panic_trace_limit;
    integer linux_panic_trace_count;
    reg [31:0] linux_panic_trace_start;
    reg [31:0] linux_panic_trace_end;
    integer linux_cache_owner_trace;
    integer linux_cache_owner_trace_limit;
    integer linux_cache_owner_trace_count;
    integer linux_tlb_trace;
    integer linux_tlb_trace_limit;
    integer linux_tlb_trace_count;
    integer linux_tlb_trace_cycle_start;
    integer linux_tlb_trace_cycle_end;
    integer linux_fault_trace;
    integer linux_fault_trace_limit;
    integer linux_fault_trace_count;
    reg [31:0] linux_fault_trace_start;
    reg [31:0] linux_fault_trace_end;
    integer linux_fault_trace_cycle_start;
    integer linux_fault_trace_cycle_end;
    integer linux_vector_line_trace;
    integer linux_vector_line_trace_limit;
    integer linux_vector_line_trace_count;
    reg [26:0] linux_vector_line;
`endif
    integer cp0_interrupt_count;
    integer cp0_syscall_count;
    integer cp0_ri_count;
    integer cp0_adel_count;
    integer cp0_cacheerr_count;
    integer cp0_eret_count;
    integer dual_core_ipi_count;
    integer dual_core_reverse_ipi_count;
    integer dual_core_reset_count;
    integer dual_core_exception_count;
`ifdef TB_MMU_HW_WALKER_AD
    integer hw_ad_aw_count;
    integer hw_ad_w_count;
    integer hw_ad_delayed_w_count;
    integer hw_ad_reset_seen;
    integer hw_ad_write_error_seen;
    integer hw_ad_downstream_error_seen;
    reg hw_ad_aw_pending;
    time hw_ad_aw_time;
`endif
`ifdef TB_L1_MAINTENANCE
    integer l1_maintenance_count;
    integer l1_maintenance_refill_count;
    reg l1_maintenance_waiting_refill;
`endif
`ifdef DMA_EVENT_TRACE
    integer dma_event_fd;
    reg [1023:0] dma_event_path;
    reg [3:0] dma_done_seen;
    reg [3:0] dma_err_seen;
    reg [3:0] dma_busy_seen;
    reg [3:0] dma_irq_seen;
`endif

`ifdef TB_DMA_RESET_STRESS
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.busy_r[0] === 1'b1);
        $display("DMA_RESET_STRESS: busy observed, asserting reset in flight");
        #20 rst_n = 1'b0;
        #50 rst_n = 1'b1;
        $display("DMA_RESET_STRESS: reset released");
    end

    always @(posedge clk) begin
        if (rst_n && u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.busy_r[0])
            $display("DMA_RESET_STRESS: live src=%08h dst=%08h len=%0d state=%0d ar=%b r=%b aw=%b w=%b b=%b",
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.cur_src_r[0],
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.cur_dst_r[0],
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.cur_len_r[0],
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.ch_state[0],
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.m_arvalid,
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.m_rvalid,
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.m_awvalid,
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.m_wvalid,
                     u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.m_bvalid);
    end
`endif

`ifdef TB_LINUX_BOOT_TRACE
    // Keep the Linux diagnostic at the testbench boundary so it cannot alter
    // CPU/cache timing.  The trace is opt-in and samples only the first refill
    // path plus a sparse heartbeat to keep logs bounded.
    always @(posedge clk) begin
        if (!rst_n) begin
            linux_trace_cycle = 0;
        end else begin
            linux_trace_cycle = linux_trace_cycle + 1;
            if (linux_trace_limit > 0 && linux_trace_cycle >= linux_trace_limit)
                $finish;
            if (linux_stall_trace != 0 &&
                linux_stall_trace_count < linux_stall_trace_limit &&
                linux_trace_cycle >= linux_stall_trace_cycle_start &&
                ((linux_stall_trace_pc != 32'd0) ?
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc ==
                  linux_stall_trace_pc) :
                 ((linux_trace_cycle < 20) ||
                  (linux_wait_trace_prev !=
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state) ||
                  (linux_intr_trace_prev !=
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.intr_req)))) begin
                $display("LINUX_STALL_TRACE cycle=%0d pc=%08h global=%b if=%b mem=%b mdu=%b rob=%b wait=%b ifok=%b memdone=%b memrd=%b memwr=%b dreq=%b dok=%b icstate=%0d icflush=%b ichit=%b icreqv=%b icreqa=%08h icidx=%0d ictag=%08h icvalid=%b%b%b%b ichitv=%b%b%b%b dcstate=%0d mdu_ready=%b idpc=%08h exp=%b intr=%b status=%08h cause=%08h count=%08h compare=%08h timer_ip=%b ext_int=%b wait_resume=%08h wb_eret=%b wb_arch=%b exc_flush=%b",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.global_stall,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.stall_req_if,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.stall_req_mem,
                    ~u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mdu_ready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.rob_backpressure,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_data_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_done,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_read,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_flush,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.cache_hit,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.lookup_index,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.lookup_tag,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_valid[3],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_valid[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_valid[1],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_valid[0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_hit[3],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_hit[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_hit[1],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.way_hit[0],
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mdu_ready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_count,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_compare,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.timer_ip_active,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ext_int,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_resume_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.exception_flush);
                linux_stall_trace_count = linux_stall_trace_count + 1;
            end
            if (linux_mode_trace != 0 &&
                linux_mode_trace_count < linux_mode_trace_limit &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_kernel_mode !=
                    linux_cpu_kernel_prev ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret)) begin
                $display("LINUX_MODE_TRACE cycle=%0d kernel=%b eret=%b pc=%08h wbpc=%08h status=%08h cause=%08h epc=%08h sp=%08h ra=%08h a0=%08h a1=%08h v0=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_kernel_mode,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[29],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[4],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[5],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[2]);
                linux_mode_trace_count = linux_mode_trace_count + 1;
            end
            if (linux_pc_trace != 0 &&
                linux_pc_trace_count < linux_pc_trace_limit &&
                linux_trace_cycle >= linux_pc_trace_cycle_start &&
                (linux_pc_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_pc_trace_cycle_end) &&
                linux_pc_trace_start != linux_pc_trace_end &&
                ((linux_pc_trace_retire_only != 0) ?
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= linux_pc_trace_start) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc < linux_pc_trace_end)) :
                 (((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc >= linux_pc_trace_start) &&
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc < linux_pc_trace_end)) ||
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= linux_pc_trace_start) &&
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc < linux_pc_trace_end))))) begin
                $display("LINUX_PC_TRACE cycle=%0d ifpc=%08h wbpc=%08h wbinst=%08h wbarch=%b wbreg=%b/%0d/%08h mem=%b/%08h/%08h llsc=%b/%b/%b/%b/%08h/%08h/%08h data=%b/%b/%b/%08h/%08h status=%08h cause=%08h epc=%08h sp=%08h ra=%08h a0=%08h a1=%08h v0=%08h gp=%08h t0=%08h s0=%08h s3=%08h s4=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.is_ll_mem,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.is_sc_mem,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.sc_reservation_match,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.reservation_data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.lladdr_visible,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok_current,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[29],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[4],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[5],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[28],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[8],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[16],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[19],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[20]);
                linux_pc_trace_count = linux_pc_trace_count + 1;
            end
            linux_cpu_kernel_prev =
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_kernel_mode;
            if (linux_uart_trace != 0 &&
                linux_uart_trace_count < linux_uart_trace_limit &&
                legacy_uart_tx_valid) begin
                $display("LINUX_UART_TRACE cycle=%0d paddr=%08h data=%02h",
                         linux_trace_cycle,
                         u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.paddr,
                         legacy_uart_tx_data);
                linux_uart_trace_count = linux_uart_trace_count + 1;
            end
            // Capture a bounded panic context without tracing the whole wait
            // loop. This diagnostic is sampled at the testbench boundary.
            if (linux_panic_trace != 0 &&
                linux_panic_trace_count < linux_panic_trace_limit &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc >= linux_panic_trace_start &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc < linux_panic_trace_end) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= linux_panic_trace_start &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc < linux_panic_trace_end))) begin
                $display("LINUX_PANIC_TRACE cycle=%0d ifpc=%08h wbpc=%08h sp=%08h ra=%08h a0=%08h a1=%08h a2=%08h a3=%08h v0=%08h gp=%08h status=%08h cause=%08h epc=%08h bad=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[29],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[4],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[5],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[6],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[7],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[28],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr);
                linux_panic_trace_count = linux_panic_trace_count + 1;
            end
            // Linux installs generated exception vectors through the
            // uncached CKSEG1 alias. Keep this trace narrow and bounded so it
            // can distinguish vector writes, vector fetches and actual TLB
            // writes without turning a long boot into an unbounded log.
            if (linux_tlb_trace != 0 &&
                linux_tlb_trace_count < linux_tlb_trace_limit &&
                (linux_tlb_trace_cycle_start == 0 ||
                 linux_trace_cycle >= linux_tlb_trace_cycle_start) &&
                (linux_tlb_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_tlb_trace_cycle_end) &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= 32'ha8e0_0000) &&
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr < 32'ha8e1_0000) ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr >= 32'h88e0_0000) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr < 32'h88e1_0000) ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_en ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                  (|u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_tlb_op))) begin
                $display("LINUX_TLB_TRACE cycle=%0d pc=%08h inst=%08h vr=%b/%08h/%08h dw=%b/%08h/%08h/%h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be);
                $display("LINUX_TLB_STATE cycle=%0d tlb=%b/%0d/%08h/%08h/%08h/%08h op=%0d hit=%b/%0d/%b/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_en,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_index,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_vpn2,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_entrylo0,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_entrylo1,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.wr_mask,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_tlb_op,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_pfn,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_pfn);
                linux_tlb_trace_count = linux_tlb_trace_count + 1;
            end
            // Keep fault/address evidence independent from broad TLB logs:
            // Linux can clear many entries in a loop before the useful event.
            if (linux_fault_trace != 0 &&
                linux_fault_trace_count < linux_fault_trace_limit &&
                (linux_fault_trace_cycle_start == 0 ||
                 linux_trace_cycle >= linux_fault_trace_cycle_start) &&
                (linux_fault_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_fault_trace_cycle_end) &&
                (((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code == 5'd2 ||
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code == 5'd3 ||
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code == 5'd4 ||
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code == 5'd5)) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= linux_fault_trace_start) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr < linux_fault_trace_end)) ||
                 (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.psel &&
                  u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.penable))) begin
                $display("LINUX_FAULT_TRACE cycle=%0d pc=%08h code=%0d bad=%08h status=%08h cause=%08h vaddr=%08h data=%b/%b/%08h/%h apb=%b/%b/%b/%08h/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be,
                    u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.psel,
                    u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.penable,
                    u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwrite,
                    u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.paddr,
                    u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwdata);
                linux_fault_trace_count = linux_fault_trace_count + 1;
            end
            if (linux_exception_trace != 0 &&
                linux_exception_trace_count < linux_exception_trace_limit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req) begin
                $display("LINUX_EXCEPTION_TRACE cycle=%0d pc=%08h code=%0d intr=%b accept=%b wbei=%b wbctl=%b/%b epc=%08h bad=%08h status=%08h cause=%08h ebase=%08h d=%b/%b/%08h vaddr=%08h wbd=%08h if=%b/%08h/%08h mmui=%b/%0d k=%b tlbi=%b/%b/%b/%08h ifmeta=%b/%0d/%08h wb=%b/%0d/%b/%b/%08h/%08h valid=%b arch=%b mem=%b/%0d/%b/%b/%08h meminst=%08h exinst=%08h old=%08h ibd=%b mbd=%b ebd=%b idbd=%b dside=%b/%b/%08h/%0d dataok=%b/%08h s1=%08h s3=%08h s0=%08h bd=%b/%b/%b tlb41=%b/%08h/%08h/%08h/%b asid=%02h/%02h va=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ei,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_to_reg,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    {u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_ebase_hi, 12'd0},
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_fault_type,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_kernel_mode,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_hit,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_multi_hit,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_v,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_pfn,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_fault_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_fault_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_fault_vaddr_q,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_data,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_tlb_refill,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_is_data,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_is_tlb_refill,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.oldest_flushed_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_wb_branch_delay,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.dmem_translate_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[17],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[19],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[16],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_valid[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_vpn2[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_mask[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_entrylo0[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.lookup1_hit_vec[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.u_mips_tlb.tlb_asid[41],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cp0_asid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_dlookup_va);
                // The live MEM signals may already describe a younger
                // instruction than the WB exception. Keep this detail record
                // separate so existing trace parsers remain compatible.
                $display("LINUX_EXCEPTION_DETAIL cycle=%0d wbpc=%08h wbinst=%08h wbex=%08h wbexc=%b/%0d/%b/%b mempc=%08h meminst=%08h memex=%08h memva=%08h memreq=%b/%b/%08h mmud=%b/%0d/%08h dflt=%b/%08h dpend=%b data=%b/%b/%08h/%h/%b/%b dcache=%0d/%b/%b/%08h/%08h/%h axi=%b/%b/%08h/%b/%b/%08h/%h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_data,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_tlb_refill,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_fault_type,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_d_pa,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.dmem_translation_fault,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.d_fault_vaddr_q,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.d_fault_vaddr_pending_q,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_bus_error,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_error,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                    `TB_DCACHE_PATH.state,
                    `TB_DCACHE_PATH.req_buf_valid,
                    `TB_DCACHE_PATH.req_buf_we,
                    `TB_DCACHE_PATH.req_buf_addr,
                    `TB_DCACHE_PATH.req_buf_wdata,
                    `TB_DCACHE_PATH.req_buf_be,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awaddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_bvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_bresp,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_bready);
                linux_exception_trace_count = linux_exception_trace_count + 1;
            end
            // Capture the CP0 exception frame across the clock boundary.  The
            // event line observes the pre-NBA state; the following line
            // observes the state after CP0 has consumed the event.  This is
            // intentionally independent from the broad exception trace and
            // remains bounded for long Linux probes.
            if (linux_exception_frame_trace != 0 &&
                linux_exception_frame_pending != 0) begin
                $display("LINUX_EXCEPTION_FRAME_AFTER cycle=%0d event_cycle=%0d event_pc=%08h event_code=%0d event_int=%b event_bd=%b status=%08h cause=%08h epc=%08h errorepc=%08h bad=%08h entryhi=%08h",
                    linux_trace_cycle,
                    linux_exception_frame_pending_cycle,
                    linux_exception_frame_pending_pc,
                    linux_exception_frame_pending_code,
                    linux_exception_frame_pending_interrupt,
                    linux_exception_frame_pending_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_errorepc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                    {u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_ebase_hi, 12'd0});
                linux_exception_frame_pending = 0;
            end
            if (linux_exception_frame_trace != 0 &&
                linux_exception_frame_trace_count < linux_exception_frame_trace_limit &&
                linux_trace_cycle >= linux_exception_frame_trace_cycle_start &&
                (linux_exception_frame_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_exception_frame_trace_cycle_end) &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept)) begin
                $display("LINUX_EXCEPTION_FRAME_BEFORE cycle=%0d pc=%08h code=%0d int=%b accept=%b eret=%b restore=%b status=%08h cause=%08h epc=%08h errorepc=%08h bad=%08h entryhi=%08h wbpc=%08h wbinst=%08h wbex=%b/%0d/%b/%b bd=%b",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_restore_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_errorepc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                    {u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_ebase_hi, 12'd0},
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_data,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_tlb_refill,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_bd);
                linux_exception_frame_pending = 1;
                linux_exception_frame_pending_cycle = linux_trace_cycle;
                linux_exception_frame_pending_pc = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_pc;
                linux_exception_frame_pending_code = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code;
                linux_exception_frame_pending_interrupt = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept;
                linux_exception_frame_pending_bd = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.exception_bd;
                linux_exception_frame_trace_count = linux_exception_frame_trace_count + 1;
            end
            // Trace architectural GPR writeback only when explicitly enabled.
            // Register and cycle filters keep long Linux probes bounded.
            if (linux_gpr_trace != 0 &&
                linux_gpr_trace_count < linux_gpr_trace_limit &&
                linux_trace_cycle >= linux_gpr_trace_cycle_start &&
                (linux_gpr_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_gpr_trace_cycle_end) &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr != 5'd0 &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr == linux_gpr_trace_reg) ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_restore_req)) begin
                $display("LINUX_GPR_WRITE_TRACE cycle=%0d pc=%08h inst=%08h rd=%0d data=%08h restore=%b restore_s0=%08h s0=%08h sp=%08h ra=%08h epc=%08h cause=%08h status=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_restore_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_restore_gpr[16*32 +: 32],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[16],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[29],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status);
                linux_gpr_trace_count = linux_gpr_trace_count + 1;
            end
            if (linux_wb_trace != 0 &&
                linux_wb_trace_count < linux_wb_trace_limit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                (((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= 32'h8800_d800) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc <= 32'h8800_d850)) ||
                 ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= 32'h8000_0000) &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc < 32'h8000_0200)))) begin
                $display("LINUX_WB_TRACE cycle=%0d pc=%08h inst=%08h valid=%b ex=%b/%0d/%b/%b w=%b/%0d/%08h gpr=%08h/%08h/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_data,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_is_tlb_refill,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[16],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[17],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[19]);
                linux_wb_trace_count = linux_wb_trace_count + 1;
            end
            if (linux_wait_trace != 0 &&
                linux_wait_trace_count < linux_wait_trace_limit &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state &&
                  (!linux_wait_state_prev ||
                   (linux_trace_cycle % 100000 == 0))) ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_is_wait ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_inst == 32'h42000020 ||
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_inst == 32'h42000020 ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst == 32'h42000020) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state))) begin
                $display("LINUX_WAIT_TRACE cycle=%0d ifpc=%08h wbpc=%08h wbinst=%08h wait=%b resume=%08h intr=%b req=%b epc=%08h status=%08h cause=%08h count=%08h compare=%08h intctl_ipti=%0d intctl_vs=%0d",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_resume_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.interrupt_accept,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.intr_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_count,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_compare,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_intctl_ipti,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_intctl_vs);
                linux_wait_trace_count = linux_wait_trace_count + 1;
            end
            // Trace the relocated Linux __delay loop and exception return
            // boundary without enabling the broad instruction trace.  The
            // address window is configurable because KASLR/image layout can
            // move the helper, and the count bound keeps long boots bounded.
            if (linux_delay_trace != 0 &&
                linux_delay_trace_count < linux_delay_trace_limit &&
                linux_trace_cycle >= linux_delay_trace_cycle_start &&
                (linux_delay_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_delay_trace_cycle_end) &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc >= linux_delay_trace_start &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc <= linux_delay_trace_end) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc >= linux_delay_trace_start &&
                  u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc <= linux_delay_trace_end))) begin
                $display("LINUX_DELAY_TRACE cycle=%0d pc=%08h ifpc=%08h inst=%08h valid=%b arch=%b sp=%08h a0=%08h a1=%08h a2=%08h a3=%08h t0=%08h v0=%08h v1=%08h ra=%08h gp=%08h idrs=%08h exrs=%08h exout=%08h exw=%b/%0d idinst=%08h ex=%08h/%08h mem=%08h/%08h d=%b/%b/%08h/%08h/%08h r=%b/%08h w=%b/%0d/%08h eret=%b intr=%b epc=%08h cause=%08h status=%08h bd=%b wb_bd=%b wbds=%08h wbpc=%08h mempc=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[29],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[4],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[5],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[6],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[7],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[8],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[3],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[28],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_val_rs,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_val_rs,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_reg_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_waddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_val_rt,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_val_rt,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[31],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_bd,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_delay_slot_next_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc);
                linux_delay_trace_count = linux_delay_trace_count + 1;
            end
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_valid &&
                ((linux_cacheop_trace_line == 27'd0) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_addr[31:5] ==
                  linux_cacheop_trace_line)) &&
                linux_cacheop_trace_count < linux_cacheop_trace_limit) begin
                $display("LINUX_CACHEOP_TRACE cycle=%0d op=%02h addr=%08h ic=%b done=%b err=%0d daw=%b/%b/%08h/%08h/%b ist=%0d dst=%0d",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_is_icache,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_done,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_error,
                    `TB_DCACHE_PATH.awvalid,
                    `TB_DCACHE_PATH.awready,
                    `TB_DCACHE_PATH.awaddr,
                    `TB_DCACHE_PATH.wdata,
                    `TB_DCACHE_PATH.wlast,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    `TB_DCACHE_PATH.state);
                linux_cacheop_trace_count = linux_cacheop_trace_count + 1;
            end
            if (linux_cp0_trace_count < linux_cp0_trace_limit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_we &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr == 5'd9) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr == 5'd11) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr == 5'd12))) begin
                $display("LINUX_CP0_TRACE cycle=%0d pc=%08h rd=%0d sel=%0d data=%08h count=%08h compare=%08h cause=%08h status=%08h intr=%b",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_sel,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_count,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_compare,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req);
                linux_cp0_trace_count = linux_cp0_trace_count + 1;
            end
            if (linux_ebase_trace != 0 &&
                linux_ebase_trace_count < linux_ebase_trace_limit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_we &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr == 5'd15) &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_sel == 3'd1)) begin
                $display("LINUX_EBASE_WRITE_TRACE cycle=%0d pc=%08h inst=%08h data=%08h status=%08h bev=%b exl=%b ebase_hi=%05h ebase=%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1],
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_ebase_hi,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.ebase_out);
                linux_ebase_trace_count = linux_ebase_trace_count + 1;
            end
            if (linux_vector_trace != 0 &&
                linux_vector_trace_count < linux_vector_trace_limit &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= 32'h8000_0000) &&
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr < 32'h8000_2000))) begin
                $display("LINUX_VECTOR_STORE_TRACE cycle=%0d va=%08h pa=%08h data=%08h be=%h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be);
                linux_vector_trace_count = linux_vector_trace_count + 1;
            end
            // Follow the generated EBase+0x200 instruction line through all
            // cache and DDR boundaries.  The line is configurable because a
            // relocated image may choose a different EBase.  This observes
            // only existing signals and is intentionally bounded.
            if (linux_vector_line_trace != 0 &&
                linux_vector_line_trace_count < linux_vector_line_trace_limit &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                  ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr[31:5] ==
                    (linux_vector_line + 27'h4000000)) ||
                   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr[31:5] ==
                    linux_vector_line))) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr[31:5] ==
                   linux_vector_line)))) begin
                $display("LINUX_VECTOR_LINE_TRACE cycle=%0d pc=%08h if=%b/%08h/%08h ok=%b/%b err=%b/%b ic=%0d req=%b/%08h ar=%b/%b/%08h r=%b/%b/%08h/%0h/%b cnt=%0d install=%b line=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h l2=%0d lar=%b/%b/%08h lr=%b/%b/%08h/%0h/%b ddr=%0d dar=%b/%b/%08h rd=%b/%b/%08h/%0h/%b ram=%08h/%08h/%08h/%08h dc=%0d dreq=%b/%b/%08h/%08h/%h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_data_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_bus_error,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_cache_error,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rlast,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_word_cnt,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.sram_write_en,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[31:0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[63:32],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[95:64],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[127:96],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[159:128],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[191:160],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[223:192],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[255:224],
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.state,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.read_addr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00e08200 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00e08204 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00e08208 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00e0820c >> 2],
                    `TB_DCACHE_PATH.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be);
                linux_vector_line_trace_count = linux_vector_line_trace_count + 1;
            end
            // Follow the known failing instruction line through the actual
            // Linux S3 DDR path. This is opt-in and independently bounded so
            // a stuck refill cannot recreate the previous OOM failure.
            if (linux_ddr_trace != 0 &&
                linux_ddr_trace_count < linux_ddr_trace_limit &&
                ((u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_araddr[31:5] == 27'h40133b) ||
                 (u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.read_addr[31:5] == 27'h40133b) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr[31:5] == 27'h40133b) ||
                 (u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr[31:5] == 27'h40133b))) begin
                $display("LINUX_DDR_TRACE cycle=%0d ic=%0d ar=%b/%b/%08h r=%b/%b/%08h/%0h/%b l2=%0d lar=%b/%b/%08h lr=%b/%b/%08h/%0h/%b ddr=%0d dar=%b/%b/%08h rd=%b/%b/%08h/%0h/%b ram=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h icbuf=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rlast,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.state,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.read_addr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026760 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026764 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026768 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h0002676c >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026770 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026774 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00026778 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h0002677c >> 2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[31:0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[63:32],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[95:64],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[127:96],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[159:128],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[191:160],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[223:192],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_buf[255:224]);
                linux_ddr_trace_count = linux_ddr_trace_count + 1;
            end
            // Follow the later Linux instruction line that previously
            // retired as 0xffffffff. This trace is independently bounded and
            // includes the refill install state so a bad line can be
            // attributed to DDR, L2, AXI routing, or I-cache installation.
            if (linux_late_icache_trace != 0 &&
                linux_late_icache_trace_count < linux_late_icache_trace_limit &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr[31:5] == 27'h484a34) ||
                 (u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr[31:5] == 27'h484a34) ||
                 (u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_araddr[31:5] == 27'h484a34) ||
                 (u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.read_addr[31:5] == 27'h484a34))) begin
                $display("LINUX_LATE_ICACHE_TRACE cycle=%0d ic=%0d req=%b/%08h ar=%b/%b/%08h r=%b/%b/%08h/%0h/%b cnt=%0d err=%b victim=%0d saddr=%0d install=%b line=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h tag=%08h/%08h/%08h/%08h data=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h l2=%0d lar=%b/%b/%08h lr=%b/%b/%08h/%0h/%b ddr=%0d dar=%b/%b/%08h rd=%b/%b/%08h/%0h/%b ram=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.req_buf_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rlast,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_word_cnt,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.refill_error,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.victim_way,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.sram_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.sram_write_en,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[31:0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[63:32],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[95:64],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[127:96],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[159:128],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[191:160],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[223:192],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.full_refill_line[255:224],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.tag_rdata[0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.tag_rdata[1],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.tag_rdata[2],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.tag_rdata[3],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][31:0],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][63:32],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][95:64],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][127:96],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][159:128],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][191:160],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][223:192],
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.data_rdata[0][255:224],
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.state,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_arready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.read_addr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094680 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094684 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094688 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h0009468c >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094690 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094694 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h00094698 >> 2],
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.ram[32'h0009469c >> 2]);
                linux_late_icache_trace_count = linux_late_icache_trace_count + 1;
            end
            if (linux_ddr_write_trace != 0 &&
                linux_ddr_write_trace_count < linux_ddr_write_trace_limit &&
                ((u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awaddr[31:5] == linux_target_trace_line) ||
                 (u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.write_addr[31:5] == linux_target_trace_line) ||
                 (u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_awaddr[31:5] == linux_target_trace_line) ||
                 (u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_awaddr[31:5] == linux_target_trace_line))) begin
                $display("LINUX_DDR_WRITE_TRACE cycle=%0d ddr=%0d aw=%b/%b/%08h/%0h/%b w=%b/%b/%08h/%h/%b active=%b/%0d/%08h l2=%0d maw=%b/%b/%08h mw=%b/%b/%08h/%h/%b saw=%b/%b/%08h sw=%b/%b/%08h/%h/%b dc=%0d daw=%b/%b/%08h dw=%b/%b/%08h/%h/%b",
                    linux_trace_cycle,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.state,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awaddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awlen,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_awid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wdata,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wstrb,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.s_wlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.write_active,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.write_left,
                    u_soc.u_impl.u_memory_subsystem.u_axi_ddr4_controller.write_addr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_awvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_awready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_awaddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_wvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_wready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_wdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_wstrb,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_wlast,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_awvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_awready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_awaddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_wvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_wready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_wdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_wstrb,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_wlast,
                    `TB_DCACHE_PATH.state,
                    `TB_DCACHE_PATH.awvalid,
                    `TB_DCACHE_PATH.awready,
                    `TB_DCACHE_PATH.awaddr,
                    `TB_DCACHE_PATH.wvalid,
                    `TB_DCACHE_PATH.wready,
                    `TB_DCACHE_PATH.wdata,
                    `TB_DCACHE_PATH.wstrb,
                    `TB_DCACHE_PATH.wlast);
                linux_ddr_write_trace_count = linux_ddr_write_trace_count + 1;
            end
            // Record ownership events for one physical line.  Unlike the
            // broad DDR trace above, these conditions are actual channel
            // handshakes, so a held valid signal cannot manufacture repeated
            // writes.  The cache line snapshots make the originating CPU
            // store/refill distinguishable from a downstream protocol issue.
            if (linux_cache_owner_trace != 0 &&
                linux_cache_owner_trace_count < linux_cache_owner_trace_limit) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr_ok &&
                    !`TB_DCACHE_PATH.req_buf_valid &&
                    (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr[31:5] == linux_target_trace_line)) begin
                    $display("LINUX_CACHE_OWNER_TRACE kind=CPU_STORE_ACCEPT cycle=%0d pc=%08h mempc=%08h addr=%08h data=%08h be=%h dstate=%0d reqbuf=%b/%b/%08h/%08h/%h",
                        linux_trace_cycle,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be,
                        `TB_DCACHE_PATH.state,
                        `TB_DCACHE_PATH.req_buf_valid,
                        `TB_DCACHE_PATH.req_buf_we,
                        `TB_DCACHE_PATH.req_buf_addr,
                        `TB_DCACHE_PATH.req_buf_wdata,
                        `TB_DCACHE_PATH.req_buf_be);
                    linux_cache_owner_trace_count = linux_cache_owner_trace_count + 1;
                end else if (`TB_DCACHE_PATH.state == 5'd2 &&
                             `TB_DCACHE_PATH.awvalid && `TB_DCACHE_PATH.awready &&
                             (`TB_DCACHE_PATH.awaddr[31:5] == linux_target_trace_line)) begin
                    $display("LINUX_CACHE_OWNER_TRACE kind=DCACHE_WB_AW cycle=%0d pc=%08h mempc=%08h aw=%08h victim_way=%0d victim_tag=%08h line=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h reqbuf=%b/%b/%08h/%08h/%h",
                        linux_trace_cycle,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                        `TB_DCACHE_PATH.awaddr,
                        `TB_DCACHE_PATH.victim_way,
                        `TB_DCACHE_PATH.victim_tag_entry,
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][31:0],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][63:32],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][95:64],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][127:96],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][159:128],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][191:160],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][223:192],
                        `TB_DCACHE_PATH.data_rdata[`TB_DCACHE_PATH.victim_way][255:224],
                        `TB_DCACHE_PATH.req_buf_valid,
                        `TB_DCACHE_PATH.req_buf_we,
                        `TB_DCACHE_PATH.req_buf_addr,
                        `TB_DCACHE_PATH.req_buf_wdata,
                        `TB_DCACHE_PATH.req_buf_be);
                    linux_cache_owner_trace_count = linux_cache_owner_trace_count + 1;
                end else if (`TB_DCACHE_PATH.state == 5'd3 &&
                             `TB_DCACHE_PATH.wvalid && `TB_DCACHE_PATH.wready &&
                             (`TB_DCACHE_PATH.awaddr[31:5] == linux_target_trace_line)) begin
                    $display("LINUX_CACHE_OWNER_TRACE kind=DCACHE_WB_W cycle=%0d pc=%08h mempc=%08h aw=%08h word=%0d wdata=%08h wstrb=%h wlast=%b victim_way=%0d victim_tag=%08h",
                        linux_trace_cycle,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                        `TB_DCACHE_PATH.awaddr,
                        `TB_DCACHE_PATH.word_cnt,
                        `TB_DCACHE_PATH.wdata,
                        `TB_DCACHE_PATH.wstrb,
                        `TB_DCACHE_PATH.wlast,
                        `TB_DCACHE_PATH.victim_way,
                        `TB_DCACHE_PATH.victim_tag_entry);
                    linux_cache_owner_trace_count = linux_cache_owner_trace_count + 1;
                end else if (`TB_DCACHE_PATH.state == 5'd6 &&
                             `TB_DCACHE_PATH.rready && `TB_DCACHE_PATH.rvalid &&
                             (`TB_DCACHE_PATH.araddr[31:5] == linux_target_trace_line)) begin
                    $display("LINUX_CACHE_OWNER_TRACE kind=DCACHE_REFILL_R cycle=%0d pc=%08h mempc=%08h ar=%08h word=%0d rdata=%08h rresp=%h rlast=%b linebuf=%08h/%08h/%08h/%08h/%08h/%08h/%08h/%08h reqbuf=%b/%b/%08h/%08h/%h",
                        linux_trace_cycle,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                        u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                        `TB_DCACHE_PATH.araddr,
                        `TB_DCACHE_PATH.word_cnt,
                        `TB_DCACHE_PATH.rdata,
                        `TB_DCACHE_PATH.rresp,
                        `TB_DCACHE_PATH.rlast,
                        `TB_DCACHE_PATH.line_buf[31:0],
                        `TB_DCACHE_PATH.line_buf[63:32],
                        `TB_DCACHE_PATH.line_buf[95:64],
                        `TB_DCACHE_PATH.line_buf[127:96],
                        `TB_DCACHE_PATH.line_buf[159:128],
                        `TB_DCACHE_PATH.line_buf[191:160],
                        `TB_DCACHE_PATH.line_buf[223:192],
                        `TB_DCACHE_PATH.line_buf[255:224],
                        `TB_DCACHE_PATH.req_buf_valid,
                        `TB_DCACHE_PATH.req_buf_we,
                        `TB_DCACHE_PATH.req_buf_addr,
                        `TB_DCACHE_PATH.req_buf_wdata,
                        `TB_DCACHE_PATH.req_buf_be);
                    linux_cache_owner_trace_count = linux_cache_owner_trace_count + 1;
                end
            end
            if (linux_target_dside_trace != 0 &&
                linux_target_dside_trace_count < linux_target_dside_trace_limit &&
                linux_trace_cycle >= linux_target_trace_cycle_start &&
                (linux_target_trace_cycle_end == 0 ||
                 linux_trace_cycle <= linux_target_trace_cycle_end) &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr[31:5] == linux_target_trace_line) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_ex_out[31:5] == linux_target_trace_line) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_addr[31:5] == linux_target_trace_line))) begin
                $display("LINUX_TARGET_DSIDE_TRACE cycle=%0d pc=%08h mempc=%08h va=%08h pa=%08h we=%b wdata=%08h be=%h memop=%03h done=%b req=%b dstate=%0d reqbuf=%b/%b/%08h/%08h/%h victim=%0d/%08h",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_be,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_op,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_done,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_valid,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_we,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.req_buf_be,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.victim_way,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.victim_tag_entry);
                linux_target_dside_trace_count = linux_target_dside_trace_count + 1;
            end
            if (linux_progress_trace != 0 &&
                ((linux_trace_cycle < 20) ||
                 (linux_trace_cycle % 100000 == 0) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr[31:5] == 27'h045062c)))) begin
                $display("LINUX_PROGRESS_TRACE cycle=%0d pc=%08h", linux_trace_cycle,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc);
            end
            if (linux_refill_trace != 0 &&
                ((linux_trace_cycle < 20) ||
                 (linux_trace_cycle % 100000 == 0) ||
                 (u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid &&
                  (u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr[31:5] == 27'h045062c)))) begin
                $display("LINUX_REFILL_TRACE cycle=%0d pc=%08h if=%b/%08h/%08h mmui=%b/%0d k=%b tlbi=%b/%b/%b/%08h ic=%0d ar=%b/%b/%08h r=%b/%b/%08h/%0h/%b l2=%0d lar=%b/%b/%08h lr=%b/%b/%08h/%0h/%b ddr=%0d dar=%b/%b/%08h dr=%b/%b/%08h/%0h/%b cpu=%b/%b/%08h/%08h stall=%b dc=%0d aw=%b/%b/%08h w=%b/%b/%08h/%h/%b b=%b/%b da=%b/%b/%08h/%0h dr=%b/%b/%08h/%0h/%b",
                    linux_trace_cycle,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_ok,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_i_fault_type,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_kernel_mode,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_hit,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_multi_hit,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_v,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mmu_ilookup_pfn,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.arready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.araddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rready,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rdata,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rid,
                    u_soc.u_impl.u_core_subsystem.u_core.u_icache.rlast,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_arready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rready,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rdata,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rid,
                    u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.m_rlast,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.rd_state[0],
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_arvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_arready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_araddr,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rvalid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rready,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rdata,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rid,
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_rlast,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.global_stall,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.state,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.awvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.awready,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.awaddr,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.wvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.wready,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.wdata,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.wstrb,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.wlast,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.bvalid,
                    u_soc.u_impl.u_core_subsystem.u_core.g_blocking.u_dcache.bready,
                    u_soc.u_impl.m1_arvalid,
                    u_soc.u_impl.m1_arready,
                    u_soc.u_impl.m1_araddr,
                    u_soc.u_impl.m1_arlen,
                    u_soc.u_impl.m1_rvalid,
                    u_soc.u_impl.m1_rready,
                    u_soc.u_impl.m1_rdata,
                    u_soc.u_impl.m1_rid,
                    u_soc.u_impl.m1_rlast);
            end
            linux_wait_state_prev =
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state;
            linux_global_stall_prev =
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.global_stall;
            linux_wait_trace_prev =
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wait_state;
            linux_intr_trace_prev =
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.intr_req;
        end
    end

    initial begin
        linux_trace_limit = 0;
        if (!$value$plusargs("LINUX_TRACE_LIMIT=%d", linux_trace_limit)) begin end
        linux_refill_trace = 0;
        if (!$value$plusargs("LINUX_REFILL_TRACE=%d", linux_refill_trace)) begin end
        linux_progress_trace = 1;
        if (!$value$plusargs("LINUX_PROGRESS_TRACE=%d", linux_progress_trace)) begin end
        linux_stall_trace = 0;
        if (!$value$plusargs("LINUX_STALL_TRACE=%d", linux_stall_trace)) begin end
        linux_stall_trace_limit = 256;
        if (!$value$plusargs("LINUX_STALL_TRACE_LIMIT=%d", linux_stall_trace_limit)) begin end
        linux_stall_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_STALL_TRACE_CYCLE_START=%d", linux_stall_trace_cycle_start)) begin end
        linux_stall_trace_pc = 32'd0;
        if (!$value$plusargs("LINUX_STALL_TRACE_PC=%h", linux_stall_trace_pc)) begin end
        linux_stall_trace_count = 0;
        linux_global_stall_prev = 1'b0;
        linux_wait_trace_prev = 1'b0;
        linux_intr_trace_prev = 1'b0;
        linux_exception_trace = 0;
        if (!$value$plusargs("LINUX_EXCEPTION_TRACE=%d", linux_exception_trace)) begin end
        linux_exception_trace_limit = 256;
        if (!$value$plusargs("LINUX_EXCEPTION_TRACE_LIMIT=%d", linux_exception_trace_limit)) begin end
        linux_exception_trace_count = 0;
        linux_exception_frame_trace = 0;
        if (!$value$plusargs("LINUX_EXCEPTION_FRAME_TRACE=%d", linux_exception_frame_trace)) begin end
        linux_exception_frame_trace_limit = 64;
        if (!$value$plusargs("LINUX_EXCEPTION_FRAME_TRACE_LIMIT=%d", linux_exception_frame_trace_limit)) begin end
        linux_exception_frame_trace_count = 0;
        linux_exception_frame_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_EXCEPTION_FRAME_TRACE_CYCLE_START=%d", linux_exception_frame_trace_cycle_start)) begin end
        linux_exception_frame_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_EXCEPTION_FRAME_TRACE_CYCLE_END=%d", linux_exception_frame_trace_cycle_end)) begin end
        linux_exception_frame_pending = 0;
        linux_exception_frame_pending_cycle = 0;
        linux_exception_frame_pending_pc = 32'd0;
        linux_exception_frame_pending_code = 5'd0;
        linux_exception_frame_pending_interrupt = 1'b0;
        linux_exception_frame_pending_bd = 1'b0;
        linux_ebase_trace = 0;
        if (!$value$plusargs("LINUX_EBASE_TRACE=%d", linux_ebase_trace)) begin end
        linux_ebase_trace_limit = 64;
        if (!$value$plusargs("LINUX_EBASE_TRACE_LIMIT=%d", linux_ebase_trace_limit)) begin end
        linux_ebase_trace_count = 0;
        linux_wb_trace = 0;
        if (!$value$plusargs("LINUX_WB_TRACE=%d", linux_wb_trace)) begin end
        linux_wb_trace_limit = 256;
        if (!$value$plusargs("LINUX_WB_TRACE_LIMIT=%d", linux_wb_trace_limit)) begin end
        linux_wb_trace_count = 0;
        linux_mode_trace = 0;
        if (!$value$plusargs("LINUX_MODE_TRACE=%d", linux_mode_trace)) begin end
        linux_mode_trace_limit = 64;
        if (!$value$plusargs("LINUX_MODE_TRACE_LIMIT=%d", linux_mode_trace_limit)) begin end
        linux_mode_trace_count = 0;
        linux_cpu_kernel_prev = 1'b1;
        linux_pc_trace = 0;
        if (!$value$plusargs("LINUX_PC_TRACE=%d", linux_pc_trace)) begin end
        linux_pc_trace_limit = 256;
        if (!$value$plusargs("LINUX_PC_TRACE_LIMIT=%d", linux_pc_trace_limit)) begin end
        linux_pc_trace_count = 0;
        linux_pc_trace_retire_only = 0;
        if (!$value$plusargs("LINUX_PC_TRACE_RETIRE_ONLY=%d", linux_pc_trace_retire_only)) begin end
        linux_pc_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_PC_TRACE_CYCLE_START=%d", linux_pc_trace_cycle_start)) begin end
        linux_pc_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_PC_TRACE_CYCLE_END=%d", linux_pc_trace_cycle_end)) begin end
        linux_pc_trace_start = 32'd0;
        if (!$value$plusargs("LINUX_PC_TRACE_START=%h", linux_pc_trace_start)) begin end
        linux_pc_trace_end = 32'd0;
        if (!$value$plusargs("LINUX_PC_TRACE_END=%h", linux_pc_trace_end)) begin end
        linux_wait_trace = 0;
        if (!$value$plusargs("LINUX_WAIT_TRACE=%d", linux_wait_trace)) begin end
        linux_wait_trace_limit = 256;
        if (!$value$plusargs("LINUX_WAIT_TRACE_LIMIT=%d", linux_wait_trace_limit)) begin end
        linux_wait_trace_count = 0;
        linux_wait_state_prev = 1'b0;
        linux_vector_trace = 0;
        if (!$value$plusargs("LINUX_VECTOR_TRACE=%d", linux_vector_trace)) begin end
        linux_vector_trace_limit = 1000;
        if (!$value$plusargs("LINUX_VECTOR_TRACE_LIMIT=%d", linux_vector_trace_limit)) begin end
        linux_vector_trace_count = 0;
        // Diagnostic streams are opt-in.  A direct simv invocation must not
        // emit thousands of cache-maintenance records by default.
        linux_cacheop_trace_limit = 0;
        if (!$value$plusargs("LINUX_CACHEOP_TRACE_LIMIT=%d", linux_cacheop_trace_limit)) begin end
        linux_cacheop_trace_line = 27'd0;
        if (!$value$plusargs("LINUX_CACHEOP_TRACE_LINE=%h", linux_cacheop_trace_line)) begin end
        linux_cacheop_trace_count = 0;
        linux_cp0_trace_limit = 0;
        if (!$value$plusargs("LINUX_CP0_TRACE_LIMIT=%d", linux_cp0_trace_limit)) begin end
        linux_cp0_trace_count = 0;
        linux_ddr_trace = 0;
        if (!$value$plusargs("LINUX_DDR_TRACE=%d", linux_ddr_trace)) begin end
        linux_ddr_trace_limit = 200;
        if (!$value$plusargs("LINUX_DDR_TRACE_LIMIT=%d", linux_ddr_trace_limit)) begin end
        linux_ddr_trace_count = 0;
        linux_late_icache_trace = 0;
        if (!$value$plusargs("LINUX_LATE_ICACHE_TRACE=%d", linux_late_icache_trace)) begin end
        linux_late_icache_trace_limit = 160;
        if (!$value$plusargs("LINUX_LATE_ICACHE_TRACE_LIMIT=%d", linux_late_icache_trace_limit)) begin end
        linux_late_icache_trace_count = 0;
        linux_ddr_write_trace = 0;
        if (!$value$plusargs("LINUX_DDR_WRITE_TRACE=%d", linux_ddr_write_trace)) begin end
        linux_ddr_write_trace_limit = 240;
        if (!$value$plusargs("LINUX_DDR_WRITE_TRACE_LIMIT=%d", linux_ddr_write_trace_limit)) begin end
        linux_ddr_write_trace_count = 0;
        linux_target_dside_trace = 0;
        if (!$value$plusargs("LINUX_TARGET_DSIDE_TRACE=%d", linux_target_dside_trace)) begin end
        linux_target_dside_trace_limit = 160;
        if (!$value$plusargs("LINUX_TARGET_DSIDE_TRACE_LIMIT=%d", linux_target_dside_trace_limit)) begin end
        linux_target_dside_trace_count = 0;
        linux_target_trace_line = 27'h40133b;
        if (!$value$plusargs("LINUX_TARGET_TRACE_LINE=%h", linux_target_trace_line)) begin end
        linux_target_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_TARGET_TRACE_CYCLE_START=%d", linux_target_trace_cycle_start)) begin end
        linux_target_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_TARGET_TRACE_CYCLE_END=%d", linux_target_trace_cycle_end)) begin end
        linux_delay_trace = 0;
        if (!$value$plusargs("LINUX_DELAY_TRACE=%d", linux_delay_trace)) begin end
        linux_delay_trace_limit = 256;
        if (!$value$plusargs("LINUX_DELAY_TRACE_LIMIT=%d", linux_delay_trace_limit)) begin end
        linux_delay_trace_count = 0;
        linux_delay_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_DELAY_TRACE_CYCLE_START=%d", linux_delay_trace_cycle_start)) begin end
        linux_delay_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_DELAY_TRACE_CYCLE_END=%d", linux_delay_trace_cycle_end)) begin end
        linux_delay_trace_start = 32'h8924_34e0;
        if (!$value$plusargs("LINUX_DELAY_TRACE_START=%h", linux_delay_trace_start)) begin end
        linux_delay_trace_end = 32'h8924_34e4;
        if (!$value$plusargs("LINUX_DELAY_TRACE_END=%h", linux_delay_trace_end)) begin end
        linux_gpr_trace = 0;
        if (!$value$plusargs("LINUX_GPR_TRACE=%d", linux_gpr_trace)) begin end
        linux_gpr_trace_limit = 256;
        if (!$value$plusargs("LINUX_GPR_TRACE_LIMIT=%d", linux_gpr_trace_limit)) begin end
        linux_gpr_trace_count = 0;
        linux_gpr_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_GPR_TRACE_CYCLE_START=%d", linux_gpr_trace_cycle_start)) begin end
        linux_gpr_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_GPR_TRACE_CYCLE_END=%d", linux_gpr_trace_cycle_end)) begin end
        linux_gpr_trace_reg = 5'd16;
        if (!$value$plusargs("LINUX_GPR_TRACE_REG=%d", linux_gpr_trace_reg)) begin end
        linux_uart_trace = 0;
        if (!$value$plusargs("LINUX_UART_TRACE=%d", linux_uart_trace)) begin end
        linux_uart_trace_limit = 256;
        if (!$value$plusargs("LINUX_UART_TRACE_LIMIT=%d", linux_uart_trace_limit)) begin end
        linux_uart_trace_count = 0;
        linux_panic_trace = 0;
        if (!$value$plusargs("LINUX_PANIC_TRACE=%d", linux_panic_trace)) begin end
        linux_panic_trace_limit = 32;
        if (!$value$plusargs("LINUX_PANIC_TRACE_LIMIT=%d", linux_panic_trace_limit)) begin end
        linux_panic_trace_count = 0;
        linux_panic_trace_start = 32'h8924_5cbc;
        if (!$value$plusargs("LINUX_PANIC_TRACE_START=%h", linux_panic_trace_start)) begin end
        linux_panic_trace_end = 32'h8924_6010;
        if (!$value$plusargs("LINUX_PANIC_TRACE_END=%h", linux_panic_trace_end)) begin end
        linux_cache_owner_trace = 0;
        if (!$value$plusargs("LINUX_CACHE_OWNER_TRACE=%d", linux_cache_owner_trace)) begin end
        linux_cache_owner_trace_limit = 256;
        if (!$value$plusargs("LINUX_CACHE_OWNER_TRACE_LIMIT=%d", linux_cache_owner_trace_limit)) begin end
        linux_cache_owner_trace_count = 0;
        linux_tlb_trace = 0;
        if (!$value$plusargs("LINUX_TLB_TRACE=%d", linux_tlb_trace)) begin end
        linux_tlb_trace_limit = 256;
        if (!$value$plusargs("LINUX_TLB_TRACE_LIMIT=%d", linux_tlb_trace_limit)) begin end
        linux_tlb_trace_count = 0;
        linux_tlb_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_TLB_TRACE_CYCLE_START=%d", linux_tlb_trace_cycle_start)) begin end
        linux_tlb_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_TLB_TRACE_CYCLE_END=%d", linux_tlb_trace_cycle_end)) begin end
        linux_fault_trace = 0;
        if (!$value$plusargs("LINUX_FAULT_TRACE=%d", linux_fault_trace)) begin end
        linux_fault_trace_limit = 256;
        if (!$value$plusargs("LINUX_FAULT_TRACE_LIMIT=%d", linux_fault_trace_limit)) begin end
        linux_fault_trace_count = 0;
        linux_fault_trace_start = 32'hc000_0000;
        if (!$value$plusargs("LINUX_FAULT_TRACE_START=%h", linux_fault_trace_start)) begin end
        linux_fault_trace_end = 32'hc001_0000;
        if (!$value$plusargs("LINUX_FAULT_TRACE_END=%h", linux_fault_trace_end)) begin end
        linux_fault_trace_cycle_start = 0;
        if (!$value$plusargs("LINUX_FAULT_TRACE_CYCLE_START=%d", linux_fault_trace_cycle_start)) begin end
        linux_fault_trace_cycle_end = 0;
        if (!$value$plusargs("LINUX_FAULT_TRACE_CYCLE_END=%d", linux_fault_trace_cycle_end)) begin end
        linux_vector_line_trace = 0;
        if (!$value$plusargs("LINUX_VECTOR_LINE_TRACE=%d", linux_vector_line_trace)) begin end
        linux_vector_line_trace_limit = 256;
        if (!$value$plusargs("LINUX_VECTOR_LINE_TRACE_LIMIT=%d", linux_vector_line_trace_limit)) begin end
        linux_vector_line_trace_count = 0;
        linux_vector_line = 27'h470410;
        if (!$value$plusargs("LINUX_VECTOR_LINE=%h", linux_vector_line)) begin end
    end
`endif

`ifdef TB_L1_AXI_ERROR_RESET_STRESS
    // Exercise reset while the injected refill is genuinely in flight.  The
    // error model and L1 state both reset, so the restarted firmware must
    // observe the injected fault again and complete precise ErrorEPC recovery.
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.n_mshr_occ != 0);
        $display("L1_AXI_ERROR_RESET: refill in flight, asserting reset");
        #20 rst_n = 1'b0;
        #50 rst_n = 1'b1;
        $display("L1_AXI_ERROR_RESET: reset released");
    end
`endif

`ifdef TB_L1_AXI_ERROR_TWO_RESET_STRESS
    // Exercise reset after both independent L1 MSHRs are allocated.  The
    // cache and DDR model must discard the pre-reset transactions; the
    // restarted firmware then re-issues both faults and recovers precisely.
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.n_mshr_occ >= 2);
        $display("L1_AXI_TWO_ERROR_RESET: two refills in flight mshr=%0d, asserting reset",
                 u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.n_mshr_occ);
        #20 rst_n = 1'b0;
        #50 rst_n = 1'b1;
        $display("L1_AXI_TWO_ERROR_RESET: reset released");
    end
`endif

`ifdef SOC_L2_E2E
    integer l2_e2e_ar_total;
    integer l2_e2e_aw_total;
    integer l2_e2e_w_total;
    integer l2_e2e_b_total;
    integer l2_e2e_ar_target;
    integer l2_e2e_aw_target;
    localparam [31:0] L2_E2E_TARGET_LINE = 32'h00008000;
`endif
    
    wire [31:0] gpio_pins;
`ifdef SOC_UART_EXTERNAL_RX_WAVEFORM
    reg uart_rx = 1'b1;
`else
    wire uart_rx = 1'b1;
`endif
`ifdef SOC_UART_CTS_FLOW_CONTROL
    reg uart_cts_n = 1'b1;
`else
    wire uart_cts_n = 1'b0;
`endif
    wire uart_dsr_n = 1'b0;
    wire uart_dcd_n = 1'b0;
    wire uart_ri_n = 1'b1;
    reg uart_tx_seen_low;
`ifdef SOC_UART_CTS_FLOW_CONTROL
    reg uart_cts_release_seen;
    reg uart_tx_low_before_cts_release;
`endif
    
    // Pull down GPIOs weakly to avoid 'z' in simulation if not driven
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate
    
    mips_soc #(
`ifdef SOC_ENABLE_DUAL_CORE
               .ENABLE_DUAL_CORE(1'b1),
`endif
`ifdef SOC_HARDWARE_WALKER_ENABLE
               .ENABLE_HARDWARE_WALKER(1'b1),
               .HARDWARE_WALKER_PTBR(32'h0000_1000),
`endif
               .ENABLE_UART_PINS(1'b1),
`ifdef SOC_ENABLE_DDR4_STATUS
               .ENABLE_DDR4_STATUS(1'b1)
`else
               .ENABLE_DDR4_STATUS(1'b0)
`endif
`ifdef SOC_DDR4_STATUS_FATAL
               ,.ENABLE_DDR4_STATUS_FATAL(1'b1)
`else
               ,.ENABLE_DDR4_STATUS_FATAL(1'b0)
`endif
    ) u_soc(
        .clk        (clk),
        .rst_n      (rst_n),
        .gpio_pins  (gpio_pins),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .uart_cts_n (uart_cts_n),
        .uart_rts_n (uart_rts_n),
        .uart_dsr_n (uart_dsr_n),
        .uart_dtr_n (uart_dtr_n),
        .uart_dcd_n (uart_dcd_n),
        .uart_ri_n  (uart_ri_n),
        .spi_sclk   (spi_sclk),
        .spi_cs_n   (spi_cs_n),
        .spi_mosi   (spi_mosi),
        .spi_miso   (1'b0),
        .qspi_io    (qspi_io),
        .tck        (tck_r),
        .tms        (tms_r),
        .tdi        (tdi_r),
        .tdo        (tdo)
    );

    wire        legacy_mailbox_valid = legacy_obs_if.mailbox_valid;
    wire [31:0] legacy_mailbox_wdata = legacy_obs_if.mailbox_wdata;
    wire [31:0] legacy_trace_pc = legacy_obs_if.trace_pc;
    wire        legacy_cp0_except_req = legacy_obs_if.cp0_except_req;
    wire [4:0]  legacy_cp0_except_code = legacy_obs_if.cp0_except_code;
    wire        legacy_cp0_intr_req = legacy_obs_if.cp0_intr_req;
    wire        legacy_cp0_exl = legacy_obs_if.cp0_exl;
    wire        legacy_cp0_eret = legacy_obs_if.cp0_eret;
    assign legacy_uart_tx_valid = legacy_obs_if.uart_tx_valid;
    assign legacy_uart_tx_data  = legacy_obs_if.uart_tx_data;
    wire        legacy_core_global_stall = legacy_obs_if.core_global_stall;
    wire [4:0]  legacy_dcache_state = legacy_obs_if.dcache_state;
    wire [4:0]  legacy_dcache_next_state = legacy_obs_if.dcache_next_state;
    wire [31:0] legacy_dcache_req_buf_addr = legacy_obs_if.dcache_req_buf_addr;
    wire        legacy_dcache_req_buf_we = legacy_obs_if.dcache_req_buf_we;
    wire        legacy_dcache_uncacheable = legacy_obs_if.dcache_uncacheable;
    wire        legacy_dcache_awvalid = legacy_obs_if.dcache_awvalid;
    wire        legacy_dcache_wvalid = legacy_obs_if.dcache_wvalid;
    wire        legacy_dcache_bready = legacy_obs_if.dcache_bready;
    
    // Clock Generation
/* obsolete L1 debug block removed from the active testbench
            $display("ROBEX t=%0t pc=%08h code=%0d memex=%b codein=%0d cache=%b/%b op=%b/%b bus=%b/%b adel=%b/%b owner=%b/%b rsp=%b/%h dstate=%0d r=%b/%b/%h b=%b/%b/%h",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_pc_plus_8 - 8,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_code_out,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_req_out,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_except_code,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_cache_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_error,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_cache_op_fault_seen,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_op_valid,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_bus_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_bus_error,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_adel_exception,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_ades_exception,
                     `TB_DCACHE_PATH.legacy_sel, `TB_DCACHE_PATH.l1_sel,
                     `TB_DCACHE_PATH.n_rsp_valid, `TB_DCACHE_PATH.n_rsp_id,
                     `TB_DCACHE_PATH.state,
                     `TB_DCACHE_PATH.rready, `TB_DCACHE_PATH.rvalid,
                     `TB_DCACHE_PATH.rresp,
                     `TB_DCACHE_PATH.bready, `TB_DCACHE_PATH.bvalid,
                     `TB_DCACHE_PATH.bresp);
        if (rst_n && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req &&
            u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_code == 5'h1e)
            $display("CACHEERR t=%0t pc=%08h wbpc=%08h wbcode=%0d wbreq=%b if=%b/%b mem=%b/%b rob=%b rsp=%h err=%b",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_cache_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_bus_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_cache_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_bus_fault,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.rob_complete_valid,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_resp_id,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_error);
        if (rst_n && `TB_DCACHE_PATH.n_rsp_valid)
            $display("L1RSP t=%0t id=%h err=%b data=%08h cpu_id=%h req=%b/%b addr=%08h pc=%08h bridge=%0d/%08h mline=%08h/%08h",
                     $time, `TB_DCACHE_PATH.n_rsp_id, `TB_DCACHE_PATH.n_rsp_error,
                     `TB_DCACHE_PATH.n_rsp_data,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req_id,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     `TB_DCACHE_PATH.u_bridge.state, `TB_DCACHE_PATH.u_bridge.addr_q,
                     `TB_DCACHE_PATH.u_l1.mline[0], `TB_DCACHE_PATH.u_l1.mline[1]);
        if (rst_n && `TB_DCACHE_PATH.l1_req && `TB_DCACHE_PATH.n_cpu_ready)
            $strobe("L1REQ t=%0t id=%h addr=%08h pc=%08h done/read/en/raw=%b/%b/%b/%b req/ok=%b/%b ready/latch=%b/%b flush/exfl/eff=%b/%b/%b eret/intr=%b/%b",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req_id,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_done,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_read,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_enable_nb_load,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req_raw,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr_ok,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.rob_alloc_ready,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_mem_addr_accepted,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.flush_ex_mem,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.exception_flush,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.intr_req);
        if (rst_n && l1_trace_count < 80 &&
            ((u_soc.u_impl.u_soc_fabric.s0_awvalid && u_soc.u_impl.u_soc_fabric.s0_awready) ||
             (u_soc.u_impl.u_soc_fabric.s0_wvalid && u_soc.u_impl.u_soc_fabric.s0_wready) ||
             (u_soc.u_impl.u_soc_fabric.s0_bvalid && u_soc.u_impl.u_soc_fabric.s0_bready) ||
             (u_soc.u_impl.u_soc_fabric.s0_arvalid && u_soc.u_impl.u_soc_fabric.s0_arready) ||
             (u_soc.u_impl.u_soc_fabric.s0_rvalid && u_soc.u_impl.u_soc_fabric.s0_rready))) begin
            $display("L1TRACE t=%0t aw=%b/%b/%08h w=%b/%b/%08h/%b b=%b/%b ar=%b/%b/%08h r=%b/%b/%08h/%b l2=%0d owner=%b/%b/%b l1=%b/%b bridge=%0d xwr=%b/%b/%0d/%0d",
                     $time,
                     u_soc.u_impl.u_soc_fabric.s0_awvalid, u_soc.u_impl.u_soc_fabric.s0_awready,
                     u_soc.u_impl.u_soc_fabric.s0_awaddr,
                     u_soc.u_impl.u_soc_fabric.s0_wvalid, u_soc.u_impl.u_soc_fabric.s0_wready,
                     u_soc.u_impl.u_soc_fabric.s0_wdata, u_soc.u_impl.u_soc_fabric.s0_wlast,
                     u_soc.u_impl.u_soc_fabric.s0_bvalid, u_soc.u_impl.u_soc_fabric.s0_bready,
                     u_soc.u_impl.u_soc_fabric.s0_arvalid, u_soc.u_impl.u_soc_fabric.s0_arready,
                     u_soc.u_impl.u_soc_fabric.s0_araddr,
                     u_soc.u_impl.u_soc_fabric.s0_rvalid, u_soc.u_impl.u_soc_fabric.s0_rready,
                     u_soc.u_impl.u_soc_fabric.s0_rdata, u_soc.u_impl.u_soc_fabric.s0_rlast,
                     u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                     `TB_DCACHE_PATH.legacy_sel, `TB_DCACHE_PATH.l1_sel,
                     `TB_DCACHE_PATH.legacy_aw_seen,
                     `TB_DCACHE_PATH.n_awvalid, `TB_DCACHE_PATH.n_wvalid,
                     `TB_DCACHE_PATH.u_bridge.state,
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_valid[0],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_wdone[0],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_wpend[0],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_cnt[0]);
            l1_trace_count = l1_trace_count + 1;
        end
    end
`endif

*/
`ifdef TB_L1_NONBLOCKING_DEBUG
    always @(posedge clk) begin
        if (rst_n && (u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.legacy_sel ||
                      u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.l_awvalid ||
                      u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.bvalid ||
                      u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.state == 5'd10)) begin
            $display("NBDBG t=%0t state=%0d legacy=%b awseen=%b mux_aw=%b/%b/%08h mux_w=%b/%b/%08h/%b mux_b=%b/%b/%b l_aw=%b l_w=%b l_b=%b x_m1_aw=%b/%b/%08h x_m1_w=%b/%b/%08h/%b x_m1_b=%b/%b/%b x_s1_aw=%b/%b/%08h x_s1_w=%b/%b/%08h/%b x_s1_b=%b/%b/%b wr1=%b/%b/%0d/%0d",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.state,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.legacy_sel,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.legacy_aw_seen,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.awvalid,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.awready,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.awaddr,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.wvalid,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.wready,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.wdata,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.wlast,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.bvalid,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.bready,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.bresp,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.l_awvalid,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.l_wvalid,
                     u_soc.u_impl.u_core_subsystem.u_core.g_l1_nonblocking.u_dcache.l_bready,
                     u_soc.u_impl.u_soc_fabric.m1_awvalid,
                     u_soc.u_impl.u_soc_fabric.m1_awready,
                     u_soc.u_impl.u_soc_fabric.m1_awaddr,
                     u_soc.u_impl.u_soc_fabric.m1_wvalid,
                     u_soc.u_impl.u_soc_fabric.m1_wready,
                     u_soc.u_impl.u_soc_fabric.m1_wdata,
                     u_soc.u_impl.u_soc_fabric.m1_wlast,
                     u_soc.u_impl.u_soc_fabric.m1_bvalid,
                     u_soc.u_impl.u_soc_fabric.m1_bready,
                     u_soc.u_impl.u_soc_fabric.m1_bresp,
                     u_soc.u_impl.u_soc_fabric.s1_awvalid,
                     u_soc.u_impl.u_soc_fabric.s1_awready,
                     u_soc.u_impl.u_soc_fabric.s1_awaddr,
                     u_soc.u_impl.u_soc_fabric.s1_wvalid,
                     u_soc.u_impl.u_soc_fabric.s1_wready,
                     u_soc.u_impl.u_soc_fabric.s1_wdata,
                     u_soc.u_impl.u_soc_fabric.s1_wlast,
                     u_soc.u_impl.u_soc_fabric.s1_bvalid,
                     u_soc.u_impl.u_soc_fabric.s1_bready,
                     u_soc.u_impl.u_soc_fabric.s1_bresp,
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_valid[1],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_wdone[1],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_wpend[1],
                     u_soc.u_impl.u_soc_fabric.u_xbar.wr_cnt[1]);
        end
    end
`endif
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Sequence
    initial begin
        rst_n = 0;
        cp0_interrupt_count = 0;
        cp0_syscall_count = 0;
        cp0_ri_count = 0;
        cp0_adel_count = 0;
        cp0_cacheerr_count = 0;
        cp0_eret_count = 0;
        dual_core_ipi_count = 0;
        dual_core_reverse_ipi_count = 0;
        dual_core_reset_count = 0;
        dual_core_exception_count = 0;
`ifdef TB_MMU_HW_WALKER_AD
        hw_ad_aw_count = 0;
        hw_ad_w_count = 0;
        hw_ad_delayed_w_count = 0;
        hw_ad_reset_seen = 0;
        hw_ad_write_error_seen = 0;
        hw_ad_downstream_error_seen = 0;
        hw_ad_aw_pending = 1'b0;
        hw_ad_aw_time = 0;
`endif
`ifdef TB_L1_MAINTENANCE
        l1_maintenance_count = 0;
        l1_maintenance_refill_count = 0;
        l1_maintenance_waiting_refill = 1'b0;
`endif
`ifdef DMA_EVENT_TRACE
        dma_event_fd = 0;
        dma_event_path = "dma_rtl_events.jsonl";
        dma_done_seen = 0;
        dma_err_seen = 0;
        dma_busy_seen = 0;
        dma_irq_seen = 0;
        if (!$value$plusargs("DMA_EVENT_TRACE=%s", dma_event_path)) begin end
        dma_event_fd = $fopen(dma_event_path, "w");
`endif
        uart_tx_seen_low = 1'b0;
`ifdef SOC_UART_CTS_FLOW_CONTROL
        uart_cts_release_seen = 1'b0;
        uart_tx_low_before_cts_release = 1'b0;
`endif

        // Initialize memory with an explicit firmware artifact before reset release.
        firmware_hex = "firmware.hex";
        if ($value$plusargs("FW_HEX=%s", firmware_hex)) begin
            $display("tb_mips_soc: loading firmware from %0s", firmware_hex);
        end else begin
            $display("tb_mips_soc: loading default firmware.hex");
        end
        u_soc.preload_sram_hex(firmware_hex);

`ifdef TB_LINUX_BOOT
        ddr_hex = "";
        if ($value$plusargs("DDR_HEX=%s", ddr_hex)) begin
            $display("tb_mips_soc: loading DDR image from %0s", ddr_hex);
            u_soc.u_impl.u_memory_subsystem.preload_ddr_hex(ddr_hex);
        end else begin
            $display("tb_mips_soc: ERROR: TB_LINUX_BOOT requires +DDR_HEX");
            $finish;
        end
`endif

        // Wait a few cycles
        #25;
        rst_n = 1;
        
        // We need to wait enough cycles for instruction fetch, cache miss, uncacheable writes
    end

`ifdef DMA_EVENT_TRACE
    // Architectural DMA event monitor.  Poll-cycle differences are omitted;
    // state transitions and programmed transfer semantics remain strict.
    always @(posedge clk) begin : dma_event_monitor
        integer di;
        reg [31:0] dstatus;
        if (rst_n === 1'b1) begin
            for (di = 0; di < 4; di = di + 1) begin
                if (u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.done_r[di] &&
                    !dma_done_seen[di] && !dma_busy_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"START\",\"ch\":%0d,\"src\":\"%08x\",\"dst\":\"%08x\",\"len\":%0d,\"sg\":%0d}\n", di, u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.src_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.dst_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.len_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.sg_mode_r[di]);
                if (u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.busy_r[di] && !dma_busy_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"START\",\"ch\":%0d,\"src\":\"%08x\",\"dst\":\"%08x\",\"len\":%0d,\"sg\":%0d}\n", di, u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.src_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.dst_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.len_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.sg_mode_r[di]);
                if (u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.done_r[di] && !dma_done_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"DONE\",\"ch\":%0d,\"err\":%0d,\"code\":%0d,\"src\":\"%08x\",\"dst\":\"%08x\",\"len\":%0d,\"sg\":%0d}\n", di, u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.err_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.err_code_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.src_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.dst_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.len_r[di], u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.sg_mode_r[di]);
                if (!u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.done_r[di] && dma_done_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"W1C\",\"ch\":%0d}\n", di);
                if (u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.ch_int[di] && !dma_irq_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"IRQ\",\"ch\":%0d,\"level\":1}\n", di);
                if (!u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.ch_int[di] && dma_irq_seen[di])
                    $fwrite(dma_event_fd, "{\"event\":\"IRQ\",\"ch\":%0d,\"level\":0}\n", di);
                dma_busy_seen[di] = u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.busy_r[di];
                dma_done_seen[di] = u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.done_r[di];
                dma_err_seen[di] = u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.err_r[di];
                dma_irq_seen[di] = u_soc.u_impl.u_peripheral_subsystem.u_apb_dma.ch_int[di];
            end
            $fflush(dma_event_fd);
        end
    end
`endif

`ifdef SOC_ENABLE_DUAL_CORE
    initial begin
        wait (rst_n === 1'b1);

`ifdef SOC_COHERENCY_FW_STRESS
        $display("COH_STRESS_CPUNUM core0=%0d core1=%0d",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.CPUNUM,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.CPUNUM);
`endif
        repeat (100) @(posedge clk);
        if (^u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc === 1'bx) begin
            $display("REGRESSION_TEST_FAILED dual-core core1 PC is unknown");
            $finish;
        end
        $display("DUAL_CORE_CORE1_ACTIVE pc=%08h", u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc);
    end

`ifndef SOC_COHERENCY_LL_SC
`ifndef SOC_COHERENCY_FW_STRESS
`ifndef SOC_L2_E2E
`ifndef TB_DUAL_CORE_MMU_SHOOTDOWN
    initial begin
        wait (rst_n === 1'b1);
        repeat (200) @(posedge clk);
        @(negedge clk);
        force u_soc.u_impl.core1_sim_exception_req = 1'b1;
        @(negedge clk);
        release u_soc.u_impl.core1_sim_exception_req;
        $display("DUAL_CORE_CORE1_EXCEPTION_INJECTED code=0A");
    end
`endif
`endif

`endif

`endif

`endif

`ifdef SOC_COHERENCY_LL_SC
    reg llsc_coherency_injected;
    reg llsc_coherency_observed;
    integer ll_valid_rise_count;

    initial begin
        force u_soc.u_impl.core1_reset_req = 1'b1;
        llsc_coherency_injected = 0;
        llsc_coherency_observed = 0;
        ll_valid_rise_count = 0;

        wait (rst_n === 1'b1);

        // The firmware creates reservations for the normal success case,
        // ordinary-store invalidation, exception-boundary invalidation, and
        // finally this peer-notification case.  Inject only after the fifth
        // rise so the notification applies to the intended reservation.
        while (ll_valid_rise_count < 5) begin
            @(posedge u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_valid);
            ll_valid_rise_count = ll_valid_rise_count + 1;
            $display("tb_mips_soc: Observed LL reservation rise #%0d at time=%0t", ll_valid_rise_count, $time);
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        $display("tb_mips_soc: Injecting peer store notification for address 0xA0002000");
        force u_soc.u_impl.core1_coh_store_valid = 1'b1;
        force u_soc.u_impl.core1_coh_store_addr = 32'ha0002000;
        llsc_coherency_injected = 1;
        $display("LLSC_COHERENCY_PEER_NOTIF_INJECTED addr=A0002000");

        @(negedge clk);
        release u_soc.u_impl.core1_coh_store_valid;
        release u_soc.u_impl.core1_coh_store_addr;

        @(posedge clk);
        #1;
        if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ll_reservation_valid === 1'b0) begin
            llsc_coherency_observed = 1;
            $display("tb_mips_soc: Observed core-0 reservation cleared by peer notification");
        end else begin
            $display("REGRESSION_TEST_FAILED core-0 reservation was not cleared by peer notification");
            $finish;
        end
    end
`endif

    initial begin
        soc_timeout_ns = 5200000;
        if (!$value$plusargs("SOC_TIMEOUT_NS=%d", soc_timeout_ns)) begin end
`ifdef SOC_COHERENCY_FW_STRESS
        #20000000;
`elsif SOC_L2_CPU_GATE
        #20000000;
`elsif TB_LINUX_BOOT
        // Linux boot is intentionally a long-running opt-in integration
        // test; the ordinary firmware watchdog remains unchanged.
        #2000000000;
`else
        #soc_timeout_ns;
`endif
`ifdef SOC_COHERENCY_FW_STRESS
        $display("COH_STRESS_TIMEOUT core0_pc=%08h core1_pc=%08h c0_req=%b/%b/%08h c1_exc=%b/%0d c1_epc=%08h c1_req=%b/%b/%08h c1_wdata=%08h c1_be=%h rd=%b/%b/%08h/%b/%b owner=%b seen0=%08h seen1=%08h start=%08h ready=%08h command=%08h ack_word=%08h ack_part=%08h done=%08h fail=%08h",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_req,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_code,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_epc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_req,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_we,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_addr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_wdata,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_be,
                 u_soc.u_impl.fx_arvalid, u_soc.u_impl.fx_arready,
                 u_soc.u_impl.fx_araddr, u_soc.u_impl.fx_rvalid,
                 u_soc.u_impl.fx_rready,
                 u_soc.u_impl.g_dual_core.u_core1.rd_owner,
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2120/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2124/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2100/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2104/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2108/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h210c/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2110/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2114/4],
                 u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2118/4]);
`endif
        $display("\n==================================================");
        $display("SoC Simulation Timeout");
`ifdef TB_L1_NONBLOCKING
        $display("L1 timeout pc=%08h mem_vaddr=%08h data_req=%b data_we=%b data_ok=%b addr_ok=%b cause=%08h epc=%08h badv=%08h status=%08h dcache_state=%0d next=%0d req_buf=%08h/%b unc=%b legacy=%b l1=%b l_aw=%b/%b l_w=%b/%b out_w=%b/%b out_b=%b/%b bridge=%0d mshr=%0d wb=%0d rob=%0d/%0d/%0d v=%b%b%b%b r=%b%b%b%b headpc=%08h inst=%08h mr=%b mw=%b",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr_ok,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_badvaddr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                 `TB_DCACHE_PATH.state, `TB_DCACHE_PATH.next_state,
                 `TB_DCACHE_PATH.req_buf_addr, `TB_DCACHE_PATH.req_buf_we,
                 `TB_DCACHE_PATH.uncacheable,
                 `TB_DCACHE_PATH.legacy_sel, `TB_DCACHE_PATH.l1_sel,
                 `TB_DCACHE_PATH.l_awvalid, `TB_DCACHE_PATH.awready,
                 `TB_DCACHE_PATH.l_wvalid, `TB_DCACHE_PATH.wready,
                 `TB_DCACHE_PATH.wvalid, `TB_DCACHE_PATH.wready,
                 `TB_DCACHE_PATH.bvalid, `TB_DCACHE_PATH.bready,
                 `TB_DCACHE_PATH.u_bridge.state,
                 `TB_DCACHE_PATH.u_l1.mshr_occupancy,
                 `TB_DCACHE_PATH.u_l1.wb_occupancy,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.head,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.tail,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.count,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.valid[3],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.valid[2],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.valid[1],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.valid[0],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.ready[3],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.ready[2],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.ready[1],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.ready[0],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.slot[
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.head][167:136],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.slot[
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.head][135:104],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.slot[
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.head][71],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.slot[
                   u_soc.u_impl.u_core_subsystem.u_core.u_cpu.g_fifo_rob.u_mips_rob.head][70]);
`endif
`ifndef SOC_L2_NONBLOCKING
        // These probes belong to the blocking L2 implementation.  Keep the
        // timeout diagnostics buildable when the opt-in NB implementation is
        // selected; its internal state is intentionally different.
        $display("L1 READ TABLE valid=%b mid=%0d/%0d/%0d/%0d rid=%0d/%0d/%0d/%0d head=%0d tail=%0d cnt=%0d/%0d/%0d/%0d L2 req=%08h beat=%0d hit=%b lookup=%b snoop=%b/%08h sr=%b/%b rv=%b/%b/%08h/%b",
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_valid[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_mid[0][0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_mid[0][1],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_mid[0][2],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_mid[0][3],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_rid[0][0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_rid[0][1],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_rid[0][2],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_rid[0][3],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_head[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_tail[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_cnt[0],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_cnt[1],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_cnt[2],
                 u_soc.u_impl.u_soc_fabric.u_xbar.rd_cnt[3],
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.req_addr,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.beat_cnt,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.hit,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.lookup_hit,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.snoop_valid,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.snoop_addr,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_rvalid,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.s_rready,
                 u_soc.u_impl.u_memory_subsystem.u_l2_cache.u_impl.state,
                 u_soc.u_impl.u_soc_fabric.s0_rvalid,
                 u_soc.u_impl.u_soc_fabric.s0_rdata,
                 u_soc.u_impl.u_soc_fabric.s0_rlast);
`endif
        $display("ICACHE state=%0d req=%b/%08h ok=%b/%b err=%b ar=%b/%b r=%b/%b/%08h/%b cpu_pc=%08h stall=%b/%b/%b id=%08h haz=%b/%b/%b ex=%b/%0d mem=%b/%0d/%b wb=%b/%0d arch=%b busy=%b rd=%0d/%0d/%0d/%0d",
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.state,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_data_ok,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.cpu_data_ok,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_cache_error,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.arvalid,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.arready,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.rvalid,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.rready,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.rdata,
                 u_soc.u_impl.u_core_subsystem.u_core.u_icache.rlast,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.stall_req_if,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.stall_req_id,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.stall_req_id_raw,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_use_hazard,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cp0_read_hazard,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_mem_read,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_waddr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_read,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_waddr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_mem_to_reg,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_arch_valid,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_busy,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_rd[0],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_rd[1],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_rd[2],
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.nb_load_rd[3]);
`ifdef TB_DUAL_CORE_MMU_SHOOTDOWN
        $display("DUAL_MMU_TIMEOUT core0_pc=%08h core1_pc=%08h c0_status=%08h c0_cause=%08h c0_epc=%08h c1_status=%08h c1_cause=%08h c1_epc=%08h c1_data=%b/%08h/%b",
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_if_stage.pc,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                 u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_status,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_cause,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.cp0_epc,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_req,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_addr,
                 u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.data_we);
`endif
        $display("==================================================");
        $finish;
    end
    
`ifdef TB_MMU_HW_WALKER_AD
    // Observe the three fixed hardware-walker leaf PTE transactions.  The
    // behavioral DDR endpoint holds WREADY after AW, so this also proves the
    // shared bridge preserves the payload across independent channel timing.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hw_ad_aw_pending <= 1'b0;
            hw_ad_aw_time <= 0;
        end else begin
            if (u_soc.u_impl.u_core_subsystem.data_awvalid &&
                u_soc.u_impl.u_core_subsystem.data_awready &&
                ((u_soc.u_impl.u_core_subsystem.data_awaddr == 32'h00002080) ||
                 (u_soc.u_impl.u_core_subsystem.data_awaddr == 32'h00002084) ||
                 (u_soc.u_impl.u_core_subsystem.data_awaddr == 32'h00002088))) begin
                hw_ad_aw_count = hw_ad_aw_count + 1;
                hw_ad_aw_pending <= 1'b1;
                hw_ad_aw_time <= $time;
            end
            if (u_soc.u_impl.u_core_subsystem.data_wvalid &&
                u_soc.u_impl.u_core_subsystem.data_wready &&
                hw_ad_aw_pending) begin
                hw_ad_w_count = hw_ad_w_count + 1;
                if ($time > hw_ad_aw_time)
                    hw_ad_delayed_w_count = hw_ad_delayed_w_count + 1;
                hw_ad_aw_pending <= 1'b0;
            end
        end
    end
`endif

`ifdef TB_MMU_HW_WALKER_AD_RESET
    // Reset only after the walker has accepted AW while W is still pending.
    // This exercises cancellation of the shared AXI write owner and requires
    // the firmware's post-reset sequence to reproduce all three writebacks.
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_core_subsystem.ptw_axi_write_busy === 1'b1);
        wait (u_soc.u_impl.u_core_subsystem.ptw_axi_write_aw_done === 1'b1 &&
              u_soc.u_impl.u_core_subsystem.ptw_axi_write_w_done === 1'b0);
        @(negedge clk);
        $display("tb_mips_soc: resetting during hardware-walker AW/W split");
        hw_ad_reset_seen = 1;
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        $display("tb_mips_soc: hardware-walker reset released");
    end
`endif

`ifdef TB_MMU_HW_WALKER_AD_WRITE_ERROR
    // The negative gate ends only after a real walker B-channel SLVERR is
    // observed and confirms that the failed PTE write did not commit.
    always @(posedge u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_bvalid) begin
        if (rst_n && u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_bresp == 2'b10)
            hw_ad_downstream_error_seen = 1;
    end

    always @(posedge clk) begin
        if (rst_n && hw_ad_downstream_error_seen && !hw_ad_write_error_seen &&
            u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_error === 1'b1) begin
            hw_ad_write_error_seen = 1;
            if (u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_addr != 32'h00002080 ||
                u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2080/4] != 32'h0000600B ||
                u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_error !== 1'b1) begin
                $display("REGRESSION_TEST_FAILED MMU A/D write error address or commit state addr=%08h pte=%08h core_err=%b ddr_bresp=%0d impl_s0=%b/%0d/%b fabric_s0=%b/%0d/%b xbar_s0=%b m1=%b/%0d/%b",
                         u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_addr,
                         u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2080/4],
                         u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_error,
                         u_soc.u_impl.u_memory_subsystem.u_axi_sram.s_bresp,
                         u_soc.u_impl.s0_bvalid,
                         u_soc.u_impl.s0_bresp,
                         u_soc.u_impl.s0_bready,
                         u_soc.u_impl.u_soc_fabric.s0_bvalid,
                         u_soc.u_impl.u_soc_fabric.s0_bresp,
                         u_soc.u_impl.u_soc_fabric.s0_bready,
                         u_soc.u_impl.u_soc_fabric.u_xbar.s_bvalid[0],
                         u_soc.u_impl.u_soc_fabric.m1_bvalid,
                         u_soc.u_impl.u_soc_fabric.m1_bresp,
                         u_soc.u_impl.u_soc_fabric.m1_bready);
                $finish;
            end
            $display("MMU_AD_AXI_WRITE_ERROR_PASS addr=%08h resp=%0d pte=%08h",
                     u_soc.u_impl.u_core_subsystem.core_ptw_mem_write_addr,
                     u_soc.u_impl.u_core_subsystem.data_bresp,
                     u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2080/4]);
            $display("REGRESSION_TEST_SUCCESS");
            $finish;
        end
    end
`endif

    // Mailbox Monitor for Regression Tests
    always @(posedge clk) begin
`ifdef TB_L1_MAINTENANCE
        if (rst_n && `TB_DCACHE_PATH.l1_maintenance_issue) begin
            l1_maintenance_count = l1_maintenance_count + 1;
            l1_maintenance_waiting_refill = 1'b1;
        end
        if (rst_n && l1_maintenance_waiting_refill &&
            `TB_DCACHE_PATH.n_mem_req_valid) begin
            l1_maintenance_refill_count = l1_maintenance_refill_count + 1;
            l1_maintenance_waiting_refill = 1'b0;
        end
`endif
`ifdef TB_FPU_ROUND_DEBUG
        if (rst_n && (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h46000124 ||
                      u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req))
            $display("FPU_ROUND_DEBUG t=%0t pc=%08h id=%08h fcsr=%08h rm=%b result_word=%08h fpr4=%08h",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fcsr,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fcsr[1:0],
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fpu_result_word,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fpr[4]);
`endif
`ifdef TB_FPU_FPE_DEBUG
        if (rst_n && (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h46020103 ||
                      u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h46220103 ||
                      u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h46263203 ||
                      u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst == 32'h462c5382 ||
                      u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req))
            $display("FPU_FPE_DEBUG t=%0t pc=%08h id=%08h cu1=%b fcsr=%08h flags=%b en=%b idfpe=%b fpr4=%08h exc=%b code=%0d epc=%08h",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_inst,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cpu_cu1,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fcsr,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fpu_exception_flags,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fpu_enabled_flags,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.id_fpu_exception,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.fpr[4],
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_code,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc);
`endif
`ifdef TB_L1_AXI_ERROR
        if (rst_n && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_req)
            $display("L1ERR_EXC t=%0t code=%0d pc=%08h dataok=%b tagged=%b respid=%h dberr=%b cacheerr=%b model_injected=%b",
                     $time,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.effective_except_code,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_data_ok,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.tagged_data_response,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_resp_id,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_bus_error,
                     u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_cache_error,
                     u_soc.u_impl.u_memory_subsystem.u_axi_sram.error_injected);
`endif
        if (legacy_mailbox_valid) begin
            $display("CPU_CP0_SUMMARY intr=%0d syscall=%0d ri=%0d adel=%0d eret=%0d",
                     cp0_interrupt_count, cp0_syscall_count, cp0_ri_count, cp0_adel_count, cp0_eret_count);
            if (legacy_mailbox_wdata == 32'hdeadbeef) begin
`ifdef TB_L1_MAINTENANCE
                if (l1_maintenance_count != 5 ||
                    l1_maintenance_refill_count < 2) begin
                    $display("REGRESSION_TEST_FAILED L1 maintenance count=%0d refill_after=%0d",
                             l1_maintenance_count, l1_maintenance_refill_count);
                    $finish;
                end
                $display("L1_MAINTENANCE_PATH_PASS issues=%0d refills=%0d",
                         l1_maintenance_count, l1_maintenance_refill_count);
`endif
`ifdef TB_MMU_HW_WALKER
                if (u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'hfff0/4] != 32'h48415750) begin
                    $display("REGRESSION_TEST_FAILED MMU hardware walker marker mismatch: %08h",
                             u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'hfff0/4]);
                    $finish;
                end
`endif
`ifdef TB_MMU_HW_WALKER_AD
`ifdef TB_MMU_HW_WALKER_AD_RESET
                if (hw_ad_reset_seen != 1 || hw_ad_aw_count < 3 || hw_ad_w_count < 3 ||
`else
                if (hw_ad_aw_count != 3 || hw_ad_w_count != 3 ||
`endif
                    hw_ad_delayed_w_count == 0 ||
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2080/4] != 32'h0000603B ||
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2084/4] != 32'h0000703B ||
                    u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2088/4] != 32'h0000801D) begin
                    $display("REGRESSION_TEST_FAILED MMU A/D writeback aw=%0d w=%0d delayed_w=%0d ptes=%08h/%08h/%08h",
                             hw_ad_aw_count, hw_ad_w_count, hw_ad_delayed_w_count,
                             u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2080/4],
                             u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2084/4],
                             u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'h2088/4]);
                    $finish;
                end
                $display("MMU_AD_AXI_WRITEBACK_PASS aw=%0d w=%0d delayed_w=%0d",
                         hw_ad_aw_count, hw_ad_w_count, hw_ad_delayed_w_count);
`endif
`ifdef TB_MMU_REFILL
`ifndef TB_MMU_HW_WALKER
                if (u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'hfff4/4] != 32'h4D4D5550) begin
                    $display("REGRESSION_TEST_FAILED MMU refill marker mismatch: %08h",
                             u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[32'hfff4/4]);
                    $finish;
                end
                $display("MMU_REFILL_MARKER_PASS");
`endif
`endif
`ifdef TB_L1_AXI_ERROR
                if (cp0_cacheerr_count == 0) begin
                    $display("REGRESSION_TEST_FAILED L1 AXI response error did not retire CacheErr");
                    $finish;
                end
`endif
`ifdef TB_L1_AXI_ERROR_TWO
                if (cp0_cacheerr_count < 1) begin
                    $display("REGRESSION_TEST_FAILED L1 AXI simultaneous-response precise error count=%0d", cp0_cacheerr_count);
                    $finish;
                end
                $display("L1_AXI_TWO_PRECISE_REPLAY_PASS errors=%0d", cp0_cacheerr_count);
`endif
`ifdef SOC_L2_E2E
                if (l2_e2e_ar_target < 1) begin
                    $display("L2_E2E_COUNTER_MISMATCH target_ar=%0d total_ar=%0d",
                             l2_e2e_ar_target, l2_e2e_ar_total);
                    $finish;
                end
`ifdef SOC_L2_WRITEBACK
                $display("L2_E2E_WB_L1_EVICTION target_aw=%0d w=%0d b=%0d",
                         l2_e2e_aw_target, l2_e2e_w_total, l2_e2e_b_total);
`endif
                $display("L2_E2E_TEST_SUCCESS policy=%s target_ar=%0d target_aw=%0d w=%0d b=%0d",
`ifdef SOC_L2_NONBLOCKING
                         "nonblocking-write-back",
`else
`ifdef SOC_L2_WRITEBACK
                         "write-back",
`else
                         "write-through",
`endif
`endif
                         l2_e2e_ar_target, l2_e2e_aw_target,
                         l2_e2e_w_total, l2_e2e_b_total);
`endif
`ifdef SOC_COHERENCY_LL_SC
                if (!llsc_coherency_injected || !llsc_coherency_observed) begin
                    $display("REGRESSION_TEST_FAILED LL/SC peer coherency notification not injected/observed");
                    $finish;
                end
`else
`ifdef SOC_ENABLE_DUAL_CORE
`ifndef TB_DUAL_CORE_MMU_SHOOTDOWN
`ifndef SOC_COHERENCY_FW_STRESS
                if (dual_core_ipi_count == 0) begin
                    $display("REGRESSION_TEST_FAILED dual-core IPI invalidate not observed");
                    $finish;
                end
                if (dual_core_reverse_ipi_count == 0) begin
                    $display("REGRESSION_TEST_FAILED target-0 IPI invalidate not observed");
                    $finish;
                end
                if (dual_core_reset_count == 0) begin
                    $display("REGRESSION_TEST_FAILED core1 reset isolation not observed");
                    $finish;
                end
                if (dual_core_exception_count == 0) begin
                    $display("REGRESSION_TEST_FAILED core1 exception isolation not observed");
                    $finish;
                end
`endif
`endif
`endif
`endif
`ifdef SOC_UART_CTS_FLOW_CONTROL
                if (uart_tx_low_before_cts_release) begin
                    $display("REGRESSION_TEST_FAILED UART TX asserted before CTS release");
                    $finish;
                end
                if (!uart_cts_release_seen) begin
                    $display("REGRESSION_TEST_FAILED UART CTS release checkpoint not reached");
                    $finish;
                end
`endif
`ifndef SOC_ENABLE_DUAL_CORE
`ifndef SOC_L2_E2E
`ifndef TB_SKIP_UART_PIN_CHECK
                if (!uart_tx_seen_low) begin
                    $display("REGRESSION_TEST_FAILED UART TX pin never asserted");
                    $finish;
                end
`endif
`endif
`endif
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (legacy_mailbox_wdata == 32'hdeaddead ||
                         legacy_mailbox_wdata[31:16] == 16'hdeaf) begin
                $display("REGRESSION_TEST_FAILED code=%08h", legacy_mailbox_wdata);
                $finish;
            end
        end

`ifdef SOC_ENABLE_DUAL_CORE
        if (u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_req &&
            u_soc.u_impl.g_dual_core.u_core1.u_core1.u_cpu.u_mips_cp0.except_code == 5'h0A)
            dual_core_exception_count = dual_core_exception_count + 1;
        if (u_soc.u_impl.core1_reset_req)
            dual_core_reset_count = dual_core_reset_count + 1;
        if (u_soc.u_impl.g_dual_core.u_core1.tlb_inv_en &&
            u_soc.u_impl.g_dual_core.u_core1.tlb_inv_vpn2 == 19'h12345) begin
            dual_core_ipi_count = dual_core_ipi_count + 1;
        end
        if (u_soc.u_impl.u_core_subsystem.tlb_inv_en &&
            u_soc.u_impl.u_core_subsystem.tlb_inv_vpn2 == 19'h12346) begin
            dual_core_reverse_ipi_count = dual_core_reverse_ipi_count + 1;
        end
`endif
        
        // Debug PC Trace
        if ($time % 5000000 == 0) begin
            $display("Time=%0t PC=%h", $time, legacy_trace_pc);
        end
    end

`ifdef SOC_UART_EXTERNAL_RX_WAVEFORM
    // Wait until firmware enables RX with loopback disabled, then inject one
    // asynchronous 8N1 frame at the DUT's divisor=1 (16 clocks/bit) rate.
    task automatic external_uart_bit(input bit value);
    begin
        uart_rx = value;
        repeat (16) @(posedge clk);
    end
    endtask

    task automatic external_uart_frame(input [7:0] value);
        integer b;
    begin
        external_uart_bit(1'b0);
        for (b = 0; b < 8; b = b + 1)
            external_uart_bit(value[b]);
        external_uart_bit(1'b1);
        external_uart_bit(1'b1);
    end
    endtask

    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.ier_r[0] === 1'b1 &&
              u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.mcr_r[4] === 1'b0);
        repeat (32) @(posedge clk);
        $display("tb_mips_soc: injecting external UART RX frame 0x5A");
        external_uart_frame(8'h5A);
    end
`endif

`ifdef SOC_UART_CTS_FLOW_CONTROL
    initial begin
        wait (rst_n === 1'b1);
        wait (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.mcr_r[5] === 1'b1 &&
              u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.tx_empty === 1'b0);
        repeat (512) @(posedge clk);
        if (uart_tx !== 1'b1) begin
            $display("REGRESSION_TEST_FAILED UART TX started while CTS inactive");
            $finish;
        end
        $display("tb_mips_soc: UART CTS inactive held TX idle");
        uart_cts_release_seen = 1'b1;
        uart_cts_n = 1'b0;
        wait (uart_tx === 1'b0);
        $display("tb_mips_soc: UART CTS release allowed TX frame");
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cp0_interrupt_count <= 0;
            cp0_syscall_count <= 0;
            cp0_ri_count <= 0;
            cp0_adel_count <= 0;
            cp0_eret_count <= 0;
        end else begin
            if (legacy_cp0_except_req && !legacy_cp0_exl) begin
                if (legacy_cp0_intr_req) begin
                    cp0_interrupt_count <= cp0_interrupt_count + 1;
                end else begin
                    case (legacy_cp0_except_code)
                        5'h08: cp0_syscall_count <= cp0_syscall_count + 1;
                        5'h0a: cp0_ri_count <= cp0_ri_count + 1;
                        5'h04: cp0_adel_count <= cp0_adel_count + 1;
                        5'h1e: cp0_cacheerr_count <= cp0_cacheerr_count + 1;
                    endcase
                end
            end

            if (legacy_cp0_eret) begin
                cp0_eret_count <= cp0_eret_count + 1;
            end
        end
    end
    
    always @(posedge clk) begin
`ifdef SOC_UART_CTS_FLOW_CONTROL
        if (rst_n && !uart_cts_release_seen && !uart_tx)
            uart_tx_low_before_cts_release <= 1'b1;
`endif
        if (rst_n && !uart_tx)
            uart_tx_seen_low <= 1'b1;
        if (legacy_uart_tx_valid) begin
            $write("%c", legacy_uart_tx_data);
            $fflush();
        end
`ifndef TB_LINUX_BOOT
        if (rst_n && legacy_core_global_stall && $time > 20900000) begin
            $display("Time=%0t DCACHE: state=%0d next_state=%0d req_buf_addr=%x req_buf_we=%b uc_req=%b awv=%b wv=%b bready=%b", 
                $time, legacy_dcache_state, legacy_dcache_next_state, legacy_dcache_req_buf_addr, legacy_dcache_req_buf_we, legacy_dcache_uncacheable, legacy_dcache_awvalid, legacy_dcache_wvalid, legacy_dcache_bready);
        end
`endif
    end

    



    task jtag_reset;
        begin
            tms_r = 1;
            repeat(5) begin
                #10 tck_r = 1; #10 tck_r = 0;
            end
        end
    endtask

    task jtag_shift_ir;
        input [3:0] ir_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_IR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<4; i=i+1) begin
                tdi_r = ir_val[i];
                tms_r = (i==3) ? 1 : 0; // EXIT1_IR on last bit
                #10 tck_r = 1; #10 tck_r = 0;
            end
            
            // Go to PAUSE_IR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Go to EXIT2_IR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            
            // UPDATE_IR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

    task jtag_shift_dr;
        input [31:0] dr_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<32; i=i+1) begin
                tdi_r = dr_val[i];
                tms_r = (i==31) ? 1 : 0; // EXIT1_DR on last bit
                #10 tck_r = 1; 
                #10 tck_r = 0;
            end
            
            // Go to PAUSE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Stay in PAUSE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // Go to EXIT2_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            
            // UPDATE_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

    task jtag_shift_dr_65;
        input [64:0] dr_val;
        integer i;
        begin
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SELECT_DR_SCAN
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // CAPTURE_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            // SHIFT_DR
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
            for (i=0; i<65; i=i+1) begin
                tdi_r = dr_val[i];
                tms_r = (i==64) ? 1 : 0; // EXIT1_DR on last bit
                #10 tck_r = 1; 
                #10 tck_r = 0;
            end
            // UPDATE_DR
            tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
            // RUN_TEST_IDLE
            tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        end
    endtask

`ifndef SOC_COHERENCY_FW_STRESS
`ifndef SOC_L2_E2E
`ifndef SOC_L2_CPU_GATE
`ifndef TB_LINUX_BOOT
    initial begin
        // Let system reset finish
        #1500;
        jtag_reset();
        jtag_shift_ir(4'h1); // IDCODE
        jtag_shift_dr(32'h00000000); // shift out IDCODE (dummy shift)
        
        // JTAG AXI Write to GPIO direction register (0x4000_2004)
        jtag_shift_ir(4'h8); // IR_AXI_CMD
        // CMD: Write (1) | Addr (0x4000_2004) | Data (0xFFFF_FFFF)
        jtag_shift_dr_65({1'b1, 32'h40002004, 32'hFFFFFFFF});
        #100; // wait for AXI transaction

        // JTAG AXI Write to GPIO data register (0x4000_2000)
        // CMD: Write (1) | Addr (0x4000_2000) | Data (0xDEADBEEF)
        jtag_shift_dr_65({1'b1, 32'h40002000, 32'hDEADBEEF});
        #100; // wait for AXI transaction
        
        // JTAG AXI Read from GPIO data register (0x4000_2000)
        // CMD: Read (0) | Addr (0x4000_2000) | Data (0x0)
        jtag_shift_dr_65({1'b0, 32'h40002000, 32'h00000000});
        #100; // wait for AXI transaction
        // Read out the result (shift again to capture)
        jtag_shift_dr_65({1'b0, 32'h40002000, 32'h00000000});
        
        // JTAG Toggle Coverage Boost
        $display("Testing JTAG Toggle Coverage...");
        jtag_shift_ir(4'hA); // dummy IR pattern
        jtag_shift_ir(4'h5); // dummy IR pattern
        jtag_shift_dr_65({1'b1, 32'hAAAAAAAA, 32'h55555555});
        jtag_shift_dr_65({1'b0, 32'h55555555, 32'hAAAAAAAA});
        jtag_shift_dr_65({1'b1, 32'hFFFFFFFF, 32'hFFFFFFFF});
        jtag_shift_dr_65({1'b0, 32'h00000000, 32'h00000000});
        
        
        // --- JTAG FSM Coverage Sequence ---
        $display("Running JTAG FSM Coverage Sequence...");
        // Currently in RUN_TEST_IDLE.
        // Go to SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_IR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR (length 0 shift)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_IR (Cover EXIT1_IR -> UPDATE_IR)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_DR_SCAN (Cover UPDATE_IR -> SELECT_DR_SCAN)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_DR (length 0 shift)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to PAUSE_DR (Cover EXIT1_DR -> PAUSE_DR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT2_DR 
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SHIFT_DR (Cover EXIT2_DR -> SHIFT_DR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_DR 
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SELECT_DR_SCAN (Cover UPDATE_DR -> SELECT_DR_SCAN)
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Go to SELECT_IR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to PAUSE_IR (Cover EXIT1_IR -> PAUSE_IR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT2_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to SHIFT_IR (Cover EXIT2_IR -> SHIFT_IR)
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // Go to EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // Go to UPDATE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Back to RUN_TEST_IDLE
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        
        $display("JTAG Test Completed");
        
`ifndef SOC_COHERENCY_FW_STRESS
`ifndef TB_SKIP_JTAG_RESET_STRESS
        // The normal regression waits until after the firmware completes. The
        // opt-in L1 stress mode moves this sequence into the active workload
        // so an outstanding cache transaction is actually reset in flight.
`ifdef TB_L1_NONBLOCKING_RESET_STRESS
        #500000;
`else
        #3000000;
`endif
        
        $display("Testing Async Reset in middle of operations to boost FSM transition coverage...");
        // Start a JTAG shift
        // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        // SHIFT_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        tdi_r = 1; #10 tck_r = 1; #5;
        
        // Assert System Reset while in SHIFT_DR!
        rst_n = 0;
        #5 tck_r = 0;
        #20 rst_n = 1; // Release reset
        
        // Let system reset finish
        #100;
        
        $display("Testing JTAG synchronous reset (5 TCKs with TMS=1)...");
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // Should now be in TEST_LOGIC_RESET
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // Stay in TEST_LOGIC_RESET
        
        $display("Testing JTAG asynchronous resets...");
        // From RUN_TEST_IDLE
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0;
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SHIFT_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From PAUSE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT2_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT2_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From UPDATE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_DR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // UPDATE_DR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // Now do IR states
        // From SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From SHIFT_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From PAUSE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From EXIT2_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // PAUSE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT2_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        // From UPDATE_IR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_IR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // EXIT1_IR
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // UPDATE_IR
        rst_n = 0; #10; rst_n = 1; #10;
        
        $display("Testing AXI mid-flight reset via JTAG...");
        // Start JTAG AXI transaction
        jtag_shift_ir(4'h8); // IR_AXI_CMD
        // Start shifting DR, but don't finish
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // RUN_TEST_IDLE
        tms_r = 1; #10 tck_r = 1; #10 tck_r = 0; // SELECT_DR_SCAN
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // CAPTURE_DR
        tms_r = 0; #10 tck_r = 1; #10 tck_r = 0; // SHIFT_DR
        
        // Shift a few bits
        tdi_r = 1; #10 tck_r = 1; #10 tck_r = 0;
        
        // Assert system reset
        rst_n = 0;
        #50 rst_n = 1;
`endif
`endif
        
    end
`endif
`endif
`endif
`endif

`ifdef SOC_L2_E2E
    initial begin
        l2_e2e_ar_total = 0;
        l2_e2e_aw_total = 0;
        l2_e2e_w_total = 0;
        l2_e2e_b_total = 0;
        l2_e2e_ar_target = 0;
        l2_e2e_aw_target = 0;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (u_soc.u_impl.u_memory_subsystem.l2m_arvalid &&
                u_soc.u_impl.u_memory_subsystem.l2m_arready) begin
                l2_e2e_ar_total = l2_e2e_ar_total + 1;
                if (l2_e2e_ar_total < 40)
                    $display("L2_E2E_AR addr=%08h len=%0d",
                             u_soc.u_impl.u_memory_subsystem.l2m_araddr,
                             u_soc.u_impl.u_memory_subsystem.l2m_arlen);
                if ((u_soc.u_impl.u_memory_subsystem.l2m_araddr & 32'hffffffe0) ==
                    L2_E2E_TARGET_LINE)
                    l2_e2e_ar_target = l2_e2e_ar_target + 1;
            end
            if (u_soc.u_impl.u_memory_subsystem.l2m_awvalid &&
                u_soc.u_impl.u_memory_subsystem.l2m_awready) begin
                l2_e2e_aw_total = l2_e2e_aw_total + 1;
                if ((u_soc.u_impl.u_memory_subsystem.l2m_awaddr & 32'hffffffe0) ==
                    L2_E2E_TARGET_LINE)
                    l2_e2e_aw_target = l2_e2e_aw_target + 1;
            end
            if (u_soc.u_impl.u_memory_subsystem.l2m_wvalid &&
                u_soc.u_impl.u_memory_subsystem.l2m_wready)
                l2_e2e_w_total = l2_e2e_w_total + 1;
            if (u_soc.u_impl.u_memory_subsystem.l2m_bvalid &&
                u_soc.u_impl.u_memory_subsystem.l2m_bready)
                l2_e2e_b_total = l2_e2e_b_total + 1;

        end
    end
`endif

endmodule

bind tb_mips_soc soc_legacy_observation_bind u_soc_legacy_observation_bind (
    .obs_if              (legacy_obs_if),
    // Phase B.3.c + Phase C.1 note: watch the pre-MMU virtual address
    // (mem_vaddr) rather than the post-translation PA (data_addr). Firmware
    // always writes the mailbox as VA 0xA000FFFC (kseg1 alias); the MMU may
    // later translate this to PA 0x0000FFFC once SOC_MMU_ENABLE=1 flips,
    // which would silently break the observation if we watched data_addr.
    .mailbox_valid       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                          u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'ha000fffc)),
    .mailbox_wdata       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata),
    .trace_pc            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc),
    .cp0_except_req      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req),
    .cp0_except_code     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code),
    .cp0_intr_req        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req),
    .cp0_exl             (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1]),
    .cp0_eret            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .uart_tx_valid       (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.psel &&
                          u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.penable &&
                          u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwrite &&
                          (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.paddr[4:0] == 5'h00)),
    .uart_tx_data        (u_soc.u_impl.u_peripheral_subsystem.u_apb_uart.pwdata[7:0]),
    .core_global_stall   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.global_stall),
    .dcache_state        (`TB_DCACHE_PATH.state),
    .dcache_next_state   (`TB_DCACHE_PATH.next_state),
    .dcache_req_buf_addr (`TB_DCACHE_PATH.req_buf_addr),
    .dcache_req_buf_we   (`TB_DCACHE_PATH.req_buf_we),
    .dcache_uncacheable  (`TB_DCACHE_PATH.uncacheable),
    .dcache_awvalid      (`TB_DCACHE_PATH.awvalid),
    .dcache_wvalid       (`TB_DCACHE_PATH.wvalid),
    .dcache_bready       (`TB_DCACHE_PATH.bready)
);

`ifdef TB_RETIRE_TRACE
// Keep the standalone SoC top on the same architectural retire schema used by
// the UVM wrapper. This bind is intentionally verification-only and does not
// alter the RTL datapath or the production top.
bind tb_mips_soc soc_observation_bind u_soc_retire_observation_bind (
    .obs_if               (retire_obs_if),
    .retire_schema        (32'h00010000),
    .retire_valid         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_valid),
    .retire_pc            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_pc),
    .retire_instr         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst),
    .retire_next_pc       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_next_pc),
    .retire_gpr_we        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_reg_write &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr != 5'd0)),
    .retire_gpr_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_waddr),
    .retire_gpr_data      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_wdata),
    .retire_cp0_we        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_we),
    .retire_cp0_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr),
    .retire_cp0_sel       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_sel),
    .retire_cp0_data      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_fpr_state     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_save_fpr),
    .retire_fcsr_state    (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ctx_save_fcsr),
    .retire_mem_valid     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace ||
                           u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_read      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace),
    .retire_mem_write     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_mem_wdata     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_val_rt),
    .retire_mem_be        (4'b1111),
    .retire_mem_rdata     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rdata_selected),
    .retire_except        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_req),
    .retire_except_code   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_except_code),
    .retire_bd            (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_bd),
    .retire_eret          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .mailbox_valid        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                           u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'ha000fffc)),
    .mailbox_wdata        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata),
    .ex_reg_write         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_reg_write),
    .ex_pc                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.ex_pc_plus_8 - 32'd8),
    .jtag_axi_state       (u_soc.u_impl.u_debug_subsystem.u_jtag_debug_top.axi_state),
    .cpu_cp0_except_req   (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req),
    .cpu_cp0_except_code  (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code),
    .cpu_cp0_intr_req     (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req),
    .cpu_cp0_eret         (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .cpu_cp0_exl          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1]),
    .cpu_cp0_epc          (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc)
);
`endif
