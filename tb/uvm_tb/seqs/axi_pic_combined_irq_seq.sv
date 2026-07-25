`ifndef AXI_PIC_COMBINED_IRQ_SEQ_SV
`define AXI_PIC_COMBINED_IRQ_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_pic_combined_irq_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_pic_combined_irq_seq)

    localparam logic [31:0] TIMER_CTRL_ADDR = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET;
    localparam logic [31:0] TIMER_LOAD_ADDR = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR  = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;
    localparam logic [31:0] TIMER_INT_ADDR  = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET;
    localparam logic [31:0] DMA_SRC_ADDR    = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_SRC_OFFSET;
    localparam logic [31:0] DMA_DST_ADDR    = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_DST_OFFSET;
    localparam logic [31:0] DMA_LEN_ADDR    = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_LEN_OFFSET;
    localparam logic [31:0] DMA_CTRL_ADDR   = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_CTRL_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_ACTIVE_OFFSET;

    localparam logic [31:0] SRAM_SRC_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_E000;
    localparam logic [31:0] SRAM_DST_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_E100;
    localparam logic [31:0] TIMER_IRQ_MASK = 32'h0000_0004;
    localparam logic [31:0] DMA_IRQ_MASK   = 32'h0000_0008;
    localparam int unsigned DMA_WORDS = 4;
    localparam int unsigned DMA_BYTES = DMA_WORDS * 4;

    localparam int EV_MASK_ENABLE       = 0;
    localparam int EV_TIMER_ASSERT      = 1;
    localparam int EV_DMA_ASSERT        = 2;
    localparam int EV_BOTH_ASSERT       = 3;
    localparam int EV_TIMER_CLEAR       = 4;
    localparam int EV_DMA_STILL_ASSERT  = 5;
    localparam int EV_DMA_CLEAR         = 6;
    localparam int EV_ALL_CLEAR         = 7;
    localparam int EV_MASK_RESTORE      = 8;

    int unsigned pic_combined_event_sample;
    logic [3:0]  pic_active_bits_sample;

    covergroup pic_combined_irq_event_cg;
        option.per_instance = 1;

        event_cp: coverpoint pic_combined_event_sample {
            bins mask_enable      = {EV_MASK_ENABLE};
            bins timer_assert     = {EV_TIMER_ASSERT};
            bins dma_assert       = {EV_DMA_ASSERT};
            bins both_assert      = {EV_BOTH_ASSERT};
            bins timer_clear      = {EV_TIMER_CLEAR};
            bins dma_still_active = {EV_DMA_STILL_ASSERT};
            bins dma_clear        = {EV_DMA_CLEAR};
            bins all_clear        = {EV_ALL_CLEAR};
            bins mask_restore     = {EV_MASK_RESTORE};
        }
    endgroup

    covergroup pic_combined_irq_state_cg;
        option.per_instance = 1;

        active_bits_cp: coverpoint pic_active_bits_sample {
            bins none       = {4'b0000};
            bins timer_only = {4'b0100};
            bins dma_only   = {4'b1000};
            bins both       = {4'b1100};
        }
    endgroup

    function new(string name = "axi_pic_combined_irq_seq");
        super.new(name);
        pic_combined_irq_event_cg = new();
        pic_combined_irq_state_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        pic_combined_event_sample = event_id;
        pic_combined_irq_event_cg.sample();
    endfunction

    function void sample_active_bits(logic [31:0] active);
        pic_active_bits_sample = active[3:0];
        pic_combined_irq_state_cg.sample();
    endfunction

    task do_write(string item_name, logic [31:0] addr, logic [7:0] len, logic [31:0] payload[]);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        if (payload.size() != beats) begin
            `uvm_fatal("PIC_COMBINED_IRQ", $sformatf("%s payload size=%0d expected=%0d",
                       item_name, payload.size(), beats))
        end

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'd4;
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
            `uvm_error("PIC_COMBINED_IRQ", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
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
        tr.id         = 4'd4;
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
            `uvm_error("PIC_COMBINED_IRQ", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        data = tr.data[0];
    endtask

    task poll_active_bits(string item_name, logic [31:0] expected_mask,
                          logic [31:0] expected_value);
        logic [31:0] status;
        logic [31:0] active;

        for (int i = 0; i < 128; i++) begin
            do_read_word($sformatf("%s_status_%0d", item_name, i), PIC_STATUS_ADDR, status);
            do_read_word($sformatf("%s_active_%0d", item_name, i), PIC_ACTIVE_ADDR, active);
            if ((status & expected_mask) == expected_value &&
                (active & expected_mask) == expected_value) begin
                sample_active_bits(active);
                return;
            end
        end

        `uvm_error("PIC_COMBINED_IRQ",
                   $sformatf("%s did not observe expected PIC bits mask=0x%08h value=0x%08h",
                             item_name, expected_mask, expected_value))
    endtask

    task poll_dma_done(output logic [31:0] ctrl);
        ctrl = 32'h0000_0000;
        for (int i = 0; i < 128; i++) begin
            do_read_word($sformatf("pic_combined_dma_ctrl_poll_%0d", i), DMA_CTRL_ADDR, ctrl);
            if (ctrl[2] && !ctrl[0]) begin
                return;
            end
        end

        `uvm_error("PIC_COMBINED_IRQ",
                   $sformatf("DMA did not complete within poll limit; last CTRL=0x%08h", ctrl))
    endtask

    task body();
        logic [31:0] seed_data[];
        logic [31:0] data;

        seed_data = new[DMA_WORDS];
        seed_data[0] = 32'hC0DE_1001;
        seed_data[1] = 32'hC0DE_1002;
        seed_data[2] = 32'hC0DE_1003;
        seed_data[3] = 32'hC0DE_1004;

        do_write_word("pic_combined_mask_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_write_word("timer_combined_ctrl_disable", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("timer_combined_clear_before_start", TIMER_INT_ADDR, 32'h0000_0001);
        do_write_word("dma_combined_clear_before_start", DMA_CTRL_ADDR, 32'h0000_0004);
        poll_active_bits("pic_combined_initial_clear", TIMER_IRQ_MASK | DMA_IRQ_MASK, 32'h0000_0000);

        do_write("pic_combined_dma_src_seed", SRAM_SRC_BASE, DMA_WORDS - 1, seed_data);
        do_write_word("dma_combined_src_write", DMA_SRC_ADDR, SRAM_SRC_BASE);
        do_write_word("dma_combined_dst_write", DMA_DST_ADDR, SRAM_DST_BASE);
        do_write_word("dma_combined_len_write", DMA_LEN_ADDR, DMA_BYTES);
        do_write_word("timer_combined_load_write", TIMER_LOAD_ADDR, 32'h0000_0003);
        do_write_word("timer_combined_val_write", TIMER_VAL_ADDR, 32'h0000_0003);

        do_write_word("pic_combined_mask_enable", PIC_MASK_ADDR, TIMER_IRQ_MASK | DMA_IRQ_MASK);
        do_read_word("pic_combined_mask_read", PIC_MASK_ADDR, data);
        if (data !== (TIMER_IRQ_MASK | DMA_IRQ_MASK)) begin
            `uvm_error("PIC_COMBINED_IRQ", $sformatf("PIC MASK data=0x%08h expected=0x0000000c", data))
        end
        sample_event(EV_MASK_ENABLE);

        do_write_word("timer_combined_ctrl_enable", TIMER_CTRL_ADDR, 32'h0000_0003);
        poll_active_bits("pic_combined_timer_assert", TIMER_IRQ_MASK, TIMER_IRQ_MASK);
        sample_event(EV_TIMER_ASSERT);

        do_write_word("dma_combined_start_irq", DMA_CTRL_ADDR, 32'h0000_0003);
        poll_dma_done(data);
        poll_active_bits("pic_combined_dma_assert", DMA_IRQ_MASK, DMA_IRQ_MASK);
        sample_event(EV_DMA_ASSERT);
        poll_active_bits("pic_combined_both_assert", TIMER_IRQ_MASK | DMA_IRQ_MASK,
                         TIMER_IRQ_MASK | DMA_IRQ_MASK);
        sample_event(EV_BOTH_ASSERT);

        do_write_word("timer_combined_ctrl_disable_after_assert", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("timer_combined_clear_after_assert", TIMER_INT_ADDR, 32'h0000_0001);
        sample_event(EV_TIMER_CLEAR);
        poll_active_bits("pic_combined_dma_remains", TIMER_IRQ_MASK | DMA_IRQ_MASK, DMA_IRQ_MASK);
        sample_event(EV_DMA_STILL_ASSERT);

        do_write_word("dma_combined_done_clear", DMA_CTRL_ADDR, 32'h0000_0004);
        sample_event(EV_DMA_CLEAR);
        poll_active_bits("pic_combined_all_clear", TIMER_IRQ_MASK | DMA_IRQ_MASK, 32'h0000_0000);
        sample_event(EV_ALL_CLEAR);

        do_write_word("pic_combined_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
        do_read_word("pic_combined_mask_zero_read", PIC_MASK_ADDR, data);
        if (data !== 32'h0000_0000) begin
            `uvm_error("PIC_COMBINED_IRQ", $sformatf("PIC MASK restore data=0x%08h expected=0x00000000", data))
        end
        sample_event(EV_MASK_RESTORE);
    endtask
endclass

`endif
