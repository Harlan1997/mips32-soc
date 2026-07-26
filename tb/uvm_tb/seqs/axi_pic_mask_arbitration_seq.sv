`ifndef AXI_PIC_MASK_ARBITRATION_SEQ_SV
`define AXI_PIC_MASK_ARBITRATION_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_pic_mask_arbitration_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_pic_mask_arbitration_seq)

    localparam logic [31:0] UART_TX_ADDR         = `SOC_APB_BASE + `SOC_APB_UART_OFFSET  + `SOC_UART_TX_OFFSET;
    localparam logic [31:0] UART_IRQ_CLEAR_ADDR  = `SOC_APB_BASE + `SOC_APB_UART_OFFSET  + `SOC_UART_IRQ_CLEAR_OFFSET;
    localparam logic [31:0] TIMER_CTRL_ADDR      = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET;
    localparam logic [31:0] TIMER_LOAD_ADDR      = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR       = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;
    localparam logic [31:0] TIMER_INT_ADDR       = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET;
    localparam logic [31:0] DMA_SRC_ADDR         = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_SRC_OFFSET;
    localparam logic [31:0] DMA_DST_ADDR         = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_DST_OFFSET;
    localparam logic [31:0] DMA_LEN_ADDR         = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_LEN_OFFSET;
    localparam logic [31:0] DMA_CTRL_ADDR        = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_CTRL_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR      = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR        = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR      = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_ACTIVE_OFFSET;

    localparam logic [31:0] SRAM_SRC_BASE        = `SOC_SRAM_ALIAS_BASE + 32'h0000_F000;
    localparam logic [31:0] SRAM_DST_BASE        = `SOC_SRAM_ALIAS_BASE + 32'h0000_F100;
    localparam logic [31:0] UART_IRQ_MASK        = 32'h0000_0002;
    localparam logic [31:0] TIMER_IRQ_MASK       = 32'h0000_0004;
    localparam logic [31:0] DMA_IRQ_MASK         = 32'h0000_0008;
    localparam logic [31:0] TEST_IRQ_MASK        = UART_IRQ_MASK | TIMER_IRQ_MASK | DMA_IRQ_MASK;

    localparam int EV_PENDING_ALL    = 0;
    localparam int EV_MASK_NONE      = 1;
    localparam int EV_MASK_UART      = 2;
    localparam int EV_MASK_TIMER     = 3;
    localparam int EV_MASK_DMA       = 4;
    localparam int EV_MASK_UART_DMA  = 5;
    localparam int EV_MASK_ALL       = 6;
    localparam int EV_MASK_TIMER_DMA = 7;
    localparam int EV_RESTORE        = 8;

    int unsigned pic_mask_event_sample;
    logic [3:0]  pic_active_sample;

    covergroup pic_mask_arbitration_event_cg;
        option.per_instance = 1;

        event_cp: coverpoint pic_mask_event_sample {
            bins pending_all   = {EV_PENDING_ALL};
            bins mask_none     = {EV_MASK_NONE};
            bins mask_uart     = {EV_MASK_UART};
            bins mask_timer    = {EV_MASK_TIMER};
            bins mask_dma      = {EV_MASK_DMA};
            bins mask_uart_dma = {EV_MASK_UART_DMA};
            bins mask_all      = {EV_MASK_ALL};
            bins mask_timer_dma = {EV_MASK_TIMER_DMA};
            bins restore        = {EV_RESTORE};
        }
    endgroup

    covergroup pic_mask_arbitration_active_cg;
        option.per_instance = 1;

        active_cp: coverpoint pic_active_sample {
            bins none      = {4'b0000};
            bins uart_only = {4'b0010};
            bins timer_only = {4'b0100};
            bins dma_only  = {4'b1000};
            bins uart_dma  = {4'b1010};
            bins all_test  = {4'b1110};
            bins timer_dma = {4'b1100};
        }
    endgroup

    function new(string name = "axi_pic_mask_arbitration_seq");
        super.new(name);
        pic_mask_arbitration_event_cg = new();
        pic_mask_arbitration_active_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        pic_mask_event_sample = event_id;
        pic_mask_arbitration_event_cg.sample();
    endfunction

    function void sample_active(logic [31:0] active);
        pic_active_sample = active[3:0];
        pic_mask_arbitration_active_cg.sample();
    endfunction

    task do_write(string item_name, logic [31:0] addr, logic [7:0] len, logic [31:0] payload[]);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        if (payload.size() != beats) begin
            `uvm_fatal("PIC_MASK_ARB", $sformatf("%s payload size=%0d expected=%0d",
                       item_name, payload.size(), beats))
        end

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'h7;
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[beats];
        tr.strb       = new[beats];
        tr.resp       = new[1];
        foreach (tr.data[i]) begin
            tr.data[i] = payload[i];
            tr.strb[i] = 4'hF;
        end
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("PIC_MASK_ARB", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        logic [31:0] payload[];

        payload = new[1];
        payload[0] = data;
        do_write(item_name, addr, 8'h00, payload);
    endtask

    task do_read_word(string item_name, logic [31:0] addr, output logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'h7;
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
            `uvm_error("PIC_MASK_ARB", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        data = tr.data[0];
    endtask

    task poll_status_bits(string item_name, logic [31:0] expected);
        logic [31:0] status;

        for (int i = 0; i < 128; i++) begin
            do_read_word($sformatf("%s_status_%0d", item_name, i), PIC_STATUS_ADDR, status);
            if ((status & TEST_IRQ_MASK) == expected) begin
                return;
            end
        end

        `uvm_error("PIC_MASK_ARB", $sformatf("%s expected status=0x%08h", item_name, expected))
    endtask

    task expect_active(string item_name, logic [31:0] mask, logic [31:0] expected_active);
        logic [31:0] status;
        logic [31:0] active;

        do_write_word({item_name, "_mask"}, PIC_MASK_ADDR, mask);
        do_read_word({item_name, "_status"}, PIC_STATUS_ADDR, status);
        do_read_word({item_name, "_active"}, PIC_ACTIVE_ADDR, active);

        if ((active & TEST_IRQ_MASK) != expected_active) begin
            `uvm_error("PIC_MASK_ARB", $sformatf("%s active=0x%08h expected=0x%08h mask=0x%08h status=0x%08h",
                       item_name, active & TEST_IRQ_MASK, expected_active, mask, status & TEST_IRQ_MASK))
        end

        sample_active(active);
    endtask

    task seed_dma_source();
        logic [31:0] seed_data[];

        seed_data = new[1];
        seed_data[0] = 32'hCAFE_3001;
        do_write("pic_mask_dma_src_seed", SRAM_SRC_BASE, 8'h00, seed_data);
    endtask

    task start_dma_irq();
        logic [31:0] ctrl;

        seed_dma_source();
        do_write_word("pic_mask_dma_src", DMA_SRC_ADDR, SRAM_SRC_BASE);
        do_write_word("pic_mask_dma_dst", DMA_DST_ADDR, SRAM_DST_BASE);
        do_write_word("pic_mask_dma_len", DMA_LEN_ADDR, 32'd4);
        do_write_word("pic_mask_dma_start", DMA_CTRL_ADDR, 32'h0000_0003);

        for (int i = 0; i < 128; i++) begin
            do_read_word($sformatf("pic_mask_dma_ctrl_poll_%0d", i), DMA_CTRL_ADDR, ctrl);
            if (ctrl[2] && !ctrl[0]) begin
                return;
            end
        end

        `uvm_error("PIC_MASK_ARB", $sformatf("DMA did not complete; last CTRL=0x%08h", ctrl))
    endtask

    task body();
        do_write_word("pic_mask_init_zero", PIC_MASK_ADDR, 32'h0000_0000);
`ifdef SOC_USE_UART_16550
        // v2 UART fires only transient TX-empty IRQ (auto-clears on IIR
        // read) — no stable-level IRQ for arbitration to check. Use VIC's
        // INTR_SOFT register to force UART bit (source 1) permanently
        // asserted; this is stable and W1C-controlled. Semantically
        // identical to v1 apb_uart's "always pending after write" stub.
        // VIC INTR_SOFT is at PIC_BASE + 0x1C.
        do_write_word("pic_mask_soft_uart_bit",
                      `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + 32'h1C,
                      UART_IRQ_MASK);
`else
        do_write_word("pic_mask_uart_clear_initial", UART_IRQ_CLEAR_ADDR, UART_IRQ_MASK);
`endif
        do_write_word("pic_mask_timer_disable", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("pic_mask_timer_clear_initial", TIMER_INT_ADDR, 32'h0000_0001);
        do_write_word("pic_mask_dma_clear_initial", DMA_CTRL_ADDR, 32'h0000_0004);
`ifndef SOC_USE_UART_16550
        poll_status_bits("pic_mask_initial_clear", 32'h0000_0000);
`endif

        do_write_word("pic_mask_uart_tx_pending", UART_TX_ADDR, 32'h0000_0050);
        do_write_word("pic_mask_timer_load", TIMER_LOAD_ADDR, 32'h0000_0003);
        do_write_word("pic_mask_timer_val", TIMER_VAL_ADDR, 32'h0000_0003);
        do_write_word("pic_mask_timer_enable", TIMER_CTRL_ADDR, 32'h0000_0003);
        poll_status_bits("pic_mask_uart_timer_pending", UART_IRQ_MASK | TIMER_IRQ_MASK);
        start_dma_irq();
        poll_status_bits("pic_mask_all_pending", TEST_IRQ_MASK);
        sample_event(EV_PENDING_ALL);

        expect_active("pic_mask_none", 32'h0000_0000, 32'h0000_0000);
        sample_event(EV_MASK_NONE);
        expect_active("pic_mask_uart", UART_IRQ_MASK, UART_IRQ_MASK);
        sample_event(EV_MASK_UART);
        expect_active("pic_mask_timer", TIMER_IRQ_MASK, TIMER_IRQ_MASK);
        sample_event(EV_MASK_TIMER);
        expect_active("pic_mask_dma", DMA_IRQ_MASK, DMA_IRQ_MASK);
        sample_event(EV_MASK_DMA);
        expect_active("pic_mask_uart_dma", UART_IRQ_MASK | DMA_IRQ_MASK, UART_IRQ_MASK | DMA_IRQ_MASK);
        sample_event(EV_MASK_UART_DMA);
        expect_active("pic_mask_all", TEST_IRQ_MASK, TEST_IRQ_MASK);
        sample_event(EV_MASK_ALL);

        expect_active("pic_mask_timer_dma", TIMER_IRQ_MASK | DMA_IRQ_MASK, TIMER_IRQ_MASK | DMA_IRQ_MASK);
        sample_event(EV_MASK_TIMER_DMA);

        do_write_word("pic_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
        sample_event(EV_RESTORE);
`ifdef SOC_USE_UART_16550
        // Clear the software-triggered UART bit (VIC INTR_SOFT_CLR @ 0x20).
        do_write_word("pic_mask_soft_uart_clear",
                      `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + 32'h20,
                      UART_IRQ_MASK);
`else
        do_write_word("pic_mask_uart_clear_restore", UART_IRQ_CLEAR_ADDR, UART_IRQ_MASK);
`endif
        do_write_word("pic_mask_timer_disable_restore", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("pic_mask_timer_clear_restore", TIMER_INT_ADDR, 32'h0000_0001);
        do_write_word("pic_mask_dma_clear_restore", DMA_CTRL_ADDR, 32'h0000_0004);
    endtask
endclass

`endif
