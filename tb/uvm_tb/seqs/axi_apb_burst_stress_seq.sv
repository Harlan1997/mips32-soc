`ifndef AXI_APB_BURST_STRESS_SEQ_SV
`define AXI_APB_BURST_STRESS_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_apb_burst_stress_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_apb_burst_stress_seq)

    localparam logic [31:0] UART_TX_ADDR      = `SOC_APB_BASE + `SOC_APB_UART_OFFSET  + `SOC_UART_TX_OFFSET;
    localparam logic [31:0] TIMER_CTRL_ADDR   = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET;
    localparam logic [31:0] TIMER_LOAD_ADDR   = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR    = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;
    localparam logic [31:0] TIMER_INT_ADDR    = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET;
    localparam logic [31:0] GPIO_DATA_ADDR    = `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET  + `SOC_GPIO_DATA_OFFSET;
    localparam logic [31:0] GPIO_DIR_ADDR     = `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET  + `SOC_GPIO_DIR_OFFSET;
    localparam logic [31:0] DMA_SRC_ADDR      = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_SRC_OFFSET;
    localparam logic [31:0] DMA_DST_ADDR      = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_DST_OFFSET;
    localparam logic [31:0] DMA_LEN_ADDR      = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_LEN_OFFSET;
    localparam logic [31:0] DMA_CTRL_ADDR     = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET   + `SOC_DMA_CTRL_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR     = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET   + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] APB_UNUSED_ADDR   = `SOC_APB_BASE + 32'h0000_5000;

    localparam int WINDOW_UART   = 0;
    localparam int WINDOW_TIMER  = 1;
    localparam int WINDOW_GPIO   = 2;
    localparam int WINDOW_DMA    = 3;
    localparam int WINDOW_PIC    = 4;
    localparam int WINDOW_UNUSED = 5;

    int unsigned apb_window_sample;
    int unsigned apb_beats_sample;

    covergroup apb_burst_stress_cg;
        option.per_instance = 1;

        window_cp: coverpoint apb_window_sample {
            bins uart   = {WINDOW_UART};
            bins timer  = {WINDOW_TIMER};
            bins gpio   = {WINDOW_GPIO};
            bins dma    = {WINDOW_DMA};
            bins pic    = {WINDOW_PIC};
            bins unused = {WINDOW_UNUSED};
        }

        beats_cp: coverpoint apb_beats_sample {
            bins two   = {2};
            bins three = {3};
            bins four  = {4};
            bins five  = {5};
        }
    endgroup

    function new(string name = "axi_apb_burst_stress_seq");
        super.new(name);
        apb_burst_stress_cg = new();
    endfunction

    function void sample_burst(int unsigned window_id, int unsigned beats);
        apb_window_sample = window_id;
        apb_beats_sample = beats;
        apb_burst_stress_cg.sample();
    endfunction

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'd5;
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
            `uvm_error("APB_BURST", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_read_burst(string item_name, logic [31:0] addr, int unsigned window_id,
                       logic [31:0] expected[]);
        axi_transaction tr;
        int unsigned beats;

        beats = expected.size();
        if (beats == 0 || beats > 256) begin
            `uvm_fatal("APB_BURST", $sformatf("%s invalid beat count=%0d", item_name, beats))
        end

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'd5;
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
                `uvm_error("APB_BURST", $sformatf("%s beat=%0d addr=0x%08h resp=%0h expected OKAY",
                           item_name, i, addr + (i << 2), tr.resp[i]))
            end
            if (tr.data[i] !== expected[i]) begin
                `uvm_error("APB_BURST", $sformatf("%s beat=%0d addr=0x%08h data=0x%08h expected=0x%08h",
                           item_name, i, addr + (i << 2), tr.data[i], expected[i]))
            end
        end

        sample_burst(window_id, beats);
    endtask

    task body();
        logic [31:0] expected[];

        do_write_word("apb_burst_timer_disable", TIMER_CTRL_ADDR, 32'h0000_0000);
        do_write_word("apb_burst_timer_clear", TIMER_INT_ADDR, 32'h0000_0001);
        do_write_word("apb_burst_timer_load", TIMER_LOAD_ADDR, 32'h0000_0024);
        do_write_word("apb_burst_timer_val", TIMER_VAL_ADDR, 32'h0000_0018);

        do_write_word("apb_burst_gpio_dir", GPIO_DIR_ADDR, 32'hFFFF_FFFF);
        do_write_word("apb_burst_gpio_data", GPIO_DATA_ADDR, 32'h1357_2468);

        do_write_word("apb_burst_dma_clear", DMA_CTRL_ADDR, 32'h0000_0004);
        do_write_word("apb_burst_dma_src", DMA_SRC_ADDR, `SOC_SRAM_ALIAS_BASE + 32'h0000_F000);
        do_write_word("apb_burst_dma_dst", DMA_DST_ADDR, `SOC_SRAM_ALIAS_BASE + 32'h0000_F100);
        do_write_word("apb_burst_dma_len", DMA_LEN_ADDR, 32'h0000_0010);

        do_write_word("apb_burst_pic_mask_zero", PIC_MASK_ADDR, 32'h0000_0000);

        expected = new[2];
        expected[0] = 32'h0000_0000;
`ifdef SOC_USE_UART_16550
        // v2 16550: 0x04 is IER (reset = 0), not STATUS/ready-bit.
        expected[1] = 32'h0000_0000;
`else
        expected[1] = 32'h0000_0001;
`endif
        do_read_burst("apb_uart_tx_status_burst", UART_TX_ADDR, WINDOW_UART, expected);

        expected = new[4];
        expected[0] = 32'h0000_0000;
        expected[1] = 32'h0000_0024;
        expected[2] = 32'h0000_0018;
        expected[3] = 32'h0000_0000;
        do_read_burst("apb_timer_ctrl_load_val_int_burst", TIMER_CTRL_ADDR, WINDOW_TIMER, expected);

        expected = new[2];
        expected[0] = 32'h1357_2468;
        expected[1] = 32'hFFFF_FFFF;
        do_read_burst("apb_gpio_data_dir_burst", GPIO_DATA_ADDR, WINDOW_GPIO, expected);

        expected = new[4];
        expected[0] = `SOC_SRAM_ALIAS_BASE + 32'h0000_F000;
        expected[1] = `SOC_SRAM_ALIAS_BASE + 32'h0000_F100;
        expected[2] = 32'h0000_0010;
        expected[3] = 32'h0000_0000;
        do_read_burst("apb_dma_src_dst_len_ctrl_burst", DMA_SRC_ADDR, WINDOW_DMA, expected);

        expected = new[3];
        expected[0] = 32'h0000_0000;
        expected[1] = 32'h0000_0000;
        expected[2] = 32'h0000_0000;
        do_read_burst("apb_pic_status_mask_active_burst", PIC_STATUS_ADDR, WINDOW_PIC, expected);

        expected = new[5];
        foreach (expected[i]) begin
            expected[i] = 32'h0000_0000;
        end
        do_read_burst("apb_unused_slot_zero_burst", APB_UNUSED_ADDR, WINDOW_UNUSED, expected);
    endtask
endclass

`endif
