`ifndef SOC_JTAG_RESET_RECOVERY_TEST_SV
`define SOC_JTAG_RESET_RECOVERY_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"

class soc_jtag_reset_recovery_test extends soc_base_test;
    `uvm_component_utils(soc_jtag_reset_recovery_test)

    localparam int EV_INITIAL_RESET = 0;
    localparam int EV_AXI_CMD_DONE  = 1;
    localparam int EV_RESET_AW      = 2;
    localparam int EV_RESET_W       = 3;
    localparam int EV_RESET_AR      = 4;
    localparam int EV_TAP_RESET     = 5;
    localparam int EV_STIM_DONE     = 6;

    int unsigned jtag_event_sample;
    int unsigned jtag_pulse_sample;

    covergroup jtag_reset_event_cg;
        option.per_instance = 1;

        event_cp: coverpoint jtag_event_sample {
            bins initial_reset_released = {EV_INITIAL_RESET};
            bins axi_cmd_sequence_done  = {EV_AXI_CMD_DONE};
            bins reset_at_aw            = {EV_RESET_AW};
            bins reset_at_w             = {EV_RESET_W};
            bins reset_at_ar            = {EV_RESET_AR};
            bins tap_reset_sequence     = {EV_TAP_RESET};
            bins jtag_stim_done         = {EV_STIM_DONE};
        }
    endgroup

    covergroup jtag_recovery_pulse_cg;
        option.per_instance = 1;

        pulse_count_cp: coverpoint jtag_pulse_sample {
            illegal_bins too_few      = {[0:8]};
            bins meets_requirement    = {[9:255]};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        jtag_reset_event_cg = new();
        jtag_recovery_pulse_cg = new();
    endfunction

    function void sample_jtag_event(int unsigned event_id);
        jtag_event_sample = event_id;
        jtag_reset_event_cg.sample();
    endfunction

    function void sample_recovery_pulses(int unsigned pulse_count);
        jtag_pulse_sample = pulse_count;
        jtag_recovery_pulse_cg.sample();
    endfunction

    task automatic wait_flag(input string path);
        uvm_hdl_data_t value;

        for (int i = 0; i < 500; i++) begin
            if (!uvm_hdl_read(path, value)) begin
                `uvm_fatal("JTAG_RST", $sformatf("Unable to read HDL path %s", path))
            end

            if (value[0] === 1'b1) begin
                return;
            end

            #1000;
        end

        dump_recovery_status();
        `uvm_fatal("JTAG_RST", $sformatf("Timed out waiting for %s", path))
    endtask

    task automatic dump_hdl_value(input string path);
        uvm_hdl_data_t value;

        if (uvm_hdl_read(path, value)) begin
            `uvm_info("JTAG_RST", $sformatf("%s = 0x%0h", path, value[31:0]), UVM_LOW)
        end else begin
            `uvm_info("JTAG_RST", $sformatf("%s = <unreadable>", path), UVM_LOW)
        end
    endtask

    task automatic dump_recovery_status();
        dump_hdl_value("tb_top.initial_reset_released");
        dump_hdl_value("tb_top.jtag_axi_cmd_sequence_done");
        dump_hdl_value("tb_top.jtag_reset_at_aw_done");
        dump_hdl_value("tb_top.jtag_reset_at_w_done");
        dump_hdl_value("tb_top.jtag_reset_at_ar_done");
        dump_hdl_value("tb_top.jtag_tap_reset_sequence_done");
        dump_hdl_value("tb_top.jtag_stim_done");
        dump_hdl_value("tb_top.reset_recovery_pulse_count");
        dump_hdl_value("tb_top.jtag_axi_state");
    endtask

    task automatic disable_mailbox_finish();
        if (!uvm_hdl_deposit("tb_top.mailbox_finish_enable", 1'b0)) begin
            `uvm_fatal("JTAG_RST", "Unable to disable tb_top.mailbox_finish_enable")
        end
    endtask

    task automatic expect_flag(input string path, input int event_id = -1);
        uvm_hdl_data_t value;

        if (!uvm_hdl_read(path, value)) begin
            `uvm_fatal("JTAG_RST", $sformatf("Unable to read HDL path %s", path))
        end

        if (value[0] !== 1'b1) begin
            `uvm_error("JTAG_RST", $sformatf("Expected %s to be asserted, got %0b", path, value[0]))
            return;
        end

        if (event_id >= 0) begin
            sample_jtag_event(event_id);
        end
    endtask

    task automatic expect_reset_pulse_count(input int min_count);
        uvm_hdl_data_t value;
        int pulse_count;

        if (!uvm_hdl_read("tb_top.reset_recovery_pulse_count", value)) begin
            `uvm_fatal("JTAG_RST", "Unable to read tb_top.reset_recovery_pulse_count")
        end

        pulse_count = value[7:0];
        if (pulse_count < min_count) begin
            `uvm_error("JTAG_RST", $sformatf("Expected at least %0d recovery resets, got %0d", min_count, pulse_count))
            return;
        end

        sample_recovery_pulses(pulse_count);
        `uvm_info("JTAG_RST", $sformatf("Observed %0d JTAG/reset recovery pulses", pulse_count), UVM_LOW)
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Running JTAG/reset recovery observability test...", UVM_LOW)

        disable_mailbox_finish();
        wait_flag("tb_top.jtag_stim_done");

        expect_flag("tb_top.initial_reset_released", EV_INITIAL_RESET);
        expect_flag("tb_top.jtag_axi_cmd_sequence_done", EV_AXI_CMD_DONE);
        expect_flag("tb_top.jtag_reset_at_aw_done", EV_RESET_AW);
        expect_flag("tb_top.jtag_reset_at_w_done", EV_RESET_W);
        expect_flag("tb_top.jtag_reset_at_ar_done", EV_RESET_AR);
        expect_flag("tb_top.jtag_tap_reset_sequence_done", EV_TAP_RESET);
        expect_flag("tb_top.jtag_stim_done", EV_STIM_DONE);
        expect_reset_pulse_count(9);

        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("JTAG_RST_COV",
                  $sformatf("jtag_reset_event_cov=%0.2f jtag_recovery_pulse_cov=%0.2f",
                            jtag_reset_event_cg.get_inst_coverage(),
                            jtag_recovery_pulse_cg.get_inst_coverage()), UVM_LOW)
    endfunction
endclass

`endif
