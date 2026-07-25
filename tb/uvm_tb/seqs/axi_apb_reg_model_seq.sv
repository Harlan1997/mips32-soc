`ifndef AXI_APB_REG_MODEL_SEQ_SV
`define AXI_APB_REG_MODEL_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_apb_reg_model_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_apb_reg_model_seq)

    localparam logic [31:0] UART_TX_ADDR      = `SOC_APB_BASE + `SOC_APB_UART_OFFSET  + `SOC_UART_TX_OFFSET;
    localparam logic [31:0] UART_STATUS_ADDR  = `SOC_APB_BASE + `SOC_APB_UART_OFFSET  + `SOC_UART_STATUS_OFFSET;
    localparam logic [31:0] TIMER_CTRL_ADDR   = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET;
    localparam logic [31:0] TIMER_LOAD_ADDR   = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR    = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;
    localparam logic [31:0] TIMER_INT_ADDR    = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR     = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_ACTIVE_OFFSET;

    function new(string name = "axi_apb_reg_model_seq");
        super.new(name);
    endfunction

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = $urandom_range(0, 15);
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
            `uvm_error("APB_REG", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_read_word(string item_name, logic [31:0] addr, logic [31:0] expected, logic [31:0] mask);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = $urandom_range(0, 15);
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
            `uvm_error("APB_REG", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        if ((tr.data[0] & mask) != (expected & mask)) begin
            `uvm_error("APB_REG", $sformatf("%s read addr=0x%08h data=0x%08h expected=0x%08h mask=0x%08h",
                       item_name, addr, tr.data[0], expected, mask))
        end
    endtask

    task do_read_burst_check(string item_name, logic [31:0] addr,
                             logic [31:0] expected[]);
        axi_transaction tr;
        int unsigned beats;

        beats = expected.size();
        if (beats == 0) begin
            `uvm_error("APB_REG", $sformatf("%s expected data array is empty", item_name))
            return;
        end

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = $urandom_range(0, 15);
        tr.addr       = addr;
        tr.len        = beats - 1;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[beats];
        tr.strb       = new[beats];
        tr.resp       = new[beats];
        foreach (tr.strb[i]) begin
            tr.strb[i] = 4'hF;
            tr.resp[i] = `SOC_AXI_RESP_OKAY;
        end
        finish_item(tr);

        foreach (expected[i]) begin
            if (tr.resp[i] != `SOC_AXI_RESP_OKAY) begin
                `uvm_error("APB_REG", $sformatf("%s read beat=%0d addr=0x%08h resp=%0h expected OKAY",
                           item_name, i, addr + (i << 2), tr.resp[i]))
            end
            if (tr.data[i] !== expected[i]) begin
                `uvm_error("APB_REG", $sformatf("%s read beat=%0d addr=0x%08h data=0x%08h expected=0x%08h",
                           item_name, i, addr + (i << 2), tr.data[i], expected[i]))
            end
        end
    endtask

    task body();
        logic [31:0] timer_burst_expected[];

        do_read_word("uart_tx_reset_read", UART_TX_ADDR, 32'h0000_0000, 32'hFFFF_FFFF);
        do_read_word("uart_status_ready_read", UART_STATUS_ADDR, 32'h0000_0001, 32'hFFFF_FFFF);
        do_write_word("uart_tx_write_A", UART_TX_ADDR, 32'h0000_0041);

        do_write_word("timer_ctrl_disable", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_read_word("timer_ctrl_read_disable", TIMER_CTRL_ADDR, 32'h0000_0000, 32'hFFFF_FFFF);
        do_write_word("timer_load_write", TIMER_LOAD_ADDR, 32'h0000_0020);
        do_read_word("timer_load_read", TIMER_LOAD_ADDR, 32'h0000_0020, 32'hFFFF_FFFF);
        do_read_word("timer_val_after_load_read", TIMER_VAL_ADDR, 32'h0000_0020, 32'hFFFF_FFFF);
        do_write_word("timer_val_write", TIMER_VAL_ADDR, 32'h0000_0055);
        do_read_word("timer_val_read", TIMER_VAL_ADDR, 32'h0000_0055, 32'hFFFF_FFFF);
        timer_burst_expected = new[4];
        timer_burst_expected[0] = 32'h0000_0000;
        timer_burst_expected[1] = 32'h0000_0020;
        timer_burst_expected[2] = 32'h0000_0055;
        timer_burst_expected[3] = 32'h0000_0000;
        do_read_burst_check("timer_ctrl_load_val_int_burst_read", TIMER_CTRL_ADDR,
                            timer_burst_expected);
        do_write_word("timer_int_clear", TIMER_INT_ADDR, 32'h0000_0001);
        do_read_word("timer_int_read_clear", TIMER_INT_ADDR, 32'h0000_0000, 32'h0000_0001);

        do_write_word("pic_mask_clear", PIC_MASK_ADDR, 32'h0000_0000);
        do_read_word("pic_active_zero_mask", PIC_ACTIVE_ADDR, 32'h0000_0000, 32'hFFFF_FFFF);
        do_read_word("pic_status_smoke", PIC_STATUS_ADDR, 32'h0000_0000, 32'h0000_0000);
        do_write_word("pic_mask_write", PIC_MASK_ADDR, 32'h0000_0005);
        do_read_word("pic_mask_read", PIC_MASK_ADDR, 32'h0000_0005, 32'hFFFF_FFFF);
        do_write_word("pic_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_read_word("pic_mask_read_zero", PIC_MASK_ADDR, 32'h0000_0000, 32'hFFFF_FFFF);
        do_read_word("pic_active_zero_mask_final", PIC_ACTIVE_ADDR, 32'h0000_0000, 32'hFFFF_FFFF);
    endtask
endclass

`endif
