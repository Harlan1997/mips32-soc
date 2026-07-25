`ifndef AXI_FLASH_IMAGE_SEQ_SV
`define AXI_FLASH_IMAGE_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_flash_image_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_flash_image_seq)

    int unsigned flash_image_event_sample;

    covergroup flash_image_cg;
        option.per_instance = 1;
        event_cp: coverpoint flash_image_event_sample {
            bins single_word_read = {0};
            bins burst_read       = {1};
        }
    endgroup

    function new(string name = "axi_flash_image_seq");
        super.new(name);
        flash_image_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        flash_image_event_sample = event_id;
        flash_image_cg.sample();
    endfunction

    task do_flash_read(string item_name, logic [31:0] addr,
                       logic [31:0] expected[]);
        axi_transaction tr;
        int unsigned beats;

        beats = expected.size();
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'h8;
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
                `uvm_error("FLASH_IMG", $sformatf("%s beat=%0d resp=%0h expected OKAY",
                           item_name, i, tr.resp[i]))
            end
            if (tr.data[i] !== expected[i]) begin
                `uvm_error("FLASH_IMG", $sformatf("%s beat=%0d addr=0x%08h data=0x%08h expected=0x%08h",
                           item_name, i, addr + (i << 2), tr.data[i], expected[i]))
            end
        end
    endtask

    task body();
        logic [31:0] expected[];

        if (!$test$plusargs("FLASH_IMAGE")) begin
            `uvm_error("FLASH_IMG", "soc_flash_image_test requires +FLASH_IMAGE=<hex file>")
            return;
        end

        expected = new[1];
        expected[0] = 32'h1122_3344;
        do_flash_read("flash_image_single_word", `SOC_FLASH_BASE, expected);
        sample_event(0);

        expected = new[3];
        expected[0] = 32'h1122_3344;
        expected[1] = 32'h5566_7788;
        expected[2] = 32'h99AA_BBCC;
        do_flash_read("flash_image_three_word_burst", `SOC_FLASH_BASE, expected);
        sample_event(1);
    endtask
endclass

`endif
