`ifndef SOC_BASE_TEST_SV
`define SOC_BASE_TEST_SV
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../env/soc_env.sv"

class soc_base_test extends uvm_test;
    `uvm_component_utils(soc_base_test)
    soc_env env;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_env::type_id::create("env", this);
    endfunction
    
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        uvm_config_db#(int)::set(this, "env.m_axi_agent.seqr", "enable_backpressure", 0);
        `uvm_info("TEST", "Running UVM Backpressure Random Test...", UVM_LOW)
        // Since driver is autonomous slave, we just let it run.
        // We will wait 500,000,000 time units
        // Timeout watchdog
        fork
            begin
                #6000000000;
                `uvm_info("TEST", "Test completed (timeout).", UVM_LOW)
            end
        join_any
        phase.drop_objection(this);
    endtask
endclass
`endif
