// =============================================================================
// File Name: mips_mem_stage_pkg.sv
// Design:    UVM Verification Package for MEM Stage
// Author:    Antigravity
// =============================================================================

package mips_mem_stage_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class mem_transaction extends uvm_sequence_item;
        rand logic [31:0] mem_ex_out;
        rand logic [31:0] mem_val_rt;
        rand logic        mem_read;
        rand logic        mem_write;
        rand logic [2:0]  mem_op;
        rand logic [31:0] dmem_rdata;
        rand logic        mem_done;
        rand logic        translation_fault;

        logic [31:0] dmem_addr;
        logic [31:0] dmem_wdata;
        logic        dmem_we;
        logic [3:0]  dmem_be;
        logic        dmem_en;
        logic [31:0] mem_rdata_ext;
        logic        adel_exception;
        logic        ades_exception;

        // Constraints
        constraint op_valid {
            mem_op inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100,
                           3'b101, 3'b110, 3'b111};
            mem_read != mem_write; // test either read or write
        }
        
        // Sometimes generate unaligned addresses to test exceptions
        constraint align_c {
            mem_ex_out[1:0] dist {
                2'b00 := 40,
                2'b01 := 20,
                2'b10 := 20,
                2'b11 := 20
            };
        }

        constraint response_state_c {
            mem_done dist {1'b0 := 90, 1'b1 := 10};
            translation_fault dist {1'b0 := 80, 1'b1 := 20};
        }

        `uvm_object_utils_begin(mem_transaction)
            `uvm_field_int(mem_ex_out, UVM_ALL_ON)
            `uvm_field_int(mem_val_rt, UVM_ALL_ON)
            `uvm_field_int(mem_read, UVM_ALL_ON)
            `uvm_field_int(mem_write, UVM_ALL_ON)
            `uvm_field_int(mem_op, UVM_ALL_ON)
            `uvm_field_int(dmem_rdata, UVM_ALL_ON)
            `uvm_field_int(mem_done, UVM_ALL_ON)
            `uvm_field_int(translation_fault, UVM_ALL_ON)
            `uvm_field_int(dmem_addr, UVM_ALL_ON)
            `uvm_field_int(dmem_wdata, UVM_ALL_ON)
            `uvm_field_int(dmem_we, UVM_ALL_ON)
            `uvm_field_int(dmem_be, UVM_ALL_ON)
            `uvm_field_int(dmem_en, UVM_ALL_ON)
            `uvm_field_int(mem_rdata_ext, UVM_ALL_ON)
            `uvm_field_int(adel_exception, UVM_ALL_ON)
            `uvm_field_int(ades_exception, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "mem_transaction");
            super.new(name);
        endfunction
    endclass

    class mem_sequence extends uvm_sequence#(mem_transaction);
        `uvm_object_utils(mem_sequence)
        function new(string name = "mem_sequence");
            super.new(name);
        endfunction
        virtual task body();
            repeat(2000) begin
                req = mem_transaction::type_id::create("req");
                start_item(req);
                assert(req.randomize());
                finish_item(req);
            end
        endtask
    endclass

    class mem_driver extends uvm_driver#(mem_transaction);
        `uvm_component_utils(mem_driver)
        virtual mips_mem_stage_if vif;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if(!uvm_config_db#(virtual mips_mem_stage_if)::get(this, "", "vif", vif))
                `uvm_fatal("NO_VIF", "Virtual interface not set")
        endfunction
        virtual task run_phase(uvm_phase phase);
            vif.mem_ex_out = 0;
            vif.mem_val_rt = 0;
            vif.mem_read = 0;
            vif.mem_write = 0;
            vif.mem_op = 0;
            vif.dmem_rdata = 0;
            vif.mem_done = 0;
            vif.enable_nonblocking_load = 0;
            vif.mem_cache_op_valid = 0;
            vif.mem_cache_op = 0;
            vif.dmem_addr_ok = 0;
            vif.dmem_data_ok = 0;
            vif.translation_fault = 0;
            vif.cache_op_done = 0;
            vif.cache_op_error = 0;
            @(posedge vif.rst_n);
            forever begin
                seq_item_port.get_next_item(req);
                @(posedge vif.clk);
                vif.mem_ex_out = req.mem_ex_out;
                vif.mem_val_rt = req.mem_val_rt;
                vif.mem_read   = req.mem_read;
                vif.mem_write  = req.mem_write;
                vif.mem_op     = req.mem_op;
                vif.dmem_rdata = req.dmem_rdata;
                vif.mem_done = req.mem_done;
                vif.translation_fault = req.translation_fault;
                #1; // wait for comb logic
                seq_item_port.item_done();
            end
        endtask
    endclass

    class mem_monitor extends uvm_monitor;
        `uvm_component_utils(mem_monitor)
        virtual mips_mem_stage_if vif;
        uvm_analysis_port#(mem_transaction) ap;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if(!uvm_config_db#(virtual mips_mem_stage_if)::get(this, "", "vif", vif))
                `uvm_fatal("NO_VIF", "Virtual interface not set")
        endfunction
        virtual task run_phase(uvm_phase phase);
            mem_transaction tr;
            @(posedge vif.rst_n);
            forever begin
                @(posedge vif.clk);
                #2;
                tr = mem_transaction::type_id::create("tr");
                tr.mem_ex_out = vif.mem_ex_out;
                tr.mem_val_rt = vif.mem_val_rt;
                tr.mem_read = vif.mem_read;
                tr.mem_write = vif.mem_write;
                tr.mem_op = vif.mem_op;
                tr.dmem_rdata = vif.dmem_rdata;
                tr.mem_done = vif.mem_done;
                tr.translation_fault = vif.translation_fault;
                tr.dmem_addr = vif.dmem_addr;
                tr.dmem_wdata = vif.dmem_wdata;
                tr.dmem_we = vif.dmem_we;
                tr.dmem_be = vif.dmem_be;
                tr.dmem_en = vif.dmem_en;
                tr.mem_rdata_ext = vif.mem_rdata_ext;
                tr.adel_exception = vif.adel_exception;
                tr.ades_exception = vif.ades_exception;
                ap.write(tr);
            end
        endtask
    endclass

    class mem_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(mem_scoreboard)
        uvm_analysis_imp#(mem_transaction, mem_scoreboard) imp;
        int error_count = 0;
        int match_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp = new("imp", this);
        endfunction

        function void write(mem_transaction tr);
            logic [31:0] exp_dmem_addr;
            logic [31:0] exp_dmem_wdata;
            logic        exp_dmem_we;
            logic [3:0]  exp_dmem_be;
            logic        exp_dmem_en;
            logic [31:0] exp_mem_rdata_ext;
            logic        exp_adel;
            logic        exp_ades;
            logic [1:0]  align = tr.mem_ex_out[1:0];

            exp_dmem_addr = {tr.mem_ex_out[31:2], 2'b00};
            exp_dmem_en = tr.mem_read | tr.mem_write;
            exp_dmem_wdata = 32'd0;
            exp_dmem_we = tr.mem_write;
            exp_dmem_be = 4'd0;
            exp_mem_rdata_ext = tr.dmem_rdata;
            
            if (tr.mem_write) begin
                case (tr.mem_op)
                    3'b000: begin // SB
                        exp_dmem_wdata = {4{tr.mem_val_rt[7:0]}};
                        case (align)
                            2'b00: exp_dmem_be = 4'b0001;
                            2'b01: exp_dmem_be = 4'b0010;
                            2'b10: exp_dmem_be = 4'b0100;
                            2'b11: exp_dmem_be = 4'b1000;
                        endcase
                    end
                    3'b010: begin // SH
                        exp_dmem_wdata = {2{tr.mem_val_rt[15:0]}};
                        case (align[1])
                            1'b0: exp_dmem_be = 4'b0011;
                            1'b1: exp_dmem_be = 4'b1100;
                        endcase
                    end
                    3'b100, 3'b111: begin // SW / SC
                        exp_dmem_wdata = tr.mem_val_rt;
                        exp_dmem_be = 4'b1111;
                    end
                    3'b101: begin // SWL, little endian
                        case (align)
                            2'b00: begin exp_dmem_be = 4'b0001; exp_dmem_wdata = {24'd0, tr.mem_val_rt[31:24]}; end
                            2'b01: begin exp_dmem_be = 4'b0011; exp_dmem_wdata = {16'd0, tr.mem_val_rt[31:16]}; end
                            2'b10: begin exp_dmem_be = 4'b0111; exp_dmem_wdata = {8'd0, tr.mem_val_rt[31:8]}; end
                            2'b11: begin exp_dmem_be = 4'b1111; exp_dmem_wdata = tr.mem_val_rt; end
                        endcase
                    end
                    3'b110: begin // SWR, little endian
                        case (align)
                            2'b00: begin exp_dmem_be = 4'b1111; exp_dmem_wdata = tr.mem_val_rt; end
                            2'b01: begin exp_dmem_be = 4'b1110; exp_dmem_wdata = {tr.mem_val_rt[23:0], 8'd0}; end
                            2'b10: begin exp_dmem_be = 4'b1100; exp_dmem_wdata = {tr.mem_val_rt[15:0], 16'd0}; end
                            2'b11: begin exp_dmem_be = 4'b1000; exp_dmem_wdata = {tr.mem_val_rt[7:0], 24'd0}; end
                        endcase
                    end
                endcase
            end

            if (tr.mem_read) begin
                case (tr.mem_op)
                    3'b000: begin // LB
                        case (align)
                            2'b00: exp_mem_rdata_ext = { {24{tr.dmem_rdata[7]}}, tr.dmem_rdata[7:0] };
                            2'b01: exp_mem_rdata_ext = { {24{tr.dmem_rdata[15]}}, tr.dmem_rdata[15:8] };
                            2'b10: exp_mem_rdata_ext = { {24{tr.dmem_rdata[23]}}, tr.dmem_rdata[23:16] };
                            2'b11: exp_mem_rdata_ext = { {24{tr.dmem_rdata[31]}}, tr.dmem_rdata[31:24] };
                        endcase
                    end
                    3'b001: begin // LBU
                        case (align)
                            2'b00: exp_mem_rdata_ext = { 24'd0, tr.dmem_rdata[7:0] };
                            2'b01: exp_mem_rdata_ext = { 24'd0, tr.dmem_rdata[15:8] };
                            2'b10: exp_mem_rdata_ext = { 24'd0, tr.dmem_rdata[23:16] };
                            2'b11: exp_mem_rdata_ext = { 24'd0, tr.dmem_rdata[31:24] };
                        endcase
                    end
                    3'b010: begin // LH
                        case (align[1])
                            1'b0: exp_mem_rdata_ext = { {16{tr.dmem_rdata[15]}}, tr.dmem_rdata[15:0] };
                            1'b1: exp_mem_rdata_ext = { {16{tr.dmem_rdata[31]}}, tr.dmem_rdata[31:16] };
                        endcase
                    end
                    3'b011: begin // LHU
                        case (align[1])
                            1'b0: exp_mem_rdata_ext = { 16'd0, tr.dmem_rdata[15:0] };
                            1'b1: exp_mem_rdata_ext = { 16'd0, tr.dmem_rdata[31:16] };
                        endcase
                    end
                    3'b100, 3'b111: exp_mem_rdata_ext = tr.dmem_rdata;
                    3'b101: begin // LWL, little endian
                        case (align)
                            2'b00: exp_mem_rdata_ext = {tr.dmem_rdata[7:0], tr.mem_val_rt[23:0]};
                            2'b01: exp_mem_rdata_ext = {tr.dmem_rdata[15:0], tr.mem_val_rt[15:0]};
                            2'b10: exp_mem_rdata_ext = {tr.dmem_rdata[23:0], tr.mem_val_rt[7:0]};
                            2'b11: exp_mem_rdata_ext = tr.dmem_rdata;
                        endcase
                    end
                    3'b110: begin // LWR, little endian
                        case (align)
                            2'b00: exp_mem_rdata_ext = tr.dmem_rdata;
                            2'b01: exp_mem_rdata_ext = {tr.mem_val_rt[31:24], tr.dmem_rdata[31:8]};
                            2'b10: exp_mem_rdata_ext = {tr.mem_val_rt[31:16], tr.dmem_rdata[31:16]};
                            2'b11: exp_mem_rdata_ext = {tr.mem_val_rt[31:8], tr.dmem_rdata[31:24]};
                        endcase
                    end
                endcase
            end

            exp_adel = tr.mem_read & ((tr.mem_op inside {3'b010, 3'b011} & align[0]) | (tr.mem_op == 3'b100 & align != 2'b00));
            exp_ades = tr.mem_write & ((tr.mem_op inside {3'b010, 3'b011} & align[0]) | (tr.mem_op == 3'b100 & align != 2'b00));
            exp_dmem_en = (tr.mem_read | tr.mem_write) & !exp_adel & !exp_ades &
                          !tr.translation_fault & !tr.mem_done;

            if (tr.dmem_addr !== exp_dmem_addr || tr.dmem_en !== exp_dmem_en || tr.dmem_wdata !== exp_dmem_wdata ||
                tr.dmem_we !== exp_dmem_we || tr.dmem_be !== exp_dmem_be || tr.mem_rdata_ext !== exp_mem_rdata_ext ||
                tr.adel_exception !== exp_adel || tr.ades_exception !== exp_ades) begin
                `uvm_error("MEM_MISMATCH", $sformatf("Mismatch: \nInputs: addr=%h op=%b r=%b w=%b \nExpected: en=%b we=%b be=%b wdata=%h rdata_ext=%h adel=%b ades=%b \nActual: en=%b we=%b be=%b wdata=%h rdata_ext=%h adel=%b ades=%b",
                    tr.mem_ex_out, tr.mem_op, tr.mem_read, tr.mem_write, 
                    exp_dmem_en, exp_dmem_we, exp_dmem_be, exp_dmem_wdata, exp_mem_rdata_ext, exp_adel, exp_ades,
                    tr.dmem_en, tr.dmem_we, tr.dmem_be, tr.dmem_wdata, tr.mem_rdata_ext, tr.adel_exception, tr.ades_exception))
                error_count++;
            end else begin
                match_count++;
            end
        endfunction
        
        function void report_phase(uvm_phase phase);
            if (error_count == 0)
                `uvm_info("SCB_PASS", $sformatf("All %0d transactions PASSED", match_count), UVM_NONE)
            else
                `uvm_error("SCB_FAIL", $sformatf("%0d transactions FAILED", error_count))
        endfunction
    endclass

    class mem_agent extends uvm_agent;
        `uvm_component_utils(mem_agent)
        uvm_sequencer#(mem_transaction) sqr;
        mem_driver drv;
        mem_monitor mon;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sqr = uvm_sequencer#(mem_transaction)::type_id::create("sqr", this);
            drv = mem_driver::type_id::create("drv", this);
            mon = mem_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class mem_env extends uvm_env;
        `uvm_component_utils(mem_env)
        mem_agent agt;
        mem_scoreboard scb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = mem_agent::type_id::create("agt", this);
            scb = mem_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class mem_test extends uvm_test;
        `uvm_component_utils(mem_test)
        mem_env env;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = mem_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            mem_sequence seq = mem_sequence::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agt.sqr);
            #100;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
