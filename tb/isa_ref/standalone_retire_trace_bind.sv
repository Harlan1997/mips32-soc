// Verification-only retire observation for standalone boot-ROM testbenches.
// The including testbench must provide RETIRE_BIND_TARGET, u_soc and
// retire_obs_if with the same hierarchy used by tb_mips_soc.
`ifndef STANDALONE_RETIRE_TRACE_BIND_SV
`define STANDALONE_RETIRE_TRACE_BIND_SV

bind `RETIRE_BIND_TARGET soc_observation_bind u_soc_retire_observation_bind (
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
    .retire_cp0_we        (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_we &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'h10) &&
                           (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_inst[25:21] == 5'h04)),
    .retire_cp0_addr      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_rd_addr),
    .retire_cp0_sel       (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_cp0_sel),
    .retire_cp0_data      (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.wb_ex_out),
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
