`ifndef SOC_AXI_ATTRIBUTE_CROSS_SWEEP_TEST_SV
`define SOC_AXI_ATTRIBUTE_CROSS_SWEEP_TEST_SV

//------------------------------------------------------------------------------
// soc_axi_attribute_cross_sweep_test
//
// Phase A coverage-closure helper. Drives the axi_attribute_cross_sweep_seq
// which materially expands (id × len × window × direction × response) cross
// coverage per the reviewer feedback in .agent/review.md.
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_attribute_cross_sweep_seq.sv"

class soc_axi_attribute_cross_sweep_test extends soc_base_test;
    `uvm_component_utils(soc_axi_attribute_cross_sweep_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_attribute_cross_sweep_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running AXI attribute cross sweep test...", UVM_LOW)

        seq = axi_attribute_cross_sweep_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
