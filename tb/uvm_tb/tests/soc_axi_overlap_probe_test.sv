`ifndef SOC_AXI_OVERLAP_PROBE_TEST_SV
`define SOC_AXI_OVERLAP_PROBE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_overlap_probe_seq.sv"

class soc_axi_overlap_probe_test extends soc_base_test;
    `uvm_component_utils(soc_axi_overlap_probe_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        uvm_config_db#(bit)::set(this, "env.m_axi_master_agent.drv", "enable_overlap_mode", 1'b1);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        axi_overlap_probe_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running AXI overlap probe test...", UVM_LOW)

        seq = axi_overlap_probe_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
