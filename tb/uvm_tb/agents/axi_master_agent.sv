`ifndef AXI_MASTER_AGENT_SV
`define AXI_MASTER_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"
`include "axi_sequencer.sv"
`include "axi_master_driver.sv"
`include "axi_monitor.sv"

class axi_master_agent extends uvm_agent;
    `uvm_component_utils(axi_master_agent)
    
    axi_sequencer sqr;
    axi_master_driver drv;
    axi_monitor mon;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = axi_sequencer::type_id::create("sqr", this);
            drv = axi_master_driver::type_id::create("drv", this);
        end
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif
