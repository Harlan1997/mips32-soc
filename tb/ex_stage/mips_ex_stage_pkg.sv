// =============================================================================
// File Name: mips_ex_stage_pkg.sv
// Design:    MIPS32 EX Stage UVM Verification Package
// Author:    Antigravity
// Description:
//   Contains the complete UVM environment including transaction item,
//   driver, monitor, agent, scoreboard, sequences, and tests.
// =============================================================================

package mips_ex_stage_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef bit [63:0] u64_t;

    // =========================================================================
    // 1. Transaction Item
    // =========================================================================
    class mips_ex_stage_item extends uvm_sequence_item;
        // Control / Inputs
        rand bit [31:0] op_a;
        rand bit [31:0] op_b;
        rand bit [4:0]  sa;
        rand bit [3:0]  alu_op;
        rand bit [2:0]  mdu_op;
        rand bit        mdu_start;
        rand bit        sel_mdu_out;

        // Outputs
        bit [31:0] ex_out;
        bit        overflow;
        bit        zero;
        bit        mdu_ready;
        bit [31:0] hi_val;
        bit [31:0] lo_val;

        `uvm_object_utils_begin(mips_ex_stage_item)
            `uvm_field_int(op_a, UVM_ALL_ON)
            `uvm_field_int(op_b, UVM_ALL_ON)
            `uvm_field_int(sa, UVM_ALL_ON)
            `uvm_field_int(alu_op, UVM_ALL_ON)
            `uvm_field_int(mdu_op, UVM_ALL_ON)
            `uvm_field_int(mdu_start, UVM_ALL_ON)
            `uvm_field_int(sel_mdu_out, UVM_ALL_ON)
            `uvm_field_int(ex_out, UVM_ALL_ON)
            `uvm_field_int(overflow, UVM_ALL_ON)
            `uvm_field_int(zero, UVM_ALL_ON)
            `uvm_field_int(mdu_ready, UVM_ALL_ON)
            `uvm_field_int(hi_val, UVM_ALL_ON)
            `uvm_field_int(lo_val, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "mips_ex_stage_item");
            super.new(name);
        endfunction
    endclass

    // =========================================================================
    // 2. Driver
    // =========================================================================
    class mips_ex_stage_driver extends uvm_driver #(mips_ex_stage_item);
        `uvm_component_utils(mips_ex_stage_driver)
        virtual mips_ex_stage_if vif;

        function new(string name = "mips_ex_stage_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_ex_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("DRV", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            // Reset state
            vif.drv_cb.op_a        <= 32'd0;
            vif.drv_cb.op_b        <= 32'd0;
            vif.drv_cb.sa          <= 5'd0;
            vif.drv_cb.alu_op      <= 4'd0;
            vif.drv_cb.mdu_op      <= 3'd0;
            vif.drv_cb.mdu_start   <= 1'b0;
            vif.drv_cb.sel_mdu_out <= 1'b0;
            @(posedge vif.rst_n);
            
            forever begin
                seq_item_port.get_next_item(req);
                drive_item(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_item(mips_ex_stage_item item);
            @(vif.drv_cb);
            vif.drv_cb.op_a        <= item.op_a;
            vif.drv_cb.op_b        <= item.op_b;
            vif.drv_cb.sa          <= item.sa;
            vif.drv_cb.alu_op      <= item.alu_op;
            vif.drv_cb.mdu_op      <= item.mdu_op;
            vif.drv_cb.mdu_start   <= item.mdu_start;
            vif.drv_cb.sel_mdu_out <= item.sel_mdu_out;

            // Wait for multi-cycle operations to finish
            if (item.mdu_start && (item.mdu_op == 3'b000 || item.mdu_op == 3'b001 || item.mdu_op == 3'b010 || item.mdu_op == 3'b011)) begin
                // Hold mdu_start for exactly 1 cycle
                @(vif.drv_cb);
                vif.drv_cb.mdu_start <= 1'b0;
                
                // Wait for the MDU to enter the busy state (ready goes low)
                while (vif.drv_cb.mdu_ready === 1'b1) begin
                    @(vif.drv_cb);
                end
                
                // Wait for the MDU to finish (ready goes high)
                while (vif.drv_cb.mdu_ready === 1'b0) begin
                    @(vif.drv_cb);
                end
            end
        endtask
    endclass

    // =========================================================================
    // 3. Monitor
    // =========================================================================
    class mips_ex_stage_monitor extends uvm_monitor;
        `uvm_component_utils(mips_ex_stage_monitor)
        virtual mips_ex_stage_if vif;
        uvm_analysis_port #(mips_ex_stage_item) ap;

        function new(string name = "mips_ex_stage_monitor", uvm_component parent = null);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual mips_ex_stage_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("MON", "Could not get virtual interface vif")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            mips_ex_stage_item item;
            @(posedge vif.rst_n);
            forever begin
                @(vif.mon_cb);
                item = mips_ex_stage_item::type_id::create("item");
                item.op_a        = vif.mon_cb.op_a;
                item.op_b        = vif.mon_cb.op_b;
                item.sa          = vif.mon_cb.sa;
                item.alu_op      = vif.mon_cb.alu_op;
                item.mdu_op      = vif.mon_cb.mdu_op;
                item.mdu_start   = vif.mon_cb.mdu_start;
                item.sel_mdu_out = vif.mon_cb.sel_mdu_out;
                item.ex_out      = vif.mon_cb.ex_out;
                item.overflow    = vif.mon_cb.overflow;
                item.zero        = vif.mon_cb.zero;
                item.mdu_ready   = vif.mon_cb.mdu_ready;
                item.hi_val      = vif.mon_cb.hi_val;
                item.lo_val      = vif.mon_cb.lo_val;
                ap.write(item);
            end
        endtask
    endclass

    // =========================================================================
    // 4. Scoreboard (Reference Model & Checker)
    // =========================================================================
    class mips_ex_stage_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(mips_ex_stage_scoreboard)
        uvm_analysis_imp #(mips_ex_stage_item, mips_ex_stage_scoreboard) item_collected_export;

        // Internal reference states
        reg [31:0] ref_hi;
        reg [31:0] ref_lo;

        // Scoreboard FSM for multi-cycle checks
        typedef enum {SB_IDLE, SB_BUSY} sb_state_t;
        sb_state_t state;
        
        reg [31:0] exp_hi;
        reg [31:0] exp_lo;
        
        reg [31:0] mdu_start_op_a;
        reg [31:0] mdu_start_op_b;
        reg [2:0]  mdu_start_op;

        int match_cnt;
        int error_cnt;

        function new(string name = "mips_ex_stage_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
            ref_hi = 32'd0;
            ref_lo = 32'd0;
            state = SB_IDLE;
            match_cnt = 0;
            error_cnt = 0;
        endfunction

        // Prediction helper for ALU
        function void predict_alu(
            input [31:0] op_a,
            input [31:0] op_b,
            input [4:0]  sa,
            input [3:0]  alu_op,
            output [31:0] out,
            output        ov,
            output        z
        );
            reg [32:0] temp_sum;
            reg [31:0] res;
            bit sign_a, sign_b, sign_r;

            sign_a = op_a[31];
            sign_b = op_b[31];

            case (alu_op)
                4'b0000: begin // ADD
                    temp_sum = {op_a[31], op_a} + {op_b[31], op_b};
                    res = temp_sum[31:0];
                    sign_r = res[31];
                    ov = ((sign_a == sign_b) && (sign_r != sign_a));
                end
                4'b0001: begin // ADDU
                    res = op_a + op_b;
                    ov = 0;
                end
                4'b0010: begin // SUB
                    temp_sum = {op_a[31], op_a} - {op_b[31], op_b};
                    res = temp_sum[31:0];
                    sign_r = res[31];
                    ov = ((sign_a != sign_b) && (sign_r != sign_a));
                end
                4'b0011: begin // SUBU
                    res = op_a - op_b;
                    ov = 0;
                end
                4'b0100: begin // AND
                    res = op_a & op_b;
                    ov = 0;
                end
                4'b0101: begin // OR
                    res = op_a | op_b;
                    ov = 0;
                end
                4'b0110: begin // XOR
                    res = op_a ^ op_b;
                    ov = 0;
                end
                4'b0111: begin // NOR
                    res = ~(op_a | op_b);
                    ov = 0;
                end
                4'b1000: begin // SLL
                    res = op_b << sa;
                    ov = 0;
                end
                4'b1001: begin // SRL
                    res = op_b >> sa;
                    ov = 0;
                end
                4'b1010: begin // SRA
                    res = $signed(op_b) >>> sa;
                    ov = 0;
                end
                4'b1011: begin // SLT
                    if (sign_a != sign_b) begin
                        res = {31'd0, sign_a};
                    end else begin
                        temp_sum = {op_a[31], op_a} - {op_b[31], op_b};
                        res = {31'd0, temp_sum[31]};
                    end
                    ov = 0;
                end
                4'b1100: begin // SLTU
                    res = (op_a < op_b) ? 32'd1 : 32'd0;
                    ov = 0;
                end
                4'b1101: begin // LUI
                    res = {op_b[15:0], 16'd0};
                    ov = 0;
                end
                default: begin
                    res = 32'd0;
                    ov = 0;
                end
            endcase

            out = res;
            z = (res == 32'd0);
        endfunction

        // Analysis implementation port write function
        virtual function void write(mips_ex_stage_item item);
            bit [31:0] exp_alu_out;
            bit exp_overflow;
            bit exp_zero;

            // 1. Process MDU completion if busy and ready
            if (state == SB_BUSY && item.mdu_ready) begin
                // Operation complete! Check results
                if (item.hi_val !== exp_hi || item.lo_val !== exp_lo) begin
                    `uvm_error("SB_MDU_ERR", $sformatf("MDU Miscompare! Op=%0d, A=0x%h, B=0x%h. Expected: HI=0x%h, LO=0x%h. Actual: HI=0x%h, LO=0x%h", mdu_start_op, mdu_start_op_a, mdu_start_op_b, exp_hi, exp_lo, item.hi_val, item.lo_val))
                    error_cnt++;
                end else begin
                    `uvm_info("SB_MDU_OK", $sformatf("MDU Match: HI=0x%h, LO=0x%h", item.hi_val, item.lo_val), UVM_HIGH)
                    match_cnt++;
                end
                ref_hi = exp_hi;
                ref_lo = exp_lo;
                state = SB_IDLE;
            end

            // 2. Process MDU start / single-cycle write if idle
            if (state == SB_IDLE) begin
                if (item.mdu_start) begin
                    mdu_start_op_a = item.op_a;
                    mdu_start_op_b = item.op_b;
                    mdu_start_op   = item.mdu_op;
                    case (item.mdu_op)
                        3'b000: begin // MULT (Signed)
                            longint prod = $signed(item.op_a) * $signed(item.op_b);
                            exp_hi = prod[63:32];
                            exp_lo = prod[31:0];
                            state = SB_BUSY;
                        end
                        3'b001: begin // MULTU (Unsigned)
                            u64_t prod = u64_t'(item.op_a) * u64_t'(item.op_b);
                            exp_hi = prod[63:32];
                            exp_lo = prod[31:0];
                            state = SB_BUSY;
                        end
                        3'b010: begin // DIV (Signed)
                            if (item.op_b == 32'd0) begin
                                exp_hi = 32'd0;
                                exp_lo = 32'd0;
                            end else if (item.op_a == 32'h8000_0000 && item.op_b == 32'hffff_ffff) begin
                                exp_hi = 32'd0;
                                exp_lo = 32'h8000_0000;
                            end else begin
                                exp_lo = $signed(item.op_a) / $signed(item.op_b);
                                exp_hi = $signed(item.op_a) % $signed(item.op_b);
                            end
                            state = SB_BUSY;
                        end
                        3'b011: begin // DIVU (Unsigned)
                            if (item.op_b == 32'd0) begin
                                exp_hi = 32'd0;
                                exp_lo = 32'd0;
                            end else begin
                                exp_lo = item.op_a / item.op_b;
                                exp_hi = item.op_a % item.op_b;
                            end
                            state = SB_BUSY;
                        end
                        default: ;
                    endcase
                end else begin
                    // Single cycle register writes
                    if (item.mdu_op == 3'b100) begin // MTHI
                        ref_hi = item.op_a;
                    end else if (item.mdu_op == 3'b101) begin // MTLO
                        ref_lo = item.op_a;
                    end
                end
            end

            // 2. Check outputs during non-busy times or combinational checks
            // Compare output results
            if (item.sel_mdu_out) begin
                // Select MDU out (MFHI / MFLO)
                if (item.mdu_op == 3'b110) begin // MFHI
                    if (item.ex_out !== ref_hi) begin
                        `uvm_error("SB_ERR", $sformatf("MFHI Miscompare! Expected: 0x%h, Actual: 0x%h", ref_hi, item.ex_out))
                        error_cnt++;
                    end else begin
                        match_cnt++;
                    end
                end else if (item.mdu_op == 3'b111) begin // MFLO
                    if (item.ex_out !== ref_lo) begin
                        `uvm_error("SB_ERR", $sformatf("MFLO Miscompare! Expected: 0x%h, Actual: 0x%h", ref_lo, item.ex_out))
                        error_cnt++;
                    end else begin
                        match_cnt++;
                    end
                end
            end else begin
                // Select ALU out
                predict_alu(item.op_a, item.op_b, item.sa, item.alu_op, exp_alu_out, exp_overflow, exp_zero);
                if (item.ex_out !== exp_alu_out || item.overflow !== exp_overflow || item.zero !== exp_zero) begin
                    `uvm_error("SB_ALU_ERR", $sformatf("ALU Miscompare! Op: %0d, A: 0x%h, B: 0x%h, SA: %0d. Expected: Out=0x%h, Ov=%b, Z=%b. Actual: Out=0x%h, Ov=%b, Z=%b", 
                        item.alu_op, item.op_a, item.op_b, item.sa, exp_alu_out, exp_overflow, exp_zero, item.ex_out, item.overflow, item.zero))
                    error_cnt++;
                end else begin
                    match_cnt++;
                end
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SB_REPORT", $sformatf("Scoreboard verification finished. Total Matches: %0d, Total Errors: %0d", match_cnt, error_cnt), UVM_NONE)
            if (error_cnt > 0) begin
                `uvm_fatal("SB_FAIL", "Verification failed due to scoreboard errors!")
            end
        endfunction
    endclass

    // =========================================================================
    // 5. Agent
    // =========================================================================
    class mips_ex_stage_agent extends uvm_agent;
        `uvm_component_utils(mips_ex_stage_agent)
        
        mips_ex_stage_driver    driver;
        mips_ex_stage_monitor   monitor;
        uvm_sequencer #(mips_ex_stage_item) sequencer;

        function new(string name = "mips_ex_stage_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = mips_ex_stage_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver = mips_ex_stage_driver::type_id::create("driver", this);
                sequencer = uvm_sequencer#(mips_ex_stage_item)::type_id::create("sequencer", this);
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
    class mips_ex_stage_env extends uvm_env;
        `uvm_component_utils(mips_ex_stage_env)

        mips_ex_stage_agent      agent;
        mips_ex_stage_scoreboard scoreboard;

        function new(string name = "mips_ex_stage_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = mips_ex_stage_agent::type_id::create("agent", this);
            scoreboard = mips_ex_stage_scoreboard::type_id::create("scoreboard", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.item_collected_export);
        endfunction
    endclass

    // =========================================================================
    // 7. Base Sequence & Custom Test Sequences
    // =========================================================================
    class mips_ex_stage_base_seq extends uvm_sequence #(mips_ex_stage_item);
        `uvm_object_utils(mips_ex_stage_base_seq)

        function new(string name = "mips_ex_stage_base_seq");
            super.new(name);
        endfunction
    endclass

    // Sequence 1: Pure ALU random tests
    class alu_rand_seq extends mips_ex_stage_base_seq;
        `uvm_object_utils(alu_rand_seq)
        
        int num_items = 200;

        function new(string name = "alu_rand_seq");
            super.new(name);
        endfunction

        virtual task body();
            repeat (num_items) begin
                req = mips_ex_stage_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with {
                    mdu_start   == 1'b0;
                    sel_mdu_out == 1'b0;
                    alu_op inside {[4'b0000 : 4'b1101]};
                }) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);
            end
        endtask
    endclass

    // Sequence 2: Pure MDU random tests
    class mdu_rand_seq extends mips_ex_stage_base_seq;
        `uvm_object_utils(mdu_rand_seq)

        int num_items = 100;

        function new(string name = "mdu_rand_seq");
            super.new(name);
        endfunction

        virtual task body();
            repeat (num_items) begin
                // Drive MTLO/MTHI or MULT/DIV
                req = mips_ex_stage_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with {
                    mdu_op inside {[3'b000 : 3'b101]}; // MULT, MULTU, DIV, DIVU, MTHI, MTLO
                    mdu_start   == (mdu_op inside {3'b000, 3'b001, 3'b010, 3'b011});
                    sel_mdu_out == 1'b0;
                }) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);

                // Add a read back operation (MFHI or MFLO)
                req = mips_ex_stage_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with {
                    mdu_op      inside {3'b110, 3'b111}; // MFHI, MFLO
                    mdu_start   == 1'b0;
                    sel_mdu_out == 1'b1;
                }) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);
            end
        endtask
    endclass

    // Sequence 3: Mixed ALU & MDU tests (including edge cases)
    class mixed_rand_seq extends mips_ex_stage_base_seq;
        `uvm_object_utils(mixed_rand_seq)

        int num_items = 300;

        function new(string name = "mixed_rand_seq");
            super.new(name);
        endfunction

        virtual task body();
            repeat (num_items) begin
                req = mips_ex_stage_item::type_id::create("req");
                start_item(req);
                // Interleave ALU/MDU randomly with edge-case values for op_a/op_b
                if (!req.randomize() with {
                    op_a inside {32'd0, 32'd1, 32'hffff_ffff, 32'h8000_0000, 32'h7fff_ffff, [32'h0000_0002:32'hffff_ffff]};
                    op_b inside {32'd0, 32'd1, 32'hffff_ffff, 32'h8000_0000, 32'h7fff_ffff, [32'h0000_0002:32'hffff_ffff]};
                    mdu_op inside {[3'b000 : 3'b111]};
                    alu_op inside {[4'b0000 : 4'b1101]};
                    
                    // If MDU op is mult/div, start it
                    mdu_start   == (mdu_op inside {3'b000, 3'b001, 3'b010, 3'b011});
                    
                    // If read command from MDU, select it, else select ALU
                    sel_mdu_out == (mdu_op inside {3'b110, 3'b111});
                }) begin
                    `uvm_fatal("SEQ", "Randomization failed")
                end
                finish_item(req);
            end
        endtask
    endclass

    // =========================================================================
    // 8. Test Cases
    // =========================================================================
    class mips_ex_stage_base_test extends uvm_test;
        `uvm_component_utils(mips_ex_stage_base_test)

        mips_ex_stage_env env;

        function new(string name = "mips_ex_stage_base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = mips_ex_stage_env::type_id::create("env", this);
        endfunction

        virtual function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_top.print();
        endfunction
    endclass

    // Test 1: Random ALU execution
    class alu_test extends mips_ex_stage_base_test;
        `uvm_component_utils(alu_test)

        function new(string name = "alu_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            alu_rand_seq seq = alu_rand_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 2: Random MDU execution
    class mdu_test extends mips_ex_stage_base_test;
        `uvm_component_utils(mdu_test)

        function new(string name = "mdu_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            mdu_rand_seq seq = mdu_rand_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 3: Mixed execution (stress test)
    class mixed_test extends mips_ex_stage_base_test;
        `uvm_component_utils(mixed_test)

        function new(string name = "mixed_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual task run_phase(uvm_phase phase);
            mixed_rand_seq seq = mixed_rand_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
