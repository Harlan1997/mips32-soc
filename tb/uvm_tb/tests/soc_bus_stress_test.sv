`ifndef SOC_BUS_STRESS_TEST_SV
`define SOC_BUS_STRESS_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_base_test.sv"
`include "../seqs/axi_stress_seq.sv"

class soc_bus_stress_test extends soc_base_test;
    `uvm_component_utils(soc_bus_stress_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_stress_seq m_seq;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Running UVM Bus Stress Test with Background Traffic...", UVM_LOW)
        
        m_seq = axi_stress_seq::type_id::create("m_seq");
        
        fork
            // Launch the stress sequence to inject heavy random traffic
            m_seq.start(env.m_axi_master_agent.sqr);
            
            // Allow the base test timeout logic and firmware mailbox check to run
            super.run_phase(phase);
        join_any
        
        phase.drop_objection(this);
    endtask
endclass

`endif
