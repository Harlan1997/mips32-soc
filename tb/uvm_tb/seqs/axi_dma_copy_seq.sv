`ifndef AXI_DMA_COPY_SEQ_SV
`define AXI_DMA_COPY_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_dma_copy_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_dma_copy_seq)

    localparam logic [31:0] DMA_SRC_ADDR  = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_SRC_OFFSET;
    localparam logic [31:0] DMA_DST_ADDR  = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_DST_OFFSET;
    localparam logic [31:0] DMA_LEN_ADDR  = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_LEN_OFFSET;
    localparam logic [31:0] DMA_CTRL_ADDR = `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_CTRL_OFFSET;
    localparam logic [31:0] PIC_STATUS_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_STATUS_OFFSET;
    localparam logic [31:0] PIC_MASK_ADDR   = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_MASK_OFFSET;
    localparam logic [31:0] PIC_ACTIVE_ADDR = `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_ACTIVE_OFFSET;

    localparam logic [31:0] SRAM_SRC_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_D000;
    localparam logic [31:0] SRAM_DST_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_D100;
    localparam int unsigned DMA_WORDS = 4;
    localparam int unsigned DMA_BYTES = DMA_WORDS * 4;
    bit enable_irq_check;

    function new(string name = "axi_dma_copy_seq");
        super.new(name);
    endfunction

    task do_write(string item_name, logic [31:0] addr, logic [7:0] len, logic [31:0] payload[]);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        if (payload.size() != beats) begin
            `uvm_fatal("DMA_COPY", $sformatf("%s payload size=%0d expected=%0d",
                       item_name, payload.size(), beats))
        end

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'd1;
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
            `uvm_error("DMA_COPY", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        logic [31:0] payload[];

        payload = new[1];
        payload[0] = data;
        do_write(item_name, addr, 8'h00, payload);
    endtask

    task do_read(string item_name, logic [31:0] addr, logic [7:0] len,
                 output logic [31:0] observed[]);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'd1;
        tr.addr       = addr;
        tr.len        = len;
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

        observed = new[beats];
        foreach (tr.resp[i]) begin
            if (tr.resp[i] != `SOC_AXI_RESP_OKAY) begin
                `uvm_error("DMA_COPY", $sformatf("%s read beat=%0d addr=0x%08h resp=%0h expected OKAY",
                           item_name, i, addr + (i << 2), tr.resp[i]))
            end
            observed[i] = tr.data[i];
        end
    endtask

    task do_read_word(string item_name, logic [31:0] addr, output logic [31:0] data);
        logic [31:0] observed[];

        do_read(item_name, addr, 8'h00, observed);
        data = observed[0];
    endtask

    task poll_dma_done(output logic [31:0] ctrl);
        ctrl = 32'h0000_0000;
        for (int i = 0; i < 128; i++) begin
            do_read_word($sformatf("dma_ctrl_poll_%0d", i), DMA_CTRL_ADDR, ctrl);
            if (ctrl[2] && !ctrl[0]) begin
                return;
            end
        end

        `uvm_error("DMA_COPY", $sformatf("DMA did not complete within poll limit; last CTRL=0x%08h", ctrl))
    endtask

    task body();
        logic [31:0] expected[];
        logic [31:0] observed[];
        logic [31:0] ctrl;

        expected = new[DMA_WORDS];
        expected[0] = 32'hC001_D00D;
        expected[1] = 32'h1357_2468;
        expected[2] = 32'hA5A5_5A5A;
        expected[3] = 32'h0BAD_F00D;

        if (enable_irq_check) begin
            do_write_word("pic_dma_mask_enable", PIC_MASK_ADDR, 32'h0000_0008);
            do_read_word("pic_dma_mask_read", PIC_MASK_ADDR, ctrl);
            if (ctrl !== 32'h0000_0008) begin
                `uvm_error("DMA_COPY", $sformatf("PIC MASK data=0x%08h expected=0x00000008", ctrl))
            end
        end

        do_write("dma_src_seed_write", SRAM_SRC_BASE, DMA_WORDS - 1, expected);

        do_write_word("dma_src_addr_write", DMA_SRC_ADDR, SRAM_SRC_BASE);
        do_write_word("dma_dst_addr_write", DMA_DST_ADDR, SRAM_DST_BASE);
        do_write_word("dma_len_write", DMA_LEN_ADDR, DMA_BYTES);
        do_read_word("dma_src_addr_read", DMA_SRC_ADDR, ctrl);
        if (ctrl !== SRAM_SRC_BASE) begin
            `uvm_error("DMA_COPY", $sformatf("SRC register data=0x%08h expected=0x%08h", ctrl, SRAM_SRC_BASE))
        end
        do_read_word("dma_dst_addr_read", DMA_DST_ADDR, ctrl);
        if (ctrl !== SRAM_DST_BASE) begin
            `uvm_error("DMA_COPY", $sformatf("DST register data=0x%08h expected=0x%08h", ctrl, SRAM_DST_BASE))
        end
        do_read_word("dma_len_read", DMA_LEN_ADDR, ctrl);
        if (ctrl !== DMA_BYTES) begin
            `uvm_error("DMA_COPY", $sformatf("LENGTH register data=0x%08h expected=0x%08h", ctrl, DMA_BYTES))
        end

        do_write_word("dma_start_write", DMA_CTRL_ADDR, enable_irq_check ? 32'h0000_0003 : 32'h0000_0001);
        poll_dma_done(ctrl);

        if (enable_irq_check) begin
            do_read_word("pic_dma_status_asserted", PIC_STATUS_ADDR, ctrl);
            if (ctrl[3] !== 1'b1) begin
                `uvm_error("DMA_COPY", $sformatf("PIC STATUS bit3 data=0x%08h expected asserted", ctrl))
            end
            do_read_word("pic_dma_active_asserted", PIC_ACTIVE_ADDR, ctrl);
            if (ctrl[3] !== 1'b1) begin
                `uvm_error("DMA_COPY", $sformatf("PIC ACTIVE bit3 data=0x%08h expected asserted", ctrl))
            end
        end

        do_read("dma_dst_burst_read", SRAM_DST_BASE, DMA_WORDS - 1, observed);
        foreach (expected[i]) begin
            if (observed[i] !== expected[i]) begin
                `uvm_error("DMA_COPY", $sformatf("Copied word mismatch beat=%0d addr=0x%08h data=0x%08h expected=0x%08h",
                           i, SRAM_DST_BASE + (i << 2), observed[i], expected[i]))
            end
        end

        do_write_word("dma_done_clear", DMA_CTRL_ADDR, 32'h0000_0004);
        do_read_word("dma_ctrl_done_clear_read", DMA_CTRL_ADDR, ctrl);
        if (ctrl[2] !== 1'b0) begin
            `uvm_error("DMA_COPY", $sformatf("DONE bit did not clear; CTRL=0x%08h", ctrl))
        end

        if (enable_irq_check) begin
            do_read_word("pic_dma_status_cleared", PIC_STATUS_ADDR, ctrl);
            if (ctrl[3] !== 1'b0) begin
                `uvm_error("DMA_COPY", $sformatf("PIC STATUS bit3 data=0x%08h expected cleared", ctrl))
            end
            do_read_word("pic_dma_active_cleared", PIC_ACTIVE_ADDR, ctrl);
            if (ctrl[3] !== 1'b0) begin
                `uvm_error("DMA_COPY", $sformatf("PIC ACTIVE bit3 data=0x%08h expected cleared", ctrl))
            end
            do_write_word("pic_dma_mask_restore_zero", PIC_MASK_ADDR, 32'h0000_0000);
            do_read_word("pic_dma_mask_zero_read", PIC_MASK_ADDR, ctrl);
            if (ctrl !== 32'h0000_0000) begin
                `uvm_error("DMA_COPY", $sformatf("PIC MASK restore data=0x%08h expected=0x00000000", ctrl))
            end
        end
    endtask
endclass

`endif
