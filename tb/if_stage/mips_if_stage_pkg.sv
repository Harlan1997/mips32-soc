// =============================================================================
// File Name: mips_if_stage_pkg.sv
// Design:    MIPS32 IF Stage UVM Verification Package
// Author:    Antigravity
// Description:
//   Contains the complete UVM environment for verifying the Instruction Fetch stage.
//   Verifies normal PC progression, stalls, branch redirection, jump redirection,
//   exception redirection, and instruction fetch alignment checks.
// =============================================================================

package mips_if_stage_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // =========================================================================
    // 1. Transaction Item
    // =========================================================================
    class mips_if_stage_item extends uvm_sequence_item;
        // Inputs to DUT
        rand bit        stall;
        rand bit        branch_taken;
        rand bit [31:0] branch_target;
        rand bit        jump_taken;
        rand bit [31:0] jump_target;
        rand bit        exception_req;
        rand bit [31:0] exception_vector;

        // Outputs from DUT
        bit [31:0] inst_addr;
        bit [31:0] pc;
        bit [31:0] pc_plus_4;
        bit        adel_exception;

        `uvm_object_utils_begin(mips_if_stage_item)
            `uvm_field_int(stall, UVM_ALL_ON)
            `uvm_field_int(branch_taken, UVM_ALL_ON)
            `uvm_field_int(branch_target, UVM_ALL_ON)
            `uvm_field_int(jump_taken, UVM_ALL_ON)
            `uvm_field_int(jump_target, UVM_ALL_ON)
            `uvm_field_int(exception_req, UVM_ALL_ON)
            `uvm_field_int(exception_vector, UVM_ALL_ON)
            `uvm_field_int(inst_addr, UVM_ALL_ON)
            `uvm_field_int(pc, UVM_ALL_ON)
            `uvm_field_int(pc_plus_4, UVM_ALL_ON)
            `uvm_field_int(adel_exception, UVM_ALL_ON)
        `uvm_object_utils_end

        // Constraints to generate realistic scenarios (e.g. alignment errors occasionally)
        constraint c_targets {
            // Keep targets word-aligned 90% of the time, unaligned 10%
            branch_target[1:0] dist { 2'b00 := 90, [2'b01 : 2'b11] := 10 };
            jump_target[1:0]   dist { 2'b00 := 90, [2'b01 : 2'b11] := 10 };
            exception_vector[1:0] dist { 2'b00 := 95, [2'b01 : 2'b11] := 5 };
        }

        constraint c_priorities {
            // Distribute stall, branch, jump, exceptions
            exception_req dist { 1 := 5, 0 := 95 };
            branch_taken  dist { 1 := 15, 0 := 85 };
            jump_taken    dist { 1 := 10, 0 := 90 };
            stall         dist { 1 := 10, 0 := 90 };
        }

        function new(string name = "mips_if_stage_item");
            super.new(name);
        endfunction
    endclass

    // =========================================================================
    // 2. Driver
    // =========================================================================
    class mips_if_stage_driver extends uvm_driver #(mips_if_stage_item);
        `uvm_component_utils(mips_if_stage_driver)
        virtual mips_if_stage_if vif;

        function new(string name = "mips_if_stage_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_if_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("DRV", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            // Reset state
            vif.drv_cb.stall            <= 1'b0;
            vif.drv_cb.branch_taken     <= 1'b0;
            vif.drv_cb.branch_target    <= 32'd0;
            vif.drv_cb.jump_taken       <= 1'b0;
            vif.drv_cb.jump_target      <= 32'd0;
            vif.drv_cb.exception_req    <= 1'b0;
            vif.drv_cb.exception_vector <= 32'd0;
            
            @(posedge vif.rst_n);
            
            forever begin
                seq_item_port.get_next_item(req);
                drive_item(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_item(mips_if_stage_item item);
            @(vif.drv_cb);
            vif.drv_cb.stall            <= item.stall;
            vif.drv_cb.branch_taken     <= item.branch_taken;
            vif.drv_cb.branch_target    <= item.branch_target;
            vif.drv_cb.jump_taken       <= item.jump_taken;
            vif.drv_cb.jump_target      <= item.jump_target;
            vif.drv_cb.exception_req    <= item.exception_req;
            vif.drv_cb.exception_vector <= item.exception_vector;
        endtask
    endclass

    // =========================================================================
    // 3. Monitor
    // =========================================================================
    class mips_if_stage_monitor extends uvm_monitor;
        `uvm_component_utils(mips_if_stage_monitor)
        virtual mips_if_stage_if vif;
        uvm_analysis_port #(mips_if_stage_item) ap;

        function new(string name = "mips_if_stage_monitor", uvm_component parent = null);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_if_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("MON", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            mips_if_stage_item item;
            @(posedge vif.rst_n);
            forever begin
                @(vif.mon_cb);
                item = mips_if_stage_item::type_id::create("item");
                item.stall            = vif.mon_cb.stall;
                item.branch_taken     = vif.mon_cb.branch_taken;
                item.branch_target    = vif.mon_cb.branch_target;
                item.jump_taken       = vif.mon_cb.jump_taken;
                item.jump_target      = vif.mon_cb.jump_target;
                item.exception_req    = vif.mon_cb.exception_req;
                item.exception_vector = vif.mon_cb.exception_vector;
                
                item.inst_addr        = vif.mon_cb.inst_addr;
                item.pc               = vif.mon_cb.pc;
                item.pc_plus_4        = vif.mon_cb.pc_plus_4;
                item.adel_exception   = vif.mon_cb.adel_exception;
                
                ap.write(item);
            end
        endtask
    endclass

    // =========================================================================
    // 4. Scoreboard (Reference Model & Verification)
    // =========================================================================
    class mips_if_stage_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(mips_if_stage_scoreboard)
        uvm_analysis_imp #(mips_if_stage_item, mips_if_stage_scoreboard) item_collected_export;

        // Golden model Program Counter tracker
        reg [31:0] ref_pc;

        int match_cnt;
        int error_cnt;

        function new(string name = "mips_if_stage_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
            ref_pc = 32'h0000_0000; // Reset address
            match_cnt = 0;
            error_cnt = 0;
        endfunction

        virtual function void write(mips_if_stage_item item);
            bit [31:0] exp_pc = ref_pc;
            bit [31:0] exp_pc_plus_4 = ref_pc + 32'd4;
            bit        exp_adel = (ref_pc[1:0] != 2'b00);

            bit miscompare = 0;
            string errmsg = "";

            if (item.pc !== exp_pc) begin miscompare = 1; errmsg = {errmsg, $sformatf("pc mismatch: exp=0x%h, act=0x%h; ", exp_pc, item.pc)}; end
            if (item.inst_addr !== exp_pc) begin miscompare = 1; errmsg = {errmsg, $sformatf("inst_addr mismatch: exp=0x%h, act=0x%h; ", exp_pc, item.inst_addr)}; end
            if (item.pc_plus_4 !== exp_pc_plus_4) begin miscompare = 1; errmsg = {errmsg, $sformatf("pc_plus_4 mismatch: exp=0x%h, act=0x%h; ", exp_pc_plus_4, item.pc_plus_4)}; end
            if (item.adel_exception !== exp_adel) begin miscompare = 1; errmsg = {errmsg, $sformatf("adel_exception mismatch: exp=%b, act=%b; ", exp_adel, item.adel_exception)}; end

            if (miscompare) begin
                `uvm_error("SB_IF_ERR", $sformatf("IF Stage Miscompare at current PC=0x%h! %s", ref_pc, errmsg))
                error_cnt++;
            end else begin
                match_cnt++;
            end

            // Compute next ref_pc based on inputs in this cycle (effects take place at next clock edge)
            if (item.exception_req) begin
                ref_pc = item.exception_vector;
            end else if (item.branch_taken) begin
                ref_pc = item.branch_target;
            end else if (item.jump_taken) begin
                ref_pc = item.jump_target;
            end else if (item.stall) begin
                ref_pc = ref_pc;
            end else begin
                ref_pc = ref_pc + 32'd4;
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SB_IF_REPORT", $sformatf("IF Scoreboard finished. Matches: %0d, Errors: %0d", match_cnt, error_cnt), UVM_NONE)
            if (error_cnt > 0) begin
                `uvm_fatal("SB_IF_FAIL", "Verification failed due to IF scoreboard errors!")
            end
        endfunction
    endclass

    // =========================================================================
    // 5. Agent
    // =========================================================================
    class mips_if_stage_agent extends uvm_agent;
        `uvm_component_utils(mips_if_stage_agent)

        mips_if_stage_driver    driver;
        mips_if_stage_monitor   monitor;
        uvm_sequencer #(mips_if_stage_item) sequencer;

        function new(string name = "mips_if_stage_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = mips_if_stage_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver = mips_if_stage_driver::type_id::create("driver", this);
                sequencer = uvm_sequencer#(mips_if_stage_item)::type_id::create("sequencer", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass

    // =========================================================================
    // 6. Environment
    // =========================================================================
    class mips_if_stage_env extends uvm_env;
        `uvm_component_utils(mips_if_stage_env)

        mips_if_stage_agent      agent;
        mips_if_stage_scoreboard scoreboard;

        function new(string name = "mips_if_stage_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = mips_if_stage_agent::type_id::create("agent", this);
            scoreboard = mips_if_stage_scoreboard::type_id::create("scoreboard", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.item_collected_export);
        endfunction
    endclass

    // =========================================================================
    // 7. Test Sequences
    // =========================================================================
    class mips_if_stage_base_seq extends uvm_sequence #(mips_if_stage_item);
        `uvm_object_utils(mips_if_stage_base_seq)

        function new(string name = "mips_if_stage_base_seq");
            super.new(name);
        endfunction
    endclass

    class if_rand_seq extends mips_if_stage_base_seq;
        `uvm_object_utils(if_rand_seq)
        
        int num_items = 5000;

        function new(string name = "if_rand_seq");
            super.new(name);
        endfunction

        virtual task body();
            repeat (num_items) begin
                req = mips_if_stage_item::type_id::create("req");
                start_item(req);
                if (!req.randomize()) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);
            end
        endtask
    endclass

    // =========================================================================
    // 8. Test Cases
    // =========================================================================
    class mips_if_stage_base_test extends uvm_test;
        `uvm_component_utils(mips_if_stage_base_test)

        mips_if_stage_env env;

        function new(string name = "mips_if_stage_base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = mips_if_stage_env::type_id::create("env", this);
        endfunction

        virtual function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_top.print();
        endfunction
    endclass

    class if_test extends mips_if_stage_base_test;
        `uvm_component_utils(if_test)

        function new(string name = "if_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            if_rand_seq seq = if_rand_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
