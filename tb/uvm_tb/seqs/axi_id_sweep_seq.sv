`ifndef AXI_ID_SWEEP_SEQ_SV
`define AXI_ID_SWEEP_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_id_sweep_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_id_sweep_seq)

    localparam logic [31:0] SRAM_ID_SCRATCH_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_C100;

    function new(string name = "axi_id_sweep_seq");
        super.new(name);
    endfunction

    task do_write(string item_name,
                  logic [31:0] addr,
                  logic [3:0] id,
                  logic [7:0] len,
                  logic [1:0] expected_resp,
                  logic [31:0] base_data);
        axi_transaction tr;
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
            tr.data[i] = base_data + i;
            tr.strb[i] = 4'hF;
        end
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != expected_resp) begin
            `uvm_error("AXI_ID_SWEEP", $sformatf("%s id=%0d addr=0x%08h resp=%0h expected=%0h",
                       item_name, id, addr, tr.resp[0], expected_resp))
        end
    endtask

    task do_read(string item_name,
                 logic [31:0] addr,
                 logic [3:0] id,
                 logic [7:0] len,
                 logic [1:0] expected_resp);
        axi_transaction tr;
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
            tr.resp[i] = `SOC_AXI_RESP_OKAY;
        end
        finish_item(tr);

        foreach (tr.resp[i]) begin
            if (tr.resp[i] != expected_resp) begin
                `uvm_error("AXI_ID_SWEEP", $sformatf("%s id=%0d beat=%0d addr=0x%08h resp=%0h expected=%0h",
                           item_name, id, i, addr + (i << 2), tr.resp[i], expected_resp))
            end
        end
    endtask

    task body();
        do_write("id0_sram_write", SRAM_ID_SCRATCH_BASE + 32'h00, 4'h0, 8'h00,
                 `SOC_AXI_RESP_OKAY, 32'h1000_0000);
        do_read("id0_sram_read", SRAM_ID_SCRATCH_BASE + 32'h00, 4'h0, 8'h00,
                `SOC_AXI_RESP_OKAY);

        do_write("id2_apb_gpio_write", `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                 4'h2, 8'h00, `SOC_AXI_RESP_OKAY, 32'h2000_0000);
        do_read("id2_apb_gpio_read", `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                4'h2, 8'h00, `SOC_AXI_RESP_OKAY);

        do_read("id5_flash_read", `SOC_FLASH_BASE + 32'h0000_0200, 4'h5, 8'h03,
                `SOC_AXI_RESP_OKAY);
        do_write("id5_flash_write_error", `SOC_FLASH_BASE + 32'h0000_0300, 4'h5, 8'h00,
                 `SOC_AXI_RESP_SLVERR, 32'h5000_0000);

        do_write("id12_unmapped_write", 32'hF100_0000, 4'hC, 8'h00,
                 `SOC_AXI_RESP_DECERR, 32'hC000_0000);
        do_read("id12_unmapped_read", 32'hF100_0100, 4'hC, 8'h01,
                `SOC_AXI_RESP_DECERR);
    endtask
endclass

`endif
