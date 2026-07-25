`ifndef SOC_DMA_IRQ_TEST_SV
`define SOC_DMA_IRQ_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_dma_copy_seq.sv"

class soc_dma_irq_test extends soc_base_test;
    `uvm_component_utils(soc_dma_irq_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_dma_copy_seq seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "Running DMA IRQ test...", UVM_LOW)

        seq = axi_dma_copy_seq::type_id::create("seq");
        seq.enable_irq_check = 1'b1;
        seq.start(env.m_axi_master_agent.sqr);

        phase.drop_objection(this);
    endtask
endclass

`endif
