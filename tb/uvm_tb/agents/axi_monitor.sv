`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;
    axi_transaction write_addr_q[$];
    int unsigned    write_beat_q[$];
    axi_transaction write_done_by_id[16][$];
    axi_transaction read_by_id[16][$];
    int unsigned    read_beat_by_id[16][$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vif"});
    endfunction

    function void flush_pending_transactions();
        write_addr_q.delete();
        write_beat_q.delete();

        for (int unsigned id = 0; id < 16; id++) begin
            write_done_by_id[id].delete();
            read_by_id[id].delete();
            read_beat_by_id[id].delete();
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            wait(vif.rst_n);
            fork
                collect_write_channels();
                collect_read_channels();
                wait(!vif.rst_n);
            join_any
            disable fork;
            flush_pending_transactions();
        end
    endtask

    function axi_transaction create_write_transaction();
        axi_transaction tr;
        int unsigned beats;

        tr = axi_transaction::type_id::create("sram_write_tr", this);
        tr.trans_type = AXI_WRITE;
        tr.id         = vif.mon_cb.awid;
        tr.addr       = vif.mon_cb.awaddr;
        tr.len        = vif.mon_cb.awlen;
        tr.size       = vif.mon_cb.awsize;
        tr.burst      = vif.mon_cb.awburst;

        beats = vif.mon_cb.awlen + 1;
        tr.data = new[beats];
        tr.strb = new[beats];
        tr.resp = new[1];

        return tr;
    endfunction

    function axi_transaction create_read_transaction();
        axi_transaction tr;
        int unsigned beats;

        tr = axi_transaction::type_id::create("sram_read_tr", this);
        tr.trans_type = AXI_READ;
        tr.id         = vif.mon_cb.arid;
        tr.addr       = vif.mon_cb.araddr;
        tr.len        = vif.mon_cb.arlen;
        tr.size       = vif.mon_cb.arsize;
        tr.burst      = vif.mon_cb.arburst;

        beats = vif.mon_cb.arlen + 1;
        tr.data = new[beats];
        tr.strb = new[0];
        tr.resp = new[beats];

        return tr;
    endfunction

    task collect_write_channels();
        axi_transaction tr;
        int unsigned beat_idx;
        int unsigned beats;
        int unsigned id;

        forever begin
            @(vif.mon_cb);

            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                tr = create_write_transaction();
                write_addr_q.push_back(tr);
                write_beat_q.push_back(0);
            end

            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                if (write_addr_q.size() == 0) begin
                    `uvm_error("AXI_MON", "SRAM monitor observed W beat with no queued AW")
                end else begin
                    tr = write_addr_q[0];
                    beat_idx = write_beat_q[0];
                    beats = tr.len + 1;

                    if (beat_idx >= beats) begin
                        `uvm_error("AXI_MON", $sformatf("SRAM monitor observed extra W beat id=%0d addr=0x%08h",
                                   tr.id, tr.addr))
                    end else begin
                        tr.data[beat_idx] = vif.mon_cb.wdata;
                        tr.strb[beat_idx] = vif.mon_cb.wstrb;
                        write_beat_q[0] = beat_idx + 1;

                        if (vif.mon_cb.wlast !== ((beat_idx + 1) == beats)) begin
                            `uvm_error("AXI_MON", $sformatf("SRAM monitor WLAST mismatch id=%0d addr=0x%08h beat=%0d beats=%0d wlast=%0b",
                                       tr.id, tr.addr, beat_idx + 1, beats, vif.mon_cb.wlast))
                        end

                        if ((beat_idx + 1) == beats) begin
                            id = tr.id;
                            void'(write_addr_q.pop_front());
                            void'(write_beat_q.pop_front());
                            write_done_by_id[id].push_back(tr);
                        end
                    end
                end
            end

            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                id = vif.mon_cb.bid;
                if (write_done_by_id[id].size() == 0) begin
                    `uvm_error("AXI_MON", $sformatf("SRAM monitor observed B response with no completed write id=%0d resp=%0b",
                               id, vif.mon_cb.bresp))
                end else begin
                    tr = write_done_by_id[id].pop_front();
                    tr.resp[0] = vif.mon_cb.bresp;
                    ap.write(tr);
                end
            end
        end
    endtask

    task collect_read_channels();
        axi_transaction tr;
        int unsigned beat_idx;
        int unsigned beats;
        int unsigned id;

        forever begin
            @(vif.mon_cb);

            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                tr = create_read_transaction();
                id = tr.id;
                read_by_id[id].push_back(tr);
                read_beat_by_id[id].push_back(0);
            end

            if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
                id = vif.mon_cb.rid;
                if (read_by_id[id].size() == 0) begin
                    `uvm_error("AXI_MON", $sformatf("SRAM monitor observed R beat with no queued AR id=%0d resp=%0b",
                               id, vif.mon_cb.rresp))
                end else begin
                    tr = read_by_id[id][0];
                    beat_idx = read_beat_by_id[id][0];
                    beats = tr.len + 1;

                    if (beat_idx >= beats) begin
                        `uvm_error("AXI_MON", $sformatf("SRAM monitor observed extra R beat id=%0d addr=0x%08h",
                                   tr.id, tr.addr))
                    end else begin
                        tr.data[beat_idx] = vif.mon_cb.rdata;
                        tr.resp[beat_idx] = vif.mon_cb.rresp;
                        read_beat_by_id[id][0] = beat_idx + 1;

                        if (vif.mon_cb.rlast !== ((beat_idx + 1) == beats)) begin
                            `uvm_error("AXI_MON", $sformatf("SRAM monitor RLAST mismatch id=%0d addr=0x%08h beat=%0d beats=%0d rlast=%0b",
                                       tr.id, tr.addr, beat_idx + 1, beats, vif.mon_cb.rlast))
                        end

                        if ((beat_idx + 1) == beats) begin
                            void'(read_by_id[id].pop_front());
                            void'(read_beat_by_id[id].pop_front());
                            ap.write(tr);
                        end
                    end
                end
            end
        end
    endtask
endclass
`endif
