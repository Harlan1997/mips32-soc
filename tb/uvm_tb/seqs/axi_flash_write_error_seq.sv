`ifndef AXI_FLASH_WRITE_ERROR_SEQ_SV
`define AXI_FLASH_WRITE_ERROR_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_flash_write_error_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_flash_write_error_seq)

    function new(string name = "axi_flash_write_error_seq");
        super.new(name);
    endfunction

    task body();
        axi_transaction tr;

        tr = axi_transaction::type_id::create("flash_write");
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'hC;
        tr.addr       = `SOC_FLASH_BASE + 32'h0000_0100;
        tr.len        = 8'h01;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[2];
        tr.strb       = new[2];
        tr.resp       = new[1];
        tr.data[0]    = 32'h1122_3344;
        tr.data[1]    = 32'h5566_7788;
        tr.strb[0]    = 4'hF;
        tr.strb[1]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_SLVERR) begin
            `uvm_error("FLASH_WR", $sformatf("Expected flash write SLVERR, got 0x%0h", tr.resp[0]))
        end
    endtask
endclass

`endif
