`ifndef SOC_PIC_MASK_ARBITRATION_TEST_SV
`define SOC_PIC_MASK_ARBITRATION_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_pic_mask_arbitration_seq.sv"

class soc_pic_mask_arbitration_test extends soc_base_test;
    `uvm_component_utils(soc_pic_mask_arbitration_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_pic_mask_arbitration_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running PIC mask arbitration test...", UVM_LOW)

        seq = axi_pic_mask_arbitration_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
