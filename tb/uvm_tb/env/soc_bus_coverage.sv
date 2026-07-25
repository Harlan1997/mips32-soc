`ifndef SOC_BUS_COVERAGE_SV
`define SOC_BUS_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_transaction.sv"
`include "soc_config.vh"

`uvm_analysis_imp_decl(_cov_ext)
`uvm_analysis_imp_decl(_cov_sram)

class soc_bus_coverage extends uvm_component;
    `uvm_component_utils(soc_bus_coverage)

    uvm_analysis_imp_cov_ext  #(axi_transaction, soc_bus_coverage) ext_export;
    uvm_analysis_imp_cov_sram #(axi_transaction, soc_bus_coverage) sram_export;

    localparam int SRC_EXT      = 0;
    localparam int SRC_SRAM_MON = 1;
    localparam int TYPE_READ    = 0;
    localparam int TYPE_WRITE   = 1;
    localparam int WIN_BOOT     = 0;
    localparam int WIN_ALIAS    = 1;
    localparam int WIN_APB      = 2;
    localparam int WIN_FLASH    = 3;
    localparam int WIN_UNMAPPED = 4;

    int unsigned sample_source;
    int unsigned sample_type;
    int unsigned sample_window;
    int unsigned sample_resp;
    int unsigned sample_len;
    int unsigned sample_size;
    int unsigned sample_burst;
    int unsigned sample_id;

    int unsigned ext_sample_count;
    int unsigned sram_sample_count;

    covergroup bus_contract_cg;
        option.per_instance = 1;

        source_cp: coverpoint sample_source {
            bins ext      = {SRC_EXT};
            bins sram_mon = {SRC_SRAM_MON};
        }

        type_cp: coverpoint sample_type {
            bins read  = {TYPE_READ};
            bins write = {TYPE_WRITE};
        }

        window_cp: coverpoint sample_window {
            bins boot     = {WIN_BOOT};
            bins sram_alias = {WIN_ALIAS};
            bins apb      = {WIN_APB};
            bins flash    = {WIN_FLASH};
            bins unmapped = {WIN_UNMAPPED};
        }

        resp_cp: coverpoint sample_resp {
            bins okay   = {`SOC_AXI_RESP_OKAY};
            bins slverr = {`SOC_AXI_RESP_SLVERR};
            bins decerr = {`SOC_AXI_RESP_DECERR};
            ignore_bins exokay_unsupported = {`SOC_AXI_RESP_EXOKAY};
        }

        len_cp: coverpoint sample_len {
            bins single     = {0};
            bins burst_2_4  = {[1:3]};
            bins burst_5_8  = {[4:7]};
            bins burst_long = {[8:255]};
        }

        size_cp: coverpoint sample_size {
            bins word      = {2};
            ignore_bins non_word_unsupported = {0, 1, [3:7]};
        }

        burst_cp: coverpoint sample_burst {
            bins incr  = {1};
            ignore_bins fixed_unsupported = {0};
            ignore_bins wrap_unsupported  = {2};
            ignore_bins rsvd_unsupported  = {3};
        }

        id_cp: coverpoint sample_id {
            bins id0     = {0};
            bins id1_3   = {[1:3]};
            bins id4_7   = {[4:7]};
            bins id8_15  = {[8:15]};
        }

        source_type_window_cross: cross source_cp, type_cp, window_cp {
            ignore_bins sram_monitor_external_windows =
                binsof(source_cp.sram_mon) &&
                (binsof(window_cp.unmapped) ||
                 binsof(window_cp.flash) ||
                 binsof(window_cp.apb));
        }

        window_resp_cross: cross window_cp, resp_cp {
            ignore_bins unmapped_non_decerr =
                binsof(window_cp.unmapped) &&
                (binsof(resp_cp.okay) || binsof(resp_cp.slverr));
            ignore_bins flash_decerr_unsupported =
                binsof(window_cp.flash) && binsof(resp_cp.decerr);
            ignore_bins normal_window_errors =
                (binsof(window_cp.apb) ||
                 binsof(window_cp.sram_alias) ||
                 binsof(window_cp.boot)) &&
                (binsof(resp_cp.decerr) || binsof(resp_cp.slverr));
        }

        type_len_cross: cross type_cp, len_cp;
        source_type_id_cross: cross source_cp, type_cp, id_cp;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ext_export  = new("ext_export", this);
        sram_export = new("sram_export", this);
        bus_contract_cg = new();
    endfunction

    function int unsigned classify_window(logic [31:0] addr);
        if ((addr & `SOC_64KB_REGION_MASK) == `SOC_BOOT_BASE) begin
            return WIN_BOOT;
        end
        if ((addr & `SOC_64KB_REGION_MASK) == `SOC_SRAM_ALIAS_BASE) begin
            return WIN_ALIAS;
        end
        if ((addr & `SOC_64KB_REGION_MASK) == `SOC_APB_BASE) begin
            return WIN_APB;
        end
        if ((addr & `SOC_256MB_REGION_MASK) == `SOC_FLASH_BASE) begin
            return WIN_FLASH;
        end
        return WIN_UNMAPPED;
    endfunction

    function void sample_transaction(axi_transaction tr, int unsigned source);
        int unsigned resp_count;

        resp_count = tr.resp.size();
        if (resp_count == 0) begin
            return;
        end

        sample_source = source;
        sample_type   = (tr.trans_type == AXI_READ) ? TYPE_READ : TYPE_WRITE;
        sample_window = classify_window(tr.addr);
        sample_len    = tr.len;
        sample_size   = tr.size;
        sample_burst  = tr.burst;
        sample_id     = tr.id;

        foreach (tr.resp[i]) begin
            sample_resp = tr.resp[i];
            bus_contract_cg.sample();
            if (source == SRC_EXT) begin
                ext_sample_count++;
            end else begin
                sram_sample_count++;
            end
        end
    endfunction

    function void write_cov_ext(axi_transaction tr);
        sample_transaction(tr, SRC_EXT);
    endfunction

    function void write_cov_sram(axi_transaction tr);
        sample_transaction(tr, SRC_SRAM_MON);
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV_SUMMARY", $sformatf("bus_contract_cov=%0.2f ext_samples=%0d sram_samples=%0d",
                  bus_contract_cg.get_inst_coverage(), ext_sample_count, sram_sample_count), UVM_LOW)
    endfunction
endclass

`endif
