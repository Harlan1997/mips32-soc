`ifndef AXI_UART_IRQ_SEQ_SV
`define AXI_UART_IRQ_SEQ_SV

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

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("UART_IRQ", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
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

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("UART_IRQ", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        data = tr.data[0];
    endtask

    task body();
        logic [31:0] data;

        do_write_word("uart_irq_pic_mask_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_write_word("uart_irq_clear_initial", UART_IRQ_CLEAR_ADDR, UART_TX_IRQ_MASK);
        do_read_word("uart_irq_status_initial", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b0) begin
            `uvm_error("UART_IRQ", $sformatf("UART IRQ_STATUS initial data=0x%08h expected bit1 clear", data))
        end
        sample_event(0);

        do_write_word("uart_irq_pic_mask_enable", PIC_MASK_ADDR, UART_TX_IRQ_MASK);
        do_write_word("uart_irq_tx_write", UART_TX_ADDR, 32'h0000_0055);
        sample_event(1);

        do_read_word("uart_irq_status_after_tx", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b1) begin
            `uvm_error("UART_IRQ", $sformatf("UART IRQ_STATUS after TX data=0x%08h expected bit1 set", data))
        end
        do_read_word("uart_status_after_tx", UART_STATUS_ADDR, data);
        if (data[1:0] !== 2'b11) begin
            `uvm_error("UART_IRQ", $sformatf("UART STATUS after TX data=0x%08h expected ready+irq", data))
        end
        do_read_word("pic_uart_status_after_tx", PIC_STATUS_ADDR, data);
        if (data[1] !== 1'b1) begin
            `uvm_error("UART_IRQ", $sformatf("PIC STATUS after UART TX data=0x%08h expected bit1 set", data))
        end
        do_read_word("pic_uart_active_after_tx", PIC_ACTIVE_ADDR, data);
        if (data[1] !== 1'b1) begin
            `uvm_error("UART_IRQ", $sformatf("PIC ACTIVE after UART TX data=0x%08h expected bit1 set", data))
        end
        sample_event(2);

        do_write_word("uart_irq_clear_after_tx", UART_IRQ_CLEAR_ADDR, UART_TX_IRQ_MASK);
        do_read_word("uart_irq_status_after_clear", UART_IRQ_STATUS_ADDR, data);
        if (data[1] !== 1'b0) begin
            `uvm_error("UART_IRQ", $sformatf("UART IRQ_STATUS after clear data=0x%08h expected bit1 clear", data))
        end
        sample_event(3);

        do_read_word("pic_uart_status_after_clear", PIC_STATUS_ADDR, data);
        if (data[1] !== 1'b0) begin
            `uvm_error("UART_IRQ", $sformatf("PIC STATUS after UART clear data=0x%08h expected bit1 clear", data))
        end
        do_read_word("pic_uart_active_after_clear", PIC_ACTIVE_ADDR, data);
        if (data[1] !== 1'b0) begin
            `uvm_error("UART_IRQ", $sformatf("PIC ACTIVE after UART clear data=0x%08h expected bit1 clear", data))
        end
        sample_event(4);

        do_write_word("uart_irq_pic_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
    endtask
endclass

`endif
