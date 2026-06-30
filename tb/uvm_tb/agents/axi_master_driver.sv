`ifndef AXI_MASTER_DRIVER_SV
`define AXI_MASTER_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"

class axi_master_driver extends uvm_driver#(axi_transaction);
    `uvm_component_utils(axi_master_driver)

    virtual axi_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV", "Could not get virtual interface")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.awvalid <= 0;
        vif.wvalid <= 0;
        vif.wlast <= 0;
        vif.bready <= 0;
        vif.arvalid <= 0;
        vif.rready <= 0;
        
        wait(vif.rst_n);
        
        forever begin
            seq_item_port.get_next_item(req);
            if (req.trans_type == AXI_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            seq_item_port.item_done();
        end
    endtask

    task drive_write(axi_transaction tr);
        // AW Channel
        vif.mcb.awid    <= tr.id;
        vif.mcb.awaddr  <= tr.addr;
        vif.mcb.awlen   <= tr.len;
        vif.mcb.awsize  <= tr.size;
        vif.mcb.awburst <= tr.burst;
        vif.mcb.awvalid <= 1'b1;
        
        @(vif.mcb);
        while(!vif.mcb.awready) @(vif.mcb);
        vif.mcb.awvalid <= 1'b0;
        
        // W Channel
        for (int i = 0; i <= tr.len; i++) begin
            vif.mcb.wdata  <= tr.data[i];
            vif.mcb.wstrb  <= tr.strb[i];
            vif.mcb.wlast  <= (i == tr.len);
            vif.mcb.wvalid <= 1'b1;
            
            @(vif.mcb);
            while(!vif.mcb.wready) @(vif.mcb);
        end
        vif.mcb.wvalid <= 1'b0;
        vif.mcb.wlast  <= 1'b0;
        
        // B Channel
        vif.mcb.bready <= 1'b1;
        while(!vif.mcb.bvalid) @(vif.mcb);
        vif.mcb.bready <= 1'b0;
    endtask

    task drive_read(axi_transaction tr);
        // AR Channel
        vif.mcb.arid    <= tr.id;
        vif.mcb.araddr  <= tr.addr;
        vif.mcb.arlen   <= tr.len;
        vif.mcb.arsize  <= tr.size;
        vif.mcb.arburst <= tr.burst;
        vif.mcb.arvalid <= 1'b1;
        
        @(vif.mcb);
        while(!vif.mcb.arready) @(vif.mcb);
        vif.mcb.arvalid <= 1'b0;
        
        // R Channel
        vif.mcb.rready <= 1'b1;
        for (int i = 0; i <= tr.len; i++) begin
            while(!vif.mcb.rvalid) @(vif.mcb);
            tr.data[i] = vif.mcb.rdata;
            tr.resp[i] = vif.mcb.rresp;
            @(vif.mcb);
        end
        vif.mcb.rready <= 1'b0;
    endtask

endclass
`endif
