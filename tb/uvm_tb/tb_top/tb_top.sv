`timescale 1ns/1ps
`include "soc_config.vh"
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_if.sv"
`include "../agents/axi_master_if.sv"
`include "../checkers/axi_protocol_checker.sv"
`include "soc_observation_if.sv"
`include "soc_observation_bind.sv"
`include "../../isa_ref/retire_trace_capture.sv"
`include "../tests/soc_base_test.sv"
`include "../tests/soc_bus_stress_test.sv"
`include "../tests/soc_unmapped_error_test.sv"
`include "../tests/soc_flash_write_error_test.sv"
`include "../tests/soc_fabric_contract_test.sv"
`include "../tests/soc_gpio_reg_model_test.sv"
`include "../tests/soc_apb_reg_model_test.sv"
`include "../tests/soc_apb_burst_stress_test.sv"
`include "../tests/soc_apb_fault_stress_test.sv"
`include "../tests/soc_uart_irq_test.sv"
`include "../tests/soc_flash_image_test.sv"
`include "../tests/soc_dma_copy_test.sv"
`include "../tests/soc_dma_irq_test.sv"
`include "../tests/soc_timer_irq_test.sv"
`include "../tests/soc_pic_combined_irq_test.sv"
`include "../tests/soc_sram_data_integrity_test.sv"
`include "../tests/soc_axi_id_sweep_test.sv"
`include "../tests/soc_axi_attribute_cross_sweep_test.sv"
`include "../tests/soc_apb_bit_pattern_sweep_test.sv"
`include "../tests/soc_axi_overlap_probe_test.sv"
`include "../tests/soc_jtag_reset_recovery_test.sv"
`include "../tests/soc_cpu_cp0_exception_test.sv"
`include "../tests/soc_pic_mask_arbitration_test.sv"

`define BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER(INST, NAME, PREFIX) \
    bind soc_fabric axi_protocol_checker #( \
        .CHECKER_NAME(NAME), \
        .REQUIRE_SINGLE_OUTSTANDING(1'b1), \
        .REQUIRE_W_AFTER_AW(1'b1) \
    ) INST ( \
        .clk     (clk), \
        .rst_n   (rst_n), \
        .awid    (PREFIX``_awid), \
        .awaddr  (PREFIX``_awaddr), \
        .awlen   (PREFIX``_awlen), \
        .awsize  (PREFIX``_awsize), \
        .awburst (PREFIX``_awburst), \
        .awlock  (PREFIX``_awlock), \
        .awcache (PREFIX``_awcache), \
        .awprot  (PREFIX``_awprot), \
        .awvalid (PREFIX``_awvalid), \
        .awready (PREFIX``_awready), \
        .wdata   (PREFIX``_wdata), \
        .wstrb   (PREFIX``_wstrb), \
        .wlast   (PREFIX``_wlast), \
        .wvalid  (PREFIX``_wvalid), \
        .wready  (PREFIX``_wready), \
        .bid     (PREFIX``_bid), \
        .bresp   (PREFIX``_bresp), \
        .bvalid  (PREFIX``_bvalid), \
        .bready  (PREFIX``_bready), \
        .arid    (PREFIX``_arid), \
        .araddr  (PREFIX``_araddr), \
        .arlen   (PREFIX``_arlen), \
        .arsize  (PREFIX``_arsize), \
        .arburst (PREFIX``_arburst), \
        .arlock  (PREFIX``_arlock), \
        .arcache (PREFIX``_arcache), \
        .arprot  (PREFIX``_arprot), \
        .arvalid (PREFIX``_arvalid), \
        .arready (PREFIX``_arready), \
        .rid     (PREFIX``_rid), \
        .rdata   (PREFIX``_rdata), \
        .rresp   (PREFIX``_rresp), \
        .rlast   (PREFIX``_rlast), \
        .rvalid  (PREFIX``_rvalid), \
        .rready  (PREFIX``_rready) \
    );

// Phase C.3: the fabric is now a true crossbar (soc_fabric.v), so the legacy
// shared-trunk nets axim/axim2/axim3/axim4 no longer exist. The meaningful
// single-outstanding monitoring points are the crossbar's three slave-facing
// ports (s0=SRAM/L2, s1=APB, s2=FLASH), which remain single-outstanding to match
// the downstream slaves. Bind one protocol checker per slave port. These use
// the flat slave-side signals (s0_/s1_/s2_) present on soc_fabric's boundary.
`BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER(u_s0_protocol_checker, "fabric_s0", s0)
`BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER(u_s1_protocol_checker, "fabric_s1", s1)
`BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER(u_s2_protocol_checker, "fabric_s2", s2)
`BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER(u_jtag_protocol_checker, "jtag_master", jtag)

`undef BIND_SOC_FABRIC_AXI_PROTOCOL_CHECKER

