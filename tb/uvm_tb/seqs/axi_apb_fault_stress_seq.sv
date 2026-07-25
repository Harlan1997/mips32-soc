`ifndef AXI_APB_FAULT_STRESS_SEQ_SV
`define AXI_APB_FAULT_STRESS_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_apb_fault_stress_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_apb_fault_stress_seq)

    localparam logic [31:0] APB_FAULT_ADDR = `SOC_APB_BASE + `SOC_APB_FAULT_OFFSET;
    localparam logic [31:0] TIMER_VAL_ADDR = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET;

    int unsigned apb_fault_event_sample;

    covergroup apb_fault_stress_cg;
        option.per_instance = 1;
        event_cp: coverpoint apb_fault_event_sample {
            bins wait_okay_read   = {0};
            bins pslverr_read     = {1};
            bins pslverr_write    = {2};
            bins pslverr_read_burst = {3};
        }
    endgroup

    function new(string name = "axi_apb_fault_stress_seq");
        super.new(name);
        apb_fault_stress_cg = new();
    endfunction

    function void sample_event(int unsigned event_id);
        apb_fault_event_sample = event_id;
        apb_fault_stress_cg.sample();
    endfunction

    task do_read(string item_name, logic [31:0] addr, logic [7:0] len,
                 logic [1:0] expected_resp);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'h7;
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[len + 1];
        tr.strb       = new[len + 1];
        tr.resp       = new[len + 1];
        foreach (tr.strb[i]) begin
            tr.strb[i] = 4'hF;
            tr.resp[i] = `SOC_AXI_RESP_OKAY;
        end
        finish_item(tr);

        foreach (tr.resp[i]) begin
            if (tr.resp[i] != expected_resp) begin
                `uvm_error("APB_FAULT", $sformatf("%s read beat=%0d addr=0x%08h resp=%0h expected=%0h",
                           item_name, i, addr + (i << 2), tr.resp[i], expected_resp))
            end
        end
    endtask

    task do_write(string item_name, logic [31:0] addr, logic [31:0] data,
                  logic [1:0] expected_resp);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'h7;
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

        if (tr.resp[0] != expected_resp) begin
            `uvm_error("APB_FAULT", $sformatf("%s write addr=0x%08h resp=%0h expected=%0h",
                       item_name, addr, tr.resp[0], expected_resp))
        end
    endtask

    task body();
        do_read("apb_timer_wait_state_read", TIMER_VAL_ADDR, 8'h00, `SOC_AXI_RESP_OKAY);
        sample_event(0);

        do_read("apb_fault_single_read", APB_FAULT_ADDR, 8'h00, `SOC_AXI_RESP_SLVERR);
        sample_event(1);

        do_write("apb_fault_single_write", APB_FAULT_ADDR, 32'hA5A5_5A5A, `SOC_AXI_RESP_SLVERR);
        sample_event(2);

        do_read("apb_fault_burst_read", APB_FAULT_ADDR, 8'h03, `SOC_AXI_RESP_SLVERR);
        sample_event(3);
    endtask
endclass

`endif
