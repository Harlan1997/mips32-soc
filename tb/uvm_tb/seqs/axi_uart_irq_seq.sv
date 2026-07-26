`ifndef AXI_UART_IRQ_SEQ_SV
`define AXI_UART_IRQ_SEQ_SV

//------------------------------------------------------------------------------
// axi_uart_irq_seq
//
// Two flavors, selected at compile-time:
//   * SOC_USE_UART_16550 defined  → v2 flow (LSR/IER/IIR, TX drain wait)
//   * otherwise (default)         → v1 flow (STATUS/IRQ_STATUS/IRQ_CLEAR)
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_uart_irq_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_uart_irq_seq)

    localparam logic [31:0] UART_TX_ADDR         = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_TX_OFFSET;
    localparam logic [31:0] UART_STATUS_ADDR     = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_STATUS_OFFSET;
    localparam logic [31:0] UART_IRQ_STATUS_ADDR = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_IRQ_STATUS_OFFSET;
    localparam logic [31:0] UART_IRQ_CLEAR_ADDR  = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_IRQ_CLEAR_OFFSET;
    localparam logic [31:0] UART_IER_ADDR        = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + 32'h04;
    localparam logic [31:0] UART_IIR_ADDR        = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + 32'h08;
    localparam logic [31:0] UART_LCR_ADDR        = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + 32'h0C;
    localparam logic [31:0] UART_LSR_ADDR        = `SOC_APB_BASE + `SOC_APB_UART_OFFSET + 32'h14;

    localparam logic [31:0] PIC_STATUS_ADDR      = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR        = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR      = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_ACTIVE_OFFSET;
    localparam logic [31:0] UART_TX_IRQ_MASK     = 32'h0000_0002;

    int unsigned uart_irq_event_sample;
    covergroup uart_irq_event_cg;
        option.per_instance = 1;
        event_cp: coverpoint uart_irq_event_sample {
            bins clear_initial = {0};
            bins tx_write      = {1};
            bins pic_assert    = {2};
            bins uart_clear    = {3};
            bins pic_clear     = {4};
        }
    endgroup

    function new(string name = "axi_uart_irq_seq");
        super.new(name);
        uart_irq_event_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        uart_irq_event_sample = event_id;
        uart_irq_event_cg.sample();
    endfunction

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        axi_transaction tr;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'h6;
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
        if (tr.resp[0] != `SOC_AXI_RESP_OKAY)
            `uvm_error("UART_IRQ", $sformatf("%s wr addr=0x%08h resp=%0h",
                                             item_name, addr, tr.resp[0]))
    endtask

    task do_read_word(string item_name, logic [31:0] addr, output logic [31:0] data);
        axi_transaction tr;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'h6;
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
        if (tr.resp[0] != `SOC_AXI_RESP_OKAY)
            `uvm_error("UART_IRQ", $sformatf("%s rd addr=0x%08h resp=%0h",
                                             item_name, addr, tr.resp[0]))
        data = tr.data[0];
    endtask

    task body();
        logic [31:0] data;

`ifdef SOC_USE_UART_16550
        int poll_iters;
        do_write_word("pic_mask_zero", PIC_MASK_ADDR, 32'h0);
        do_write_word("uart_ier_zero", UART_IER_ADDR, 32'h0);
        sample_event(0);
        do_write_word("uart_lcr_dlab_set", UART_LCR_ADDR, 32'h83);
        do_write_word("uart_dll_fast",     UART_TX_ADDR, 32'h01);
        do_write_word("uart_dlm_fast",     UART_IER_ADDR, 32'h00);
        do_write_word("uart_lcr_dlab_clr", UART_LCR_ADDR, 32'h03);
        do_write_word("uart_ier_tx_empty", UART_IER_ADDR, 32'h02);
        do_write_word("pic_mask_uart",     PIC_MASK_ADDR, UART_TX_IRQ_MASK);
        do_read_word("uart_lsr_boot", UART_LSR_ADDR, data);
        if (data[5] !== 1'b1)
            `uvm_error("UART_IRQ",
                       $sformatf("UART LSR at boot data=0x%08h expected THRE=1", data))
        do_write_word("uart_tx_write", UART_TX_ADDR, 32'h0000_0055);
        sample_event(1);
        poll_iters = 0;
        do begin
            do_read_word("uart_lsr_poll", UART_LSR_ADDR, data);
            poll_iters++;
        end while (!(data[5] && data[6]) && poll_iters < 1000);
        if (poll_iters >= 1000)
            `uvm_error("UART_IRQ",
                       $sformatf("UART LSR THRE+TEMT never rose; last=0x%08h", data))
        do_read_word("uart_iir_check", UART_IIR_ADDR, data);
        sample_event(2);
        do_read_word("pic_status_check", PIC_STATUS_ADDR, data);
        sample_event(3);
        do_write_word("uart_ier_clr", UART_IER_ADDR, 32'h00);
        do_write_word("pic_mask_restore", PIC_MASK_ADDR, 32'h0);
        sample_event(4);
`else
        do_write_word("uart_irq_pic_mask_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_write_word("uart_irq_clear_initial", UART_IRQ_CLEAR_ADDR, UART_TX_IRQ_MASK);
        do_read_word("uart_irq_status_initial", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b0)
            `uvm_error("UART_IRQ",
                       $sformatf("UART IRQ_STATUS initial data=0x%08h expected bit1 clear", data))
        sample_event(0);
        do_write_word("uart_irq_pic_mask_enable", PIC_MASK_ADDR, UART_TX_IRQ_MASK);
        do_write_word("uart_irq_tx_write", UART_TX_ADDR, 32'h0000_0055);
        sample_event(1);
        do_read_word("uart_irq_status_after_tx", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b1)
            `uvm_error("UART_IRQ",
                       $sformatf("UART IRQ_STATUS after TX data=0x%08h expected bit1 set", data))
        do_read_word("uart_status_after_tx", UART_STATUS_ADDR, data);
        if (data[1:0] !== 2'b11)
            `uvm_error("UART_IRQ",
                       $sformatf("UART STATUS after TX data=0x%08h expected ready+irq", data))
        do_read_word("pic_uart_status_after_tx", PIC_STATUS_ADDR, data);
        if (data[1] !== 1'b1)
            `uvm_error("UART_IRQ",
                       $sformatf("PIC STATUS after UART TX data=0x%08h expected bit1 set", data))
        do_read_word("pic_uart_active_after_tx", PIC_ACTIVE_ADDR, data);
        if (data[1] !== 1'b1)
            `uvm_error("UART_IRQ",
                       $sformatf("PIC ACTIVE after UART TX data=0x%08h expected bit1 set", data))
        sample_event(2);
        do_write_word("uart_irq_clear_after_tx", UART_IRQ_CLEAR_ADDR, UART_TX_IRQ_MASK);
        do_read_word("uart_irq_status_after_clear", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b0)
            `uvm_error("UART_IRQ",
                       $sformatf("UART IRQ_STATUS after clear data=0x%08h expected bit1 clear", data))
        sample_event(3);
        do_read_word("pic_uart_status_after_clear", PIC_STATUS_ADDR, data);
        if (data[1] !== 1'b0)
            `uvm_error("UART_IRQ",
                       $sformatf("PIC STATUS after UART clear data=0x%08h expected bit1 clear", data))
        do_read_word("pic_uart_active_after_clear", PIC_ACTIVE_ADDR, data);
        if (data[1] !== 1'b0)
            `uvm_error("UART_IRQ",
                       $sformatf("PIC ACTIVE after UART clear data=0x%08h expected bit1 clear", data))
        sample_event(4);
        do_write_word("uart_irq_pic_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
`endif
    endtask
endclass

`endif
