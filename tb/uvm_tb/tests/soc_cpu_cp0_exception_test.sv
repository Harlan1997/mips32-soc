`ifndef SOC_CPU_CP0_EXCEPTION_TEST_SV
`define SOC_CPU_CP0_EXCEPTION_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"

class soc_cpu_cp0_exception_test extends soc_base_test;
    `uvm_component_utils(soc_cpu_cp0_exception_test)

    localparam int EV_INTR    = 0;
    localparam int EV_SYSCALL = 1;
    localparam int EV_RI      = 2;
    localparam int EV_ADEL    = 3;
    localparam int EV_ERET    = 4;
    localparam int EV_EXL_SET = 5;
    localparam int EV_EXL_CLR = 6;
    localparam int EV_EPC     = 7;
    localparam int EV_ENTRY   = 8;

    int unsigned cp0_event_sample;
    int unsigned cp0_count_sample;

    covergroup cpu_cp0_exception_event_cg;
        option.per_instance = 1;

        event_cp: coverpoint cp0_event_sample {
            bins exception_entry = {EV_ENTRY};
            bins interrupt_entry = {EV_INTR};
            bins syscall_entry   = {EV_SYSCALL};
            bins ri_entry        = {EV_RI};
            bins adel_entry      = {EV_ADEL};
            bins eret_return     = {EV_ERET};
            bins exl_set         = {EV_EXL_SET};
            bins exl_clear       = {EV_EXL_CLR};
            bins epc_update      = {EV_EPC};
        }
    endgroup

    covergroup cpu_cp0_exception_count_cg;
        option.per_instance = 1;

        count_cp: coverpoint cp0_count_sample {
            illegal_bins zero = {0};
            bins observed = {[1:255]};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cpu_cp0_exception_event_cg = new();
        cpu_cp0_exception_count_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        cp0_event_sample = event_id;
        cpu_cp0_exception_event_cg.sample();
    endfunction

    function void sample_count(int unsigned count);
        cp0_count_sample = count;
        cpu_cp0_exception_count_cg.sample();
    endfunction

    task automatic disable_mailbox_finish();
        if (!uvm_hdl_deposit("tb_top.mailbox_finish_enable", 1'b0)) begin
            `uvm_fatal("CPU_CP0", "Unable to disable tb_top.mailbox_finish_enable")
        end
    endtask

    task automatic wait_flag(input string path, input int timeout_cycles);
        uvm_hdl_data_t value;

        for (int i = 0; i < timeout_cycles; i++) begin
            if (!uvm_hdl_read(path, value)) begin
                `uvm_fatal("CPU_CP0", $sformatf("Unable to read HDL path %s", path))
            end
            if (value[0] === 1'b1) begin
                return;
            end
            #1000;
        end

        dump_cp0_status();
        `uvm_fatal("CPU_CP0", $sformatf("Timed out waiting for %s", path))
    endtask

    task automatic read_int(input string path, output int value);
        uvm_hdl_data_t hdl_value;

        if (!uvm_hdl_read(path, hdl_value)) begin
            `uvm_fatal("CPU_CP0", $sformatf("Unable to read HDL path %s", path))
        end
        value = hdl_value[31:0];
    endtask

    task automatic expect_flag(input string path, input int event_id);
        uvm_hdl_data_t value;

        if (!uvm_hdl_read(path, value)) begin
            `uvm_fatal("CPU_CP0", $sformatf("Unable to read HDL path %s", path))
        end

        if (value[0] !== 1'b1) begin
            `uvm_error("CPU_CP0", $sformatf("Expected %s to be asserted, got %0b", path, value[0]))
            return;
        end

        sample_event(event_id);
    endtask

    task automatic expect_count(input string path);
        int value;

        read_int(path, value);
        if (value <= 0) begin
            `uvm_error("CPU_CP0", $sformatf("Expected nonzero %s, got %0d", path, value))
            return;
        end

        sample_count(value);
        `uvm_info("CPU_CP0", $sformatf("%s=%0d", path, value), UVM_LOW)
    endtask

    task automatic dump_hdl_value(input string path);
        uvm_hdl_data_t value;

        if (uvm_hdl_read(path, value)) begin
            `uvm_info("CPU_CP0", $sformatf("%s = 0x%0h", path, value[31:0]), UVM_LOW)
        end else begin
            `uvm_info("CPU_CP0", $sformatf("%s = <unreadable>", path), UVM_LOW)
        end
    endtask

    task automatic dump_cp0_status();
        dump_hdl_value("tb_top.cpu_cp0_mailbox_success_seen");
        dump_hdl_value("tb_top.cpu_cp0_exception_entry_seen");
        dump_hdl_value("tb_top.cpu_cp0_intr_seen");
        dump_hdl_value("tb_top.cpu_cp0_syscall_seen");
        dump_hdl_value("tb_top.cpu_cp0_ri_seen");
        dump_hdl_value("tb_top.cpu_cp0_adel_seen");
        dump_hdl_value("tb_top.cpu_cp0_eret_seen");
        dump_hdl_value("tb_top.cpu_cp0_exl_set_seen");
        dump_hdl_value("tb_top.cpu_cp0_exl_clear_seen");
        dump_hdl_value("tb_top.cpu_cp0_epc_update_seen");
        dump_hdl_value("tb_top.cpu_cp0_intr_count");
        dump_hdl_value("tb_top.cpu_cp0_syscall_count");
        dump_hdl_value("tb_top.cpu_cp0_ri_count");
        dump_hdl_value("tb_top.cpu_cp0_adel_count");
        dump_hdl_value("tb_top.cpu_cp0_eret_count");
        dump_hdl_value("tb_top.cpu_cp0_last_except_code");
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Running CPU/CP0 UVM-visible exception coverage test...", UVM_LOW)

        disable_mailbox_finish();
        wait_flag("tb_top.cpu_cp0_mailbox_success_seen", 6000000);

        expect_flag("tb_top.cpu_cp0_exception_entry_seen", EV_ENTRY);
        expect_flag("tb_top.cpu_cp0_intr_seen", EV_INTR);
        expect_flag("tb_top.cpu_cp0_syscall_seen", EV_SYSCALL);
        expect_flag("tb_top.cpu_cp0_ri_seen", EV_RI);
        expect_flag("tb_top.cpu_cp0_adel_seen", EV_ADEL);
        expect_flag("tb_top.cpu_cp0_eret_seen", EV_ERET);
        expect_flag("tb_top.cpu_cp0_exl_set_seen", EV_EXL_SET);
        expect_flag("tb_top.cpu_cp0_exl_clear_seen", EV_EXL_CLR);
        expect_flag("tb_top.cpu_cp0_epc_update_seen", EV_EPC);

        expect_count("tb_top.cpu_cp0_intr_count");
        expect_count("tb_top.cpu_cp0_syscall_count");
        expect_count("tb_top.cpu_cp0_ri_count");
        expect_count("tb_top.cpu_cp0_adel_count");
        expect_count("tb_top.cpu_cp0_eret_count");

        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("CPU_CP0_COV",
                  $sformatf("cpu_cp0_exception_event_cov=%0.2f cpu_cp0_exception_count_cov=%0.2f",
                            cpu_cp0_exception_event_cg.get_inst_coverage(),
                            cpu_cp0_exception_count_cg.get_inst_coverage()), UVM_LOW)
    endfunction
endclass

`endif
