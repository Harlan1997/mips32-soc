`ifndef SOC_FLASH_IMAGE_TEST_SV
`define SOC_FLASH_IMAGE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_flash_image_seq.sv"

class soc_flash_image_test extends soc_base_test;
    `uvm_component_utils(soc_flash_image_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_flash_image_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running flash image read test...", UVM_LOW)

        seq = axi_flash_image_seq::type_id::create("seq");
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
