`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vif"});
    endfunction
    task run_phase(uvm_phase phase);
        // Placeholder for monitor
    endtask
endclass
`endif
