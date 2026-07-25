`ifndef AXI_TIMER_IRQ_SEQ_SV
`define AXI_TIMER_IRQ_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_timer_irq_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_timer_irq_seq)

    localparam int EV_MASK_ENABLE  = 0;
    localparam int EV_TIMER_ENABLE = 1;
    localparam int EV_PIC_ASSERT   = 2;
    localparam int EV_TIMER_CLEAR  = 3;
    localparam int EV_PIC_CLEAR    = 4;
    localparam int EV_MASK_RESTORE = 5;

    localparam logic [31:0] TIMER_CTRL_ADDR = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET;
    localparam logic [31:0] TIMER_LOAD_ADDR = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR  = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;
    localparam logic [31:0] TIMER_INT_ADDR  = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_ACTIVE_OFFSET;
    localparam logic [31:0] TIMER_IRQ_MASK  = 32'h0000_0004;

    int unsigned timer_irq_event_sample;
    int unsigned timer_irq_poll_count_sample;

    covergroup timer_irq_event_cg;
        option.per_instance = 1;

        event_cp: coverpoint timer_irq_event_sample {
            bins pic_mask_enable  = {EV_MASK_ENABLE};
            bins timer_enable     = {EV_TIMER_ENABLE};
            bins pic_asserted     = {EV_PIC_ASSERT};
            bins timer_int_clear  = {EV_TIMER_CLEAR};
            bins pic_cleared      = {EV_PIC_CLEAR};
            bins pic_mask_restore = {EV_MASK_RESTORE};
        }
    endgroup

    covergroup timer_irq_latency_cg;
        option.per_instance = 1;

        poll_count_cp: coverpoint timer_irq_poll_count_sample {
            illegal_bins not_observed = {0};
            bins observed             = {[1:64]};
        }
    endgroup

    function new(string name = "axi_timer_irq_seq");
        super.new(name);
        timer_irq_event_cg = new();
        timer_irq_latency_cg = new();
    endfunction

    function void sample_timer_irq_event(int unsigned event_id);
        timer_irq_event_sample = event_id;
        timer_irq_event_cg.sample();
    endfunction

    function void sample_timer_irq_latency(int unsigned poll_count);
        timer_irq_poll_count_sample = poll_count;
        timer_irq_latency_cg.sample();
    endfunction

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'd3;
        tr.addr       = addr;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.data[0]    = data;
        tr.strb[0]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("TIMER_IRQ", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_read_word(string item_name, logic [31:0] addr, output logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'd3;
        tr.addr       = addr;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.strb[0]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("TIMER_IRQ", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        data = tr.data[0];
    endtask

    task poll_pic_timer_asserted();
        logic [31:0] status;
        logic [31:0] active;

        for (int i = 0; i < 64; i++) begin
            do_read_word($sformatf("pic_timer_status_poll_%0d", i), PIC_STATUS_ADDR, status);
            do_read_word($sformatf("pic_timer_active_poll_%0d", i), PIC_ACTIVE_ADDR, active);
            if (status[2] && active[2]) begin
                sample_timer_irq_latency(i + 1);
                sample_timer_irq_event(EV_PIC_ASSERT);
                return;
            end
        end

        `uvm_error("TIMER_IRQ", "Timer interrupt did not assert through PIC within poll limit")
    endtask

    task body();
        logic [31:0] data;

        do_write_word("timer_irq_ctrl_disable", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("timer_irq_clear_before_start", TIMER_INT_ADDR, 32'h0000_0001);
        do_write_word("timer_irq_load_write", TIMER_LOAD_ADDR, 32'h0000_0003);
        do_write_word("timer_irq_val_write", TIMER_VAL_ADDR, 32'h0000_0003);
        do_write_word("pic_timer_mask_enable", PIC_MASK_ADDR, TIMER_IRQ_MASK);
        do_read_word("pic_timer_mask_read", PIC_MASK_ADDR, data);
        if (data !== TIMER_IRQ_MASK) begin
            `uvm_error("TIMER_IRQ", $sformatf("PIC MASK data=0x%08h expected=0x%08h", data, TIMER_IRQ_MASK))
        end
        sample_timer_irq_event(EV_MASK_ENABLE);

        do_write_word("timer_irq_ctrl_enable", TIMER_CTRL_ADDR, 32'h0000_0003);
        sample_timer_irq_event(EV_TIMER_ENABLE);
        poll_pic_timer_asserted();

        do_write_word("timer_irq_ctrl_disable_after_assert", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("timer_irq_clear_after_assert", TIMER_INT_ADDR, 32'h0000_0001);
        do_read_word("timer_irq_int_clear_read", TIMER_INT_ADDR, data);
        if (data[0] !== 1'b0) begin
            `uvm_error("TIMER_IRQ", $sformatf("Timer INT did not clear; INT=0x%08h", data))
        end
        sample_timer_irq_event(EV_TIMER_CLEAR);

        do_read_word("pic_timer_status_cleared", PIC_STATUS_ADDR, data);
        if (data[2] !== 1'b0) begin
            `uvm_error("TIMER_IRQ", $sformatf("PIC STATUS bit2 data=0x%08h expected cleared", data))
        end
        do_read_word("pic_timer_active_cleared", PIC_ACTIVE_ADDR, data);
        if (data[2] !== 1'b0) begin
            `uvm_error("TIMER_IRQ", $sformatf("PIC ACTIVE bit2 data=0x%08h expected cleared", data))
        end
        sample_timer_irq_event(EV_PIC_CLEAR);

        do_write_word("pic_timer_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_read_word("pic_timer_mask_zero_read", PIC_MASK_ADDR, data);
        if (data !== 32'h0000_0000) begin
            `uvm_error("TIMER_IRQ", $sformatf("PIC MASK restore data=0x%08h expected=0x00000000", data))
        end
        sample_timer_irq_event(EV_MASK_RESTORE);
    endtask
endclass

`endif