bind soc_verif_top soc_observation_bind u_soc_observation_bind (
    .obs_if               (obs_if),
    .retire_schema        (`SOC_RETIRE_TRACE_SCHEMA),
    .retire_valid         ((`SOC_RETIRE_TRACE_ENABLE != 0) &&
                           u_dut.u_core_subsystem.u_core.u_cpu.wb_valid),
    .retire_pc            (u_dut.u_core_subsystem.u_core.u_cpu.wb_pc),
    .retire_instr         (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst),
    .retire_next_pc       (u_dut.u_core_subsystem.u_core.u_cpu.wb_next_pc),
    .retire_gpr_we        ((u_dut.u_core_subsystem.u_core.u_cpu.wb_reg_write ||
                           ((`SOC_FPU_ENABLE != 0) &&
                            (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b010001) &&
                            ((u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[25:21] == 5'b00000) ||
                             (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[25:21] == 5'b00010)))) &&
                           (u_dut.u_core_subsystem.u_core.u_cpu.wb_waddr != 5'd0)),
    .retire_gpr_addr      (u_dut.u_core_subsystem.u_core.u_cpu.wb_waddr),
    .retire_gpr_data      (u_dut.u_core_subsystem.u_core.u_cpu.wb_wdata),
    .retire_cp0_we        (u_dut.u_core_subsystem.u_core.u_cpu.wb_cp0_we),
    .retire_cp0_addr      (u_dut.u_core_subsystem.u_core.u_cpu.wb_rd_addr),
    .retire_cp0_sel       (u_dut.u_core_subsystem.u_core.u_cpu.wb_cp0_sel),
    .retire_cp0_data      (u_dut.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_mem_valid     (u_dut.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace ||
                           u_dut.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_read      (u_dut.u_core_subsystem.u_core.u_cpu.wb_mem_read_trace),
    .retire_mem_write     (u_dut.u_core_subsystem.u_core.u_cpu.wb_mem_write_trace),
    .retire_mem_addr      (u_dut.u_core_subsystem.u_core.u_cpu.wb_ex_out),
    .retire_mem_wdata     (u_dut.u_core_subsystem.u_core.u_cpu.wb_val_rt),
    // Derive the observed byte lanes from the retired opcode.  This keeps
    // the trace contract tied to the architectural access size even when a
    // future internal mem_op encoding is added or reused.
    .retire_mem_be        (((u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b100000) ||
                            (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b100100) ||
                            (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b101000)) ?
                           (4'b0001 << u_dut.u_core_subsystem.u_core.u_cpu.wb_ex_out[1:0]) :
                           (((u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b100001) ||
                             (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b100101) ||
                             (u_dut.u_core_subsystem.u_core.u_cpu.wb_inst[31:26] == 6'b101001)) ?
                            (u_dut.u_core_subsystem.u_core.u_cpu.wb_ex_out[1] ? 4'b1100 : 4'b0011) :
                            4'b1111)),
    .retire_mem_rdata     (u_dut.u_core_subsystem.u_core.u_cpu.wb_rdata_selected),
    .retire_except        (u_dut.u_core_subsystem.u_core.u_cpu.wb_except_req),
    .retire_except_code   (u_dut.u_core_subsystem.u_core.u_cpu.wb_except_code),
    .retire_bd            (u_dut.u_core_subsystem.u_core.u_cpu.wb_bd),
    .retire_eret          (u_dut.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    // Phase B.3.c + Phase C.1: watch VA (mem_vaddr) rather than post-MMU PA
    // (data_addr). See tb/soc_test/tb_mips_soc.v for rationale.
    .mailbox_valid        (u_dut.u_core_subsystem.u_core.u_cpu.data_req &&
                           u_dut.u_core_subsystem.u_core.u_cpu.data_we &&
                           (u_dut.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'ha000_fffc)),
    .mailbox_wdata        (u_dut.u_core_subsystem.u_core.u_cpu.data_wdata),
    .ex_reg_write         (u_dut.u_core_subsystem.u_core.u_cpu.ex_reg_write),
    .ex_pc                (u_dut.u_core_subsystem.u_core.u_cpu.ex_pc_plus_8 - 32'd8),
    .jtag_axi_state       (u_dut.u_debug_subsystem.u_jtag_debug_top.axi_state),
    .cpu_cp0_except_req   (u_dut.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_req),
    .cpu_cp0_except_code  (u_dut.u_core_subsystem.u_core.u_cpu.u_mips_cp0.except_code),
    .cpu_cp0_intr_req     (u_dut.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intr_req),
    .cpu_cp0_eret         (u_dut.u_core_subsystem.u_core.u_cpu.wb_is_eret),
    .cpu_cp0_exl          (u_dut.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1]),
    .cpu_cp0_epc          (u_dut.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_epc)
);

module tb_top;
    logic clk;
    logic rst_n;
    
    // External GPIO and JTAG (stubbed for now)
    wire [31:0] gpio_pins;
    logic tck, tms, tdi, tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire spi_miso = 1'b0;

    // Instantiate UVM AXI Interfaces
    axi_if        axi_vif(clk, rst_n);        // Passive monitor for SoC SRAM AXI port
    axi_master_if axi_master_vif(clk, rst_n); // Active verification master
    soc_observation_if soc_obs_if(clk, rst_n);
    retire_trace_capture u_retire_trace_capture (
        .clk(clk), .rst_n(rst_n), .obs_if(soc_obs_if)
    );

    // Optional timing probe for system-mode retire differential failures.
    // Keep this behind a plusarg so normal UVM logs and performance are
    // unchanged.  The probe spans the CPU uncached request, APB bridge, and
    // VIC state in one clock-domain view.
    initial begin
        if ($test$plusargs("VIC_DEBUG")) begin
            forever begin
                @(posedge clk);
                if (u_soc.u_dut.u_core_subsystem.u_core.u_cpu.data_req ||
                    u_soc.u_dut.u_peripheral_subsystem.u_axi2apb.psel ||
                    u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.rd ||
                    u_soc.u_dut.u_core_subsystem.u_core.u_cpu.wb_valid) begin
                    $display("VIC_DEBUG t=%0t pc=%08x dreq=%b daddr=%08x dok=%b drdata=%08x arv=%b arvdy=%b araddr=%08x rvalid=%b rready=%b rdata=%08x apb_psel=%b pen=%b paddr=%08x prdata=%08x vic_rd=%b irq=%b vec=%0d best=%0d active=%08x soft=%08x mask=%08x gprwe=%b wa=%0d wdata=%08x",
                        $time,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.wb_pc,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.data_req,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.data_addr,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.data_data_ok,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.data_rdata,
                        u_soc.u_dut.m1_arvalid, u_soc.u_dut.m1_arready, u_soc.u_dut.m1_araddr,
                        u_soc.u_dut.m1_rvalid, u_soc.u_dut.m1_rready, u_soc.u_dut.m1_rdata,
                        u_soc.u_dut.u_peripheral_subsystem.u_axi2apb.psel,
                        u_soc.u_dut.u_peripheral_subsystem.u_axi2apb.penable,
                        u_soc.u_dut.u_peripheral_subsystem.u_axi2apb.paddr,
                        u_soc.u_dut.u_peripheral_subsystem.u_axi2apb.prdata,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.rd,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.irq,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.vec_id,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.best_id_r,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.active_r,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.soft_r,
                        u_soc.u_dut.u_peripheral_subsystem.u_apb_pic.enable_r,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.wb_reg_write,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.wb_waddr,
                        u_soc.u_dut.u_core_subsystem.u_core.u_cpu.wb_wdata);
                end
            end
        end
    end

    wire [3:0]  mon_s0_awid;
    wire [31:0] mon_s0_awaddr;
    wire [7:0]  mon_s0_awlen;
    wire [2:0]  mon_s0_awsize;
    wire [1:0]  mon_s0_awburst;
    wire [1:0]  mon_s0_awlock;
    wire [3:0]  mon_s0_awcache;
    wire [2:0]  mon_s0_awprot;
    wire        mon_s0_awvalid;
    wire        mon_s0_awready;
    wire [31:0] mon_s0_wdata;
    wire [3:0]  mon_s0_wstrb;
    wire        mon_s0_wlast;
    wire        mon_s0_wvalid;
    wire        mon_s0_wready;
    wire [3:0]  mon_s0_bid;
    wire [1:0]  mon_s0_bresp;
    wire        mon_s0_bvalid;
    wire        mon_s0_bready;
    wire [3:0]  mon_s0_arid;
    wire [31:0] mon_s0_araddr;
    wire [7:0]  mon_s0_arlen;
    wire [2:0]  mon_s0_arsize;
    wire [1:0]  mon_s0_arburst;
    wire [1:0]  mon_s0_arlock;
    wire [3:0]  mon_s0_arcache;
    wire [2:0]  mon_s0_arprot;
    wire        mon_s0_arvalid;
    wire        mon_s0_arready;
    wire [3:0]  mon_s0_rid;
    wire [31:0] mon_s0_rdata;
    wire [1:0]  mon_s0_rresp;
    wire        mon_s0_rlast;
    wire        mon_s0_rvalid;
    wire        mon_s0_rready;
    wire        mailbox_valid;
    wire [31:0] mailbox_wdata;
    wire        ex_reg_write;
    wire [31:0] ex_pc;
    wire [2:0]  jtag_axi_state;
    wire        cpu_cp0_except_req;
    wire [4:0]  cpu_cp0_except_code;
    wire        cpu_cp0_intr_req;
    wire        cpu_cp0_eret;
    wire        cpu_cp0_exl;
    wire [31:0] cpu_cp0_epc;
    logic       initial_reset_released;
    logic       jtag_axi_cmd_sequence_done;
    logic       jtag_reset_at_aw_done;
    logic       jtag_reset_at_w_done;
    logic       jtag_reset_at_ar_done;
    logic       jtag_tap_reset_sequence_done;
    logic       jtag_stim_done;
    string      selected_uvm_test;
    logic       mailbox_finish_enable;
    logic       retire_mailbox_finish_pending;
    logic [7:0] reset_recovery_pulse_count;
    logic       cpu_cp0_mailbox_success_seen;
    logic       cpu_cp0_exception_entry_seen;
    logic       cpu_cp0_intr_seen;
    logic       cpu_cp0_syscall_seen;
    logic       cpu_cp0_ri_seen;
    logic       cpu_cp0_adel_seen;
    logic       cpu_cp0_eret_seen;
    logic       cpu_cp0_exl_set_seen;
    logic       cpu_cp0_exl_clear_seen;
    logic       cpu_cp0_epc_update_seen;
    logic       cpu_cp0_prev_exl;
    logic [31:0] cpu_cp0_prev_epc;
    logic [4:0]  cpu_cp0_last_except_code;
    integer     cpu_cp0_intr_count;
    integer     cpu_cp0_syscall_count;
    integer     cpu_cp0_ri_count;
    integer     cpu_cp0_adel_count;
    integer     cpu_cp0_eret_count;

    initial begin
        tck = 0;
        tms = 1;
        tdi = 0;
        initial_reset_released = 1'b0;
        jtag_axi_cmd_sequence_done = 1'b0;
        jtag_reset_at_aw_done = 1'b0;
        jtag_reset_at_w_done = 1'b0;
        jtag_reset_at_ar_done = 1'b0;
        jtag_tap_reset_sequence_done = 1'b0;
        jtag_stim_done = 1'b0;
        mailbox_finish_enable = 1'b1;
        retire_mailbox_finish_pending = 1'b0;
        reset_recovery_pulse_count = 8'd0;
        cpu_cp0_mailbox_success_seen = 1'b0;
        cpu_cp0_exception_entry_seen = 1'b0;
        cpu_cp0_intr_seen = 1'b0;
        cpu_cp0_syscall_seen = 1'b0;
        cpu_cp0_ri_seen = 1'b0;
        cpu_cp0_adel_seen = 1'b0;
        cpu_cp0_eret_seen = 1'b0;
        cpu_cp0_exl_set_seen = 1'b0;
        cpu_cp0_exl_clear_seen = 1'b0;
        cpu_cp0_epc_update_seen = 1'b0;
        cpu_cp0_prev_exl = 1'b0;
        cpu_cp0_prev_epc = 32'd0;
        cpu_cp0_last_except_code = 5'd0;
        cpu_cp0_intr_count = 0;
        cpu_cp0_syscall_count = 0;
        cpu_cp0_ri_count = 0;
        cpu_cp0_adel_count = 0;
        cpu_cp0_eret_count = 0;
    end

    // Clock Generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Reset Generation
    initial begin
        rst_n = 0;
        #50;
        rst_n = 1;
        initial_reset_released = 1'b1;
    end

    // JTAG TAP Coverage Stimulus
    task pulse_recovery_reset();
        rst_n = 0;
        reset_recovery_pulse_count = reset_recovery_pulse_count + 8'd1;
        #5;
        rst_n = 1;
    endtask

    task jtag_tick(input logic next_tms, input logic next_tdi);
        tms = next_tms;
        tdi = next_tdi;
        #5 tck = 1;
        #10 tck = 0;
        #5;
    endtask

    task jtag_write_ir(input logic [3:0] ir_val);
        repeat (5) begin
            jtag_tick(1, 0); // Force TEST_LOGIC_RESET from any TAP state
        end
        jtag_tick(0, 0); // RUN_TEST_IDLE

        // IDLE -> SEL_DR -> SEL_IR -> CAP_IR -> SHIFT_IR
        jtag_tick(1, 0); // SEL_DR
        jtag_tick(1, 0); // SEL_IR
        jtag_tick(0, 0); // CAP_IR
        jtag_tick(0, 0); // SHIFT_IR
        
        // Shift 4 bits (LSB first). On last bit, tms=1 to enter EXIT1_IR
        jtag_tick(0, ir_val[0]);
        jtag_tick(0, ir_val[1]);
        jtag_tick(0, ir_val[2]);
        jtag_tick(1, ir_val[3]); // EXIT1_IR
        
        jtag_tick(1, 0); // UPDATE_IR
        jtag_tick(0, 0); // RUN_TEST_IDLE
    endtask

    task jtag_write_dr_65b(input logic [64:0] dr_val);
        // IDLE -> SEL_DR -> CAP_DR -> SHIFT_DR
        jtag_tick(1, 0); // SEL_DR
        jtag_tick(0, 0); // CAP_DR
        jtag_tick(0, 0); // SHIFT_DR
        
        // Shift 65 bits
        for (int i=0; i<64; i++) begin
            jtag_tick(0, dr_val[i]);
        end
        // Last bit with tms=1 to enter EXIT1_DR
        jtag_tick(1, dr_val[64]); // EXIT1_DR
        
        jtag_tick(1, 0); // UPDATE_DR
        jtag_tick(0, 0); // RUN_TEST_IDLE
    endtask

    initial begin
        if (!$value$plusargs("UVM_TESTNAME=%s", selected_uvm_test))
            selected_uvm_test = "";
        if (selected_uvm_test != "soc_jtag_reset_recovery_test") begin
            jtag_stim_done = 1'b1;
        end else begin
        #100;
        // From RESET to IDLE
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // Traversing all branches for coverage
        // DR Branch exhaustive traverse
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(0, 1); // SHIFT_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(0, 0); // PAUSE_DR (stay)
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(0, 0); // SHIFT_DR (loop back)
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(1, 0); // UPDATE_DR
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // DR Additional Missing Transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR (covers CAPTURE_DR->EXIT1_DR)
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(1, 0); // UPDATE_DR (covers EXIT2_DR->UPDATE_DR)
        jtag_tick(1, 0); // SELECT_DR_SCAN (covers UPDATE_DR->SELECT_DR_SCAN)
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // IR Branch exhaustive traverse
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(0, 0); // CAPTURE_IR
        jtag_tick(0, 1); // SHIFT_IR
        jtag_tick(1, 0); // EXIT1_IR
        jtag_tick(0, 0); // PAUSE_IR
        jtag_tick(0, 0); // PAUSE_IR (stay)
        jtag_tick(1, 0); // EXIT2_IR
        jtag_tick(0, 0); // SHIFT_IR (loop back)
        jtag_tick(1, 0); // EXIT1_IR
        jtag_tick(1, 0); // UPDATE_IR
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // IR Additional Missing Transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(0, 0); // CAPTURE_IR
        jtag_tick(1, 0); // EXIT1_IR (covers CAPTURE_IR->EXIT1_IR)
        jtag_tick(0, 0); // PAUSE_IR
        jtag_tick(1, 0); // EXIT2_IR
        jtag_tick(1, 0); // UPDATE_IR (covers EXIT2_IR->UPDATE_IR)
        jtag_tick(1, 0); // SELECT_DR_SCAN (covers UPDATE_IR->SELECT_DR_SCAN)
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // Now trigger real AXI transactions via JTAG
        jtag_write_ir(4'h8); // IR_AXI_CMD
        // AXI Write: [64]=1(Write), [63:32]=Addr(0x4000_0010), [31:0]=Data(0x12345678)
        jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h12345678});
        #500; // wait for AXI FSM
        
        // AXI Read: [64]=0(Read), [63:32]=Addr(0x4000_0010), [31:0]=Dummy
        jtag_write_dr_65b({1'b0, 32'h4000_0010, 32'h00000000});
        #500; // wait for AXI FSM
        
        // Toggle boost for JTAG DR (AXI Writes with full bit flips)
        jtag_write_dr_65b({1'b1, 32'hFFFF_FFFF, 32'hFFFF_FFFF}); // Unmapped addr, will trigger DECERR but JTAG handles it
        #500;
        jtag_write_dr_65b({1'b1, 32'hAAAA_AAAA, 32'hAAAA_AAAA});
        #500;
        jtag_write_dr_65b({1'b1, 32'h5555_5555, 32'h5555_5555});
        #500;
        jtag_write_dr_65b({1'b0, 32'h0000_0000, 32'h0000_0000});
        #500;
        jtag_axi_cmd_sequence_done = 1'b1;
        
        // Return to RESET
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        
        // --- Coverage for Asynchronous Resets (rst_n / trst_n) ---
        // AXI FSM Async Resets
        fork
            begin // Thread 1: Trigger JTAG AXI Write
                jtag_write_ir(4'h8); // IR_AXI_CMD
                jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h00000000});
            end
            begin // Thread 2: Intercept at ST_AW
                wait(jtag_axi_state == 3'd1); // ST_AW
                pulse_recovery_reset();
                jtag_reset_at_aw_done = 1'b1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(jtag_axi_state == 3'd2); // ST_W
                pulse_recovery_reset();
                jtag_reset_at_w_done = 1'b1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b0, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(jtag_axi_state == 3'd4); // ST_AR
                pulse_recovery_reset();
                jtag_reset_at_ar_done = 1'b1;
            end
        join

        // TAP Controller Async Resets
        // We will just do a few common states that missed TEST_LOGIC_RESET transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        pulse_recovery_reset();
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        pulse_recovery_reset();
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        pulse_recovery_reset();
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        pulse_recovery_reset();
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        pulse_recovery_reset();
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(1, 0); // UPDATE_DR
        pulse_recovery_reset();
        jtag_tap_reset_sequence_done = 1'b1;
        
        // Wait a bit before firmware continues
        #100;
        jtag_stim_done = 1'b1;
        end
    end

    // Instantiate verification SoC wrapper
    soc_verif_top u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo),
        
        // External UVM AXI Master
        .ext_awid    (axi_master_vif.awid),
        .ext_awaddr  (axi_master_vif.awaddr),
        .ext_awlen   (axi_master_vif.awlen),
        .ext_awsize  (axi_master_vif.awsize),
        .ext_awburst (axi_master_vif.awburst),
        .ext_awlock  (axi_master_vif.awlock),
        .ext_awcache (axi_master_vif.awcache),
        .ext_awprot  (axi_master_vif.awprot),
        .ext_awvalid (axi_master_vif.awvalid),
        .ext_awready (axi_master_vif.awready),
        .ext_wdata   (axi_master_vif.wdata),
        .ext_wstrb   (axi_master_vif.wstrb),
        .ext_wlast   (axi_master_vif.wlast),
        .ext_wvalid  (axi_master_vif.wvalid),
        .ext_wready  (axi_master_vif.wready),
        .ext_bid     (axi_master_vif.bid),
        .ext_bresp   (axi_master_vif.bresp),
        .ext_bvalid  (axi_master_vif.bvalid),
        .ext_bready  (axi_master_vif.bready),
        .ext_arid    (axi_master_vif.arid),
        .ext_araddr  (axi_master_vif.araddr),
        .ext_arlen   (axi_master_vif.arlen),
        .ext_arsize  (axi_master_vif.arsize),
        .ext_arburst (axi_master_vif.arburst),
        .ext_arlock  (axi_master_vif.arlock),
        .ext_arcache (axi_master_vif.arcache),
        .ext_arprot  (axi_master_vif.arprot),
        .ext_arvalid (axi_master_vif.arvalid),
        .ext_arready (axi_master_vif.arready),
        .ext_rid     (axi_master_vif.rid),
        .ext_rdata   (axi_master_vif.rdata),
        .ext_rresp   (axi_master_vif.rresp),
        .ext_rlast   (axi_master_vif.rlast),
        .ext_rvalid  (axi_master_vif.rvalid),
        .ext_rready  (axi_master_vif.rready),

        .s0_awid       (mon_s0_awid),
        .s0_awaddr     (mon_s0_awaddr),
        .s0_awlen      (mon_s0_awlen),
        .s0_awsize     (mon_s0_awsize),
        .s0_awburst    (mon_s0_awburst),
        .s0_awlock     (mon_s0_awlock),
        .s0_awcache    (mon_s0_awcache),
        .s0_awprot     (mon_s0_awprot),
        .s0_awvalid    (mon_s0_awvalid),
        .s0_awready    (mon_s0_awready),
        .s0_wdata      (mon_s0_wdata),
        .s0_wstrb      (mon_s0_wstrb),
        .s0_wlast      (mon_s0_wlast),
        .s0_wvalid     (mon_s0_wvalid),
        .s0_wready     (mon_s0_wready),
        .s0_bid        (mon_s0_bid),
        .s0_bresp      (mon_s0_bresp),
        .s0_bvalid     (mon_s0_bvalid),
        .s0_bready     (mon_s0_bready),
        .s0_arid       (mon_s0_arid),
        .s0_araddr     (mon_s0_araddr),
        .s0_arlen      (mon_s0_arlen),
        .s0_arsize     (mon_s0_arsize),
        .s0_arburst    (mon_s0_arburst),
        .s0_arlock     (mon_s0_arlock),
        .s0_arcache    (mon_s0_arcache),
        .s0_arprot     (mon_s0_arprot),
        .s0_arvalid    (mon_s0_arvalid),
        .s0_arready    (mon_s0_arready),
        .s0_rid        (mon_s0_rid),
        .s0_rdata      (mon_s0_rdata),
        .s0_rresp      (mon_s0_rresp),
        .s0_rlast      (mon_s0_rlast),
        .s0_rvalid     (mon_s0_rvalid),
        .s0_rready     (mon_s0_rready),

        .obs_if        (soc_obs_if)
    );

    assign mailbox_valid       = soc_obs_if.mailbox_valid;
    assign mailbox_wdata       = soc_obs_if.mailbox_wdata;
    assign ex_reg_write        = soc_obs_if.ex_reg_write;
    assign ex_pc               = soc_obs_if.ex_pc;
    assign jtag_axi_state      = soc_obs_if.jtag_axi_state;
    assign cpu_cp0_except_req  = soc_obs_if.cpu_cp0_except_req;
    assign cpu_cp0_except_code = soc_obs_if.cpu_cp0_except_code;
    assign cpu_cp0_intr_req    = soc_obs_if.cpu_cp0_intr_req;
    assign cpu_cp0_eret        = soc_obs_if.cpu_cp0_eret;
    assign cpu_cp0_exl         = soc_obs_if.cpu_cp0_exl;
    assign cpu_cp0_epc         = soc_obs_if.cpu_cp0_epc;

    // Mailbox Monitor for Regression Tests
    always @(posedge clk) begin
        if (`SOC_RETIRE_TRACE_ENABLE && retire_mailbox_finish_pending) begin
            $display("REGRESSION_TEST_SUCCESS");
            $finish;
        end
        if (`SOC_RETIRE_TRACE_ENABLE && soc_obs_if.retire_valid &&
            soc_obs_if.retire_mem_valid && soc_obs_if.retire_mem_write &&
            ((soc_obs_if.retire_mem_addr == 32'ha000_fffc) ||
             (soc_obs_if.retire_mem_addr == 32'h0000_fffc)) &&
            soc_obs_if.retire_mem_wdata == 32'hdeadbeef) begin
            retire_mailbox_finish_pending <= 1'b1;
        end
        if (mailbox_valid && mailbox_finish_enable && !`SOC_RETIRE_TRACE_ENABLE) begin
            if (mailbox_wdata == 32'hdeadbeef) begin
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (mailbox_wdata == 32'hdeaddead) begin
                $display("REGRESSION_TEST_FAILED");
                $finish;
            end
        end
    end

    // A system-mode retire trace must distinguish an architectural redirect
    // from an aggregate SoC reset. Keep this diagnostic opt-in with the trace
    // path so ordinary UVM logs and DUT behavior are unchanged.
    always @(negedge u_soc.u_dut.soc_rst_n) begin
        if (`SOC_RETIRE_TRACE_ENABLE)
            $display("RETIRE_TRACE_SOC_RESET time=%0t wdt_reset=%0b",
                     $time, u_soc.u_dut.wdt_reset);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_cp0_mailbox_success_seen <= 1'b0;
            cpu_cp0_exception_entry_seen <= 1'b0;
            cpu_cp0_intr_seen            <= 1'b0;
            cpu_cp0_syscall_seen         <= 1'b0;
            cpu_cp0_ri_seen              <= 1'b0;
            cpu_cp0_adel_seen            <= 1'b0;
            cpu_cp0_eret_seen            <= 1'b0;
            cpu_cp0_exl_set_seen         <= 1'b0;
            cpu_cp0_exl_clear_seen       <= 1'b0;
            cpu_cp0_epc_update_seen      <= 1'b0;
            cpu_cp0_prev_exl             <= 1'b0;
            cpu_cp0_prev_epc             <= 32'd0;
            cpu_cp0_last_except_code     <= 5'd0;
            cpu_cp0_intr_count           <= 0;
            cpu_cp0_syscall_count        <= 0;
            cpu_cp0_ri_count             <= 0;
            cpu_cp0_adel_count           <= 0;
            cpu_cp0_eret_count           <= 0;
        end else begin
            if (mailbox_valid && mailbox_wdata == 32'hdeadbeef) begin
                cpu_cp0_mailbox_success_seen <= 1'b1;
            end

            if (cpu_cp0_except_req && !cpu_cp0_exl) begin
                cpu_cp0_exception_entry_seen <= 1'b1;
                cpu_cp0_last_except_code <= cpu_cp0_except_code;
                if (cpu_cp0_intr_req) begin
                    cpu_cp0_intr_seen  <= 1'b1;
                    cpu_cp0_intr_count <= cpu_cp0_intr_count + 1;
                end else begin
                    case (cpu_cp0_except_code)
                        5'h08: begin
                            cpu_cp0_syscall_seen  <= 1'b1;
                            cpu_cp0_syscall_count <= cpu_cp0_syscall_count + 1;
                        end
                        5'h0a: begin
                            cpu_cp0_ri_seen  <= 1'b1;
                            cpu_cp0_ri_count <= cpu_cp0_ri_count + 1;
                        end
                        5'h04: begin
                            cpu_cp0_adel_seen  <= 1'b1;
                            cpu_cp0_adel_count <= cpu_cp0_adel_count + 1;
                        end
                    endcase
                end
            end

            if (cpu_cp0_eret) begin
                cpu_cp0_eret_seen  <= 1'b1;
                cpu_cp0_eret_count <= cpu_cp0_eret_count + 1;
            end

            if (!cpu_cp0_prev_exl && cpu_cp0_exl) begin
                cpu_cp0_exl_set_seen <= 1'b1;
            end
            if (cpu_cp0_prev_exl && !cpu_cp0_exl) begin
                cpu_cp0_exl_clear_seen <= 1'b1;
            end
            if (cpu_cp0_epc != 32'd0 && cpu_cp0_epc != cpu_cp0_prev_epc) begin
                cpu_cp0_epc_update_seen <= 1'b1;
            end

            cpu_cp0_prev_exl <= cpu_cp0_exl;
            cpu_cp0_prev_epc <= cpu_cp0_epc;
        end
    end



    // Debug PC Trace at end
    initial begin
        #5000000000; // wait 5 ms
        $display("START TRACING PCs to catch deadlock");
        for (int i=0; i<100; i++) begin
            @(posedge clk);
            if (ex_reg_write)
                $display("[%t] EX PC = %h", $time, ex_pc);
        end
        $finish;
    end

    // Bind SoC Master outputs -> UVM VIP inputs
    assign axi_vif.awid    = mon_s0_awid;
    assign axi_vif.awaddr  = mon_s0_awaddr;
    assign axi_vif.awlen   = mon_s0_awlen;
    assign axi_vif.awsize  = mon_s0_awsize;
    assign axi_vif.awburst = mon_s0_awburst;
    assign axi_vif.awlock  = mon_s0_awlock;
    assign axi_vif.awcache = mon_s0_awcache;
    assign axi_vif.awprot  = mon_s0_awprot;
    assign axi_vif.awvalid = mon_s0_awvalid;
    assign axi_vif.awready = mon_s0_awready;
    
    assign axi_vif.wid     = 4'd0; // s_wid removed in some AXI4, default to 0
    assign axi_vif.wdata   = mon_s0_wdata;
    assign axi_vif.wstrb   = mon_s0_wstrb;
    assign axi_vif.wlast   = mon_s0_wlast;
    assign axi_vif.wvalid  = mon_s0_wvalid;
    assign axi_vif.wready  = mon_s0_wready;
    
    assign axi_vif.bid     = mon_s0_bid;
    assign axi_vif.bresp   = mon_s0_bresp;
    assign axi_vif.bvalid  = mon_s0_bvalid;
    assign axi_vif.bready  = mon_s0_bready;
    
    assign axi_vif.arid    = mon_s0_arid;
    assign axi_vif.araddr  = mon_s0_araddr;
    assign axi_vif.arlen   = mon_s0_arlen;
    assign axi_vif.arsize  = mon_s0_arsize;
    assign axi_vif.arburst = mon_s0_arburst;
    assign axi_vif.arlock  = mon_s0_arlock;
    assign axi_vif.arcache = mon_s0_arcache;
    assign axi_vif.arprot  = mon_s0_arprot;
    assign axi_vif.arvalid = mon_s0_arvalid;
    assign axi_vif.arready = mon_s0_arready;
    
    assign axi_vif.rid     = mon_s0_rid;
    assign axi_vif.rdata   = mon_s0_rdata;
    assign axi_vif.rresp   = mon_s0_rresp;
    assign axi_vif.rlast   = mon_s0_rlast;
    assign axi_vif.rvalid  = mon_s0_rvalid;
    assign axi_vif.rready  = mon_s0_rready;

    // Phase C.3: the crossbar accepts multiple outstanding transactions from a
    // master across different slaves (concurrent cross-slave traffic). The ext
    // master legitimately overlaps requests now, so single-outstanding is no
    // longer the contract at this port. Payload-stability and W-after-AW still
    // hold and are still checked.
    axi_protocol_checker #(
        .CHECKER_NAME("ext_axi_master"),
        .REQUIRE_SINGLE_OUTSTANDING(1'b0),
        .REQUIRE_W_AFTER_AW(1'b1)
    ) u_ext_axi_protocol_checker (
        .clk     (clk),
        .rst_n   (rst_n),
        .awid    (axi_master_vif.awid),
        .awaddr  (axi_master_vif.awaddr),
        .awlen   (axi_master_vif.awlen),
        .awsize  (axi_master_vif.awsize),
        .awburst (axi_master_vif.awburst),
        .awlock  (axi_master_vif.awlock),
        .awcache (axi_master_vif.awcache),
        .awprot  (axi_master_vif.awprot),
        .awvalid (axi_master_vif.awvalid),
        .awready (axi_master_vif.awready),
        .wdata   (axi_master_vif.wdata),
        .wstrb   (axi_master_vif.wstrb),
        .wlast   (axi_master_vif.wlast),
        .wvalid  (axi_master_vif.wvalid),
        .wready  (axi_master_vif.wready),
        .bid     (axi_master_vif.bid),
        .bresp   (axi_master_vif.bresp),
        .bvalid  (axi_master_vif.bvalid),
        .bready  (axi_master_vif.bready),
        .arid    (axi_master_vif.arid),
        .araddr  (axi_master_vif.araddr),
        .arlen   (axi_master_vif.arlen),
        .arsize  (axi_master_vif.arsize),
        .arburst (axi_master_vif.arburst),
        .arlock  (axi_master_vif.arlock),
        .arcache (axi_master_vif.arcache),
        .arprot  (axi_master_vif.arprot),
        .arvalid (axi_master_vif.arvalid),
        .arready (axi_master_vif.arready),
        .rid     (axi_master_vif.rid),
        .rdata   (axi_master_vif.rdata),
        .rresp   (axi_master_vif.rresp),
        .rlast   (axi_master_vif.rlast),
        .rvalid  (axi_master_vif.rvalid),
        .rready  (axi_master_vif.rready)
    );

    axi_protocol_checker #(
        .CHECKER_NAME("sram_axi_monitor"),
        .REQUIRE_SINGLE_OUTSTANDING(1'b1),
        .REQUIRE_W_AFTER_AW(1'b1)
    ) u_sram_axi_protocol_checker (
        .clk     (clk),
        .rst_n   (rst_n),
        .awid    (axi_vif.awid),
        .awaddr  (axi_vif.awaddr),
        .awlen   (axi_vif.awlen),
        .awsize  (axi_vif.awsize),
        .awburst (axi_vif.awburst),
        .awlock  (axi_vif.awlock),
        .awcache (axi_vif.awcache),
        .awprot  (axi_vif.awprot),
        .awvalid (axi_vif.awvalid),
        .awready (axi_vif.awready),
        .wdata   (axi_vif.wdata),
        .wstrb   (axi_vif.wstrb),
        .wlast   (axi_vif.wlast),
        .wvalid  (axi_vif.wvalid),
        .wready  (axi_vif.wready),
        .bid     (axi_vif.bid),
        .bresp   (axi_vif.bresp),
        .bvalid  (axi_vif.bvalid),
        .bready  (axi_vif.bready),
        .arid    (axi_vif.arid),
        .araddr  (axi_vif.araddr),
        .arlen   (axi_vif.arlen),
        .arsize  (axi_vif.arsize),
        .arburst (axi_vif.arburst),
        .arlock  (axi_vif.arlock),
        .arcache (axi_vif.arcache),
        .arprot  (axi_vif.arprot),
        .arvalid (axi_vif.arvalid),
        .arready (axi_vif.arready),
        .rid     (axi_vif.rid),
        .rdata   (axi_vif.rdata),
        .rresp   (axi_vif.rresp),
        .rlast   (axi_vif.rlast),
        .rvalid  (axi_vif.rvalid),
        .rready  (axi_vif.rready)
    );

    initial begin
        uvm_config_db#(virtual axi_if)::set(null, "*env.m_axi_agent*", "vif", axi_vif);
        uvm_config_db#(virtual axi_master_if)::set(null, "*env.m_axi_master_agent*", "vif", axi_master_vif);
        
        $display("========================================");
        $display("  Starting MIPS32 SoC UVM Environment   ");
        $display("========================================");
        
        run_test("soc_base_test");
    end

    initial begin
        // Waveform dumping can be added here
    end

endmodule
