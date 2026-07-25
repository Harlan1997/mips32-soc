`ifndef AXI_UNMAPPED_ERROR_SEQ_SV
`define AXI_UNMAPPED_ERROR_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_unmapped_error_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_unmapped_error_seq)

    function new(string name = "axi_unmapped_error_seq");
        super.new(name);
    endfunction

    task body();
        axi_transaction tr;

        tr = axi_transaction::type_id::create("unmapped_write");
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'hA;
        tr.addr       = 32'hF000_1000;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.data[0]    = 32'hCAFE_BABE;
        tr.strb[0]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_DECERR) begin
            `uvm_error("UNMAPPED", $sformatf("Expected write DECERR, got 0x%0h", tr.resp[0]))
        end

        tr = axi_transaction::type_id::create("unmapped_read");
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'hB;
        tr.addr       = 32'hF000_2000;
        tr.len        = 8'h03;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[4];
        tr.strb       = new[4];
        tr.resp       = new[4];
        foreach (tr.strb[i]) begin
            tr.strb[i] = 4'hF;
            tr.resp[i] = `SOC_AXI_RESP_OKAY;
        end
        finish_item(tr);

        foreach (tr.resp[i]) begin
            if (tr.resp[i] != `SOC_AXI_RESP_DECERR) begin
                `uvm_error("UNMAPPED", $sformatf("Expected read beat %0d DECERR, got 0x%0h", i, tr.resp[i]))
            end
            if (tr.data[i] != 32'h0000_0000) begin
                `uvm_error("UNMAPPED", $sformatf("Expected read beat %0d zero data, got 0x%08h", i, tr.data[i]))
            end
        end
    endtask
endclass

`endif
