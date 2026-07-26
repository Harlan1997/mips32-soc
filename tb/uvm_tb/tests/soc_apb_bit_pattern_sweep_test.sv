`ifndef SOC_APB_BIT_PATTERN_SWEEP_TEST_SV
`define SOC_APB_BIT_PATTERN_SWEEP_TEST_SV

//------------------------------------------------------------------------------
// soc_apb_bit_pattern_sweep_test — Phase A closure helper for APB peripheral
// register toggle coverage. Runs axi_apb_bit_pattern_sweep_seq.
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_apb_bit_pattern_sweep_seq.sv"

class soc_apb_bit_pattern_sweep_test extends soc_base_test;
    `uvm_component_utils(soc_apb_bit_pattern_sweep_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_apb_bit_pattern_sweep_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running APB bit pattern sweep...", UVM_LOW)

        seq = axi_apb_bit_pattern_sweep_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
