`ifndef AXI_SRAM_DATA_INTEGRITY_SEQ_SV
`define AXI_SRAM_DATA_INTEGRITY_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_sram_data_integrity_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_sram_data_integrity_seq)

    localparam logic [31:0] SRAM_SCRATCH_BASE = `SOC_SRAM_ALIAS_BASE + 32'h0000_C000;
    localparam logic [31:0] BOOT_SCRATCH_BASE = `SOC_BOOT_BASE + 32'h0000_D000;

    function new(string name = "axi_sram_data_integrity_seq");
        super.new(name);
    endfunction

    task do_write(string item_name, logic [31:0] addr, logic [7:0] len, logic [31:0] base_data);
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
            tr.data[i] = base_data ^ (32'h0101_0101 * i);
            tr.strb[i] = 4'hF;
        end
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("SRAM_DATA", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_masked_write(string item_name, logic [31:0] addr, logic [31:0] data, logic [3:0] strb);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = $urandom_range(0, 15);
        tr.addr       = addr;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.data[0]    = data;
        tr.strb[0]    = strb;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("SRAM_DATA", $sformatf("%s masked write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_read_check(string item_name, logic [31:0] addr, logic [7:0] len, logic [31:0] expected_data[]);
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
            if (tr.resp[i] != `SOC_AXI_RESP_OKAY) begin
                `uvm_error("SRAM_DATA", $sformatf("%s read beat=%0d addr=0x%08h resp=%0h expected OKAY",
                           item_name, i, addr + (i << 2), tr.resp[i]))
            end
            if (tr.data[i] != expected_data[i]) begin
                `uvm_error("SRAM_DATA", $sformatf("%s read beat=%0d addr=0x%08h data=0x%08h expected=0x%08h",
                           item_name, i, addr + (i << 2), tr.data[i], expected_data[i]))
            end
        end
    endtask

    task body();
        logic [31:0] expected_burst[];
        logic [31:0] expected_masked[];
        logic [31:0] expected_long[];
        logic [31:0] expected_boot[];

        expected_burst = new[4];
        foreach (expected_burst[i]) begin
            expected_burst[i] = 32'h1357_9BDF ^ (32'h0101_0101 * i);
        end

        do_write("sram_alias_burst_write", SRAM_SCRATCH_BASE, 8'h03, 32'h1357_9BDF);
        do_read_check("sram_alias_burst_read", SRAM_SCRATCH_BASE, 8'h03, expected_burst);

        expected_masked = new[1];
        expected_masked[0] = (expected_burst[1] & 32'hFF00_00FF) | (32'hA1B2_C3D4 & 32'h00FF_FF00);

        do_masked_write("sram_alias_masked_write", SRAM_SCRATCH_BASE + 32'h4, 32'hA1B2_C3D4, 4'b0110);
        do_read_check("sram_alias_masked_read", SRAM_SCRATCH_BASE + 32'h4, 8'h00, expected_masked);

        expected_long = new[9];
        foreach (expected_long[i]) begin
            expected_long[i] = 32'h2468_ACE0 ^ (32'h0101_0101 * i);
        end

        do_write("sram_alias_long_burst_write", SRAM_SCRATCH_BASE + 32'h100, 8'h08, 32'h2468_ACE0);
        do_read_check("sram_alias_long_burst_read", SRAM_SCRATCH_BASE + 32'h100, 8'h08, expected_long);

        expected_boot = new[2];
        foreach (expected_boot[i]) begin
            expected_boot[i] = 32'hB007_0000 ^ (32'h0101_0101 * i);
        end

        do_write("boot_sram_write", BOOT_SCRATCH_BASE, 8'h01, 32'hB007_0000);
        do_read_check("boot_sram_readback", BOOT_SCRATCH_BASE, 8'h01, expected_boot);
    endtask
endclass

`endif
