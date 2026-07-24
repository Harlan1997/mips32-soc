`ifndef SOC_ENV_SV
`define SOC_ENV_SV
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_agent.sv"
`include "../agents/axi_master_agent.sv"
`include "soc_scoreboard.sv"
`include "soc_bus_coverage.sv"
class soc_env extends uvm_env;
    `uvm_component_utils(soc_env)
    axi_agent m_axi_agent; // Slave
    axi_master_agent m_axi_master_agent; // Master
    soc_scoreboard sb;
    soc_bus_coverage cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_axi_agent = axi_agent::type_id::create("m_axi_agent", this);
        m_axi_master_agent = axi_master_agent::type_id::create("m_axi_master_agent", this);
        sb = soc_scoreboard::type_id::create("sb", this);
        cov = soc_bus_coverage::type_id::create("cov", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_axi_agent.mon.ap.connect(sb.sram_export);
        m_axi_master_agent.mon.ap.connect(sb.ext_export);
        m_axi_agent.mon.ap.connect(cov.sram_export);
        m_axi_master_agent.mon.ap.connect(cov.ext_export);
    endfunction
endclass
`endif
