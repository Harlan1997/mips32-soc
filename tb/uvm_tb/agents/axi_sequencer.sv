`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"
class axi_sequencer extends uvm_sequencer #(axi_transaction);
    `uvm_component_utils(axi_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
`endif
