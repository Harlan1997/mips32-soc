`ifndef AXI_FABRIC_CONTRACT_SEQ_SV
`define AXI_FABRIC_CONTRACT_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_fabric_contract_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_fabric_contract_seq)

    function new(string name = "axi_fabric_contract_seq");
        super.new(name);
    endfunction

    task do_read(string item_name, logic [31:0] addr, logic [7:0] len, logic [1:0] expected_resp);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = $urandom_range(0, 15);
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

        foreach (tr.resp[i]) begin
            if (tr.resp[i] != expected_resp) begin
                `uvm_error("FABRIC_CONTRACT", $sformatf("%s beat=%0d addr=0x%08h resp=%0h expected=%0h",
                           item_name, i, addr, tr.resp[i], expected_resp))
            end
        end
    endtask

    task do_write(string item_name, logic [31:0] addr, logic [7:0] len, logic [1:0] expected_resp);
        axi_transaction tr;
        int unsigned beats;

        beats = len + 1;
        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = $urandom_range(0, 15);
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[beats];
        tr.strb       = new[beats];
        tr.resp       = new[1];
        foreach (tr.data[i]) begin
            tr.data[i] = 32'hC0DE_0000 + i;
            tr.strb[i] = 4'hF;
        end
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != expected_resp) begin
            `uvm_error("FABRIC_CONTRACT", $sformatf("%s addr=0x%08h resp=%0h expected=%0h",
                       item_name, addr, tr.resp[0], expected_resp))
        end
    endtask

    task body();
        do_read("boot_sram_read",  `SOC_BOOT_BASE + 32'h0000_0000, 8'h00, `SOC_AXI_RESP_OKAY);
        do_read("alias_sram_read", `SOC_SRAM_ALIAS_BASE + 32'h0000_0020, 8'h01, `SOC_AXI_RESP_OKAY);
        do_read("apb_gpio_read",   `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                8'h00, `SOC_AXI_RESP_OKAY);
        do_write("apb_gpio_write", `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                 8'h00, `SOC_AXI_RESP_OKAY);
        do_read("flash_read",      `SOC_FLASH_BASE + 32'h0000_0100, 8'h01, `SOC_AXI_RESP_OKAY);
        do_write("flash_write",    `SOC_FLASH_BASE + 32'h0000_0200, 8'h01, `SOC_AXI_RESP_SLVERR);
        do_write("unmapped_write", 32'hF000_3000, 8'h00, `SOC_AXI_RESP_DECERR);
        do_read("unmapped_read",   32'hF000_4000, 8'h03, `SOC_AXI_RESP_DECERR);
    endtask
endclass

`endif
