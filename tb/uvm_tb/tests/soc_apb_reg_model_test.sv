`ifndef SOC_APB_REG_MODEL_TEST_SV
`define SOC_APB_REG_MODEL_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_apb_reg_model_seq.sv"

class soc_apb_reg_model_test extends soc_base_test;
    `uvm_component_utils(soc_apb_reg_model_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_apb_reg_model_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running APB register model test...", UVM_LOW)

        seq = axi_apb_reg_model_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
