`ifndef AXI_OVERLAP_PROBE_SEQ_SV
`define AXI_OVERLAP_PROBE_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_overlap_probe_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_overlap_probe_seq)

    localparam logic [31:0] OVERLAP_SRAM_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_C200;

    function new(string name = "axi_overlap_probe_seq");
        super.new(name);
    endfunction

    task submit_write(output axi_transaction tr,
                      input string item_name,
                      input logic [3:0] id,
                      input logic [31:0] addr,
                      input logic [7:0] len,
                      input logic [31:0] data_seed);
        int unsigned beats;

        beats = len + 1;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = id;
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[beats];
        tr.strb       = new[beats];
        tr.resp       = new[1];
        foreach (tr.data[i]) begin
            tr.data[i] = data_seed + i;
            tr.strb[i] = 4'hF;
        end
        tr.resp[0] = 2'bxx;
        finish_item(tr);
    endtask

    task submit_read(output axi_transaction tr,
                     input string item_name,
                     input logic [3:0] id,
                     input logic [31:0] addr,
                     input logic [7:0] len);
        int unsigned beats;

        beats = len + 1;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = id;
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[beats];
        tr.strb       = new[beats];
        tr.resp       = new[beats];
        foreach (tr.strb[i]) begin
            tr.strb[i] = 4'hF;
            tr.resp[i] = 2'bxx;
        end
        finish_item(tr);
    endtask

    task wait_write_done(axi_transaction tr, logic [1:0] expected_resp);
        int unsigned cycles;

        cycles = 0;
        while ($isunknown(tr.resp[0]) && cycles < 5000) begin
            #1000;
            cycles++;
        end
        if ($isunknown(tr.resp[0])) begin
            `uvm_error("OVERLAP_PROBE", $sformatf("Write id=%0d addr=0x%08h did not complete", tr.id, tr.addr))
        end else if (tr.resp[0] != expected_resp) begin
            `uvm_error("OVERLAP_PROBE", $sformatf("Write id=%0d addr=0x%08h resp=%0h expected=%0h",
                       tr.id, tr.addr, tr.resp[0], expected_resp))
        end
    endtask

    task wait_read_done(axi_transaction tr, logic [1:0] expected_resp);
        int unsigned cycles;
        bit complete;

        cycles = 0;
        complete = 1'b0;
        while (!complete && cycles < 5000) begin
            complete = 1'b1;
            foreach (tr.resp[i]) begin
                if ($isunknown(tr.resp[i])) begin
                    complete = 1'b0;
                end
            end
            if (!complete) begin
                #1000;
                cycles++;
            end
        end

        if (!complete) begin
            `uvm_error("OVERLAP_PROBE", $sformatf("Read id=%0d addr=0x%08h did not complete", tr.id, tr.addr))
        end

        foreach (tr.resp[i]) begin
            if (!$isunknown(tr.resp[i]) && tr.resp[i] != expected_resp) begin
                `uvm_error("OVERLAP_PROBE", $sformatf("Read id=%0d addr=0x%08h beat=%0d resp=%0h expected=%0h",
                           tr.id, tr.addr + (i << 2), i, tr.resp[i], expected_resp))
            end
        end
    endtask

    task body();
        axi_transaction w_sram;
        axi_transaction w_decerr;
        axi_transaction w_flash;
        axi_transaction r_sram;
        axi_transaction r_flash;
        axi_transaction r_decerr;

        submit_write(w_sram, "overlap_sram_write", 4'h1, OVERLAP_SRAM_BASE,
                     8'h00, 32'h1111_0000);
        submit_write(w_decerr, "overlap_unmapped_write", 4'h2, 32'hF200_0000,
                     8'h00, 32'h2222_0000);
        submit_write(w_flash, "overlap_flash_write", 4'h3, `SOC_FLASH_BASE + 32'h0000_0400,
                     8'h00, 32'h3333_0000);
        submit_read(r_sram, "overlap_sram_read", 4'h4, OVERLAP_SRAM_BASE, 8'h00);
        submit_read(r_flash, "overlap_flash_read", 4'h5, `SOC_FLASH_BASE + 32'h0000_0500, 8'h03);
        submit_read(r_decerr, "overlap_unmapped_read", 4'h6, 32'hF200_0100, 8'h01);

        wait_write_done(w_sram, `SOC_AXI_RESP_OKAY);
        wait_write_done(w_decerr, `SOC_AXI_RESP_DECERR);
        wait_write_done(w_flash, `SOC_AXI_RESP_SLVERR);
        wait_read_done(r_sram, `SOC_AXI_RESP_OKAY);
        wait_read_done(r_flash, `SOC_AXI_RESP_OKAY);
        wait_read_done(r_decerr, `SOC_AXI_RESP_DECERR);
    endtask
endclass

`endif
