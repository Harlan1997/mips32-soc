`ifndef AXI_MASTER_DRIVER_SV
`define AXI_MASTER_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_master_if.sv"
`include "axi_transaction.sv"

class axi_master_driver extends uvm_driver#(axi_transaction);
    `uvm_component_utils(axi_master_driver)

    virtual axi_master_if vif;
    bit enable_overlap_mode;
    axi_transaction write_aw_q[$];
    axi_transaction write_w_q[$];
    axi_transaction write_b_q[16][$];
    axi_transaction read_ar_q[$];
    axi_transaction read_r_q[16][$];
    int unsigned    read_beat_q[16][$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi_master_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV", "Could not get virtual interface")
        end
        void'(uvm_config_db#(bit)::get(this, "", "enable_overlap_mode", enable_overlap_mode));
    endfunction

    task run_phase(uvm_phase phase);
        vif.mcb.awid    <= 0;
        vif.mcb.awaddr  <= 0;
        vif.mcb.awlen   <= 0;
        vif.mcb.awsize  <= 3'd2;
        vif.mcb.awburst <= 2'b01;
        vif.mcb.awlock  <= 0;
        vif.mcb.awcache <= 0;
        vif.mcb.awprot  <= 0;
        vif.mcb.awvalid <= 0;
        vif.mcb.wid     <= 0;
        vif.mcb.wdata   <= 0;
        vif.mcb.wstrb   <= 0;
        vif.mcb.wlast   <= 0;
        vif.mcb.wvalid  <= 0;
        vif.mcb.bready  <= 0;
        vif.mcb.arid    <= 0;
        vif.mcb.araddr  <= 0;
        vif.mcb.arlen   <= 0;
        vif.mcb.arsize  <= 3'd2;
        vif.mcb.arburst <= 2'b01;
        vif.mcb.arlock  <= 0;
        vif.mcb.arcache <= 0;
        vif.mcb.arprot  <= 0;
        vif.mcb.arvalid <= 0;
        vif.mcb.rready  <= 0;
        
        wait(vif.rst_n);

        if (enable_overlap_mode) begin
            run_overlap_mode();
        end else begin
            run_serial_mode();
        end
    endtask

    task run_serial_mode();
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

    task run_overlap_mode();
        fork
            accept_overlap_items();
            drive_overlap_aw();
            drive_overlap_w();
            collect_overlap_b();
            drive_overlap_ar();
            collect_overlap_r();
        join
    endtask

    task accept_overlap_items();
        axi_transaction tr;

        forever begin
            seq_item_port.get_next_item(tr);
            if (tr.trans_type == AXI_WRITE) begin
                write_aw_q.push_back(tr);
            end else begin
                read_ar_q.push_back(tr);
            end
            seq_item_port.item_done();
        end
    endtask

    task drive_overlap_aw();
        axi_transaction tr;

        forever begin
            @(vif.mcb);
            if (write_aw_q.size() != 0) begin
                tr = write_aw_q.pop_front();
                vif.mcb.awid    <= tr.id;
                vif.mcb.awaddr  <= tr.addr;
                vif.mcb.awlen   <= tr.len;
                vif.mcb.awsize  <= tr.size;
                vif.mcb.awburst <= tr.burst;
                vif.mcb.awlock  <= 2'b00;
                vif.mcb.awcache <= 4'b0000;
                vif.mcb.awprot  <= 3'b000;
                vif.mcb.awvalid <= 1'b1;

                @(vif.mcb);
                while(!vif.mcb.awready) @(vif.mcb);
                vif.mcb.awvalid <= 1'b0;
                write_w_q.push_back(tr);
            end
        end
    endtask

    task drive_overlap_w();
        axi_transaction tr;

        forever begin
            @(vif.mcb);
            if (write_w_q.size() != 0) begin
                tr = write_w_q.pop_front();
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
                write_b_q[tr.id].push_back(tr);
            end
        end
    endtask

    task collect_overlap_b();
        int unsigned id;
        axi_transaction tr;

        vif.mcb.bready <= 1'b1;
        forever begin
            @(vif.mcb);
            if (vif.mcb.bvalid) begin
                id = vif.mcb.bid;
                if (write_b_q[id].size() == 0) begin
                    `uvm_error("DRV_B", $sformatf("B response with no pending overlapped write id=%0d resp=%0b",
                               id, vif.mcb.bresp))
                end else begin
                    tr = write_b_q[id].pop_front();
                    if (tr.resp.size() > 0) begin
                        tr.resp[0] = vif.mcb.bresp;
                    end
                end
            end
        end
    endtask

    task drive_overlap_ar();
        axi_transaction tr;

        forever begin
            @(vif.mcb);
            if (read_ar_q.size() != 0) begin
                tr = read_ar_q.pop_front();
                vif.mcb.arid    <= tr.id;
                vif.mcb.araddr  <= tr.addr;
                vif.mcb.arlen   <= tr.len;
                vif.mcb.arsize  <= tr.size;
                vif.mcb.arburst <= tr.burst;
                vif.mcb.arlock  <= 2'b00;
                vif.mcb.arcache <= 4'b0000;
                vif.mcb.arprot  <= 3'b000;
                vif.mcb.arvalid <= 1'b1;

                @(vif.mcb);
                while(!vif.mcb.arready) @(vif.mcb);
                vif.mcb.arvalid <= 1'b0;
                read_r_q[tr.id].push_back(tr);
                read_beat_q[tr.id].push_back(0);
            end
        end
    endtask

    task collect_overlap_r();
        int unsigned id;
        axi_transaction tr;
        int unsigned beat_idx;

        vif.mcb.rready <= 1'b1;
        forever begin
            @(vif.mcb);
            if (vif.mcb.rvalid) begin
                id = vif.mcb.rid;
                if (read_r_q[id].size() == 0 || read_beat_q[id].size() == 0) begin
                    `uvm_error("DRV_R", $sformatf("R beat with no pending overlapped read id=%0d resp=%0b",
                               id, vif.mcb.rresp))
                end else begin
                    tr = read_r_q[id][0];
                    beat_idx = read_beat_q[id][0];
                    if (beat_idx <= tr.len) begin
                        tr.data[beat_idx] = vif.mcb.rdata;
                        tr.resp[beat_idx] = vif.mcb.rresp;
                    end else begin
                        `uvm_error("DRV_R", $sformatf("Extra R beat id=%0d addr=0x%08h", tr.id, tr.addr))
                    end

                    if (vif.mcb.rlast) begin
                        void'(read_r_q[id].pop_front());
                        void'(read_beat_q[id].pop_front());
                    end else begin
                        read_beat_q[id][0] = beat_idx + 1;
                    end
                end
            end
        end
    endtask

    task drive_write(axi_transaction tr);
        // AW Channel
        vif.mcb.awid    <= tr.id;
        vif.mcb.awaddr  <= tr.addr;
        vif.mcb.awlen   <= tr.len;
        vif.mcb.awsize  <= tr.size;
        vif.mcb.awburst <= tr.burst;
        vif.mcb.awlock  <= 2'b00;
        vif.mcb.awcache <= 4'b0000;
        vif.mcb.awprot  <= 3'b000;
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
        if (tr.resp.size() > 0) begin
            tr.resp[0] = vif.mcb.bresp;
        end
        vif.mcb.bready <= 1'b0;
    endtask

    task drive_read(axi_transaction tr);
        // AR Channel
        vif.mcb.arid    <= tr.id;
        vif.mcb.araddr  <= tr.addr;
        vif.mcb.arlen   <= tr.len;
        vif.mcb.arsize  <= tr.size;
        vif.mcb.arburst <= tr.burst;
        vif.mcb.arlock  <= 2'b00;
        vif.mcb.arcache <= 4'b0000;
        vif.mcb.arprot  <= 3'b000;
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
