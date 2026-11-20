`timescale 1ns/1ps

// Directed negative coverage for the D-side BadVAddr owner token.  The test
// drives the owner metadata at the CPU boundary and verifies that every
// architectural flush boundary clears a live token before a later WB bundle
// can consume it.
module tb_mips_cpu_badvaddr_owner_context;
    reg clk, rst_n;
    reg ctx_restore_req;
    reg [31:0] imem [0:255];
    reg [31:0] fetch_addr_q;
    integer i;
    integer failures;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, inst_rdata;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0] data_req_id, data_be;
    wire [3:0] data_resp_id = 4'd0;
    wire inst_addr_ok = 1'b1, inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0, inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1, data_data_ok = 1'b1;
    wire data_bus_error = 1'b0, data_cache_error = 1'b0;
    wire data_cache_op_done = 1'b0, data_cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire data_cache_op_valid;
    wire [4:0] data_cache_op;
    wire [31:0] data_cache_op_addr;
    wire data_cache_op_is_icache;
    wire [31:0] data_cache_tag_wdata;

    assign inst_rdata = imem[fetch_addr_q[9:2]];
    assign data_rdata = 32'h1234_5678;

    mips_cpu u_cpu (
        .clk(clk), .rst_n(rst_n), .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
        .inst_bus_error(inst_bus_error), .inst_cache_error(inst_cache_error),
        .inst_rdata(inst_rdata), .data_req(data_req), .data_req_id(data_req_id),
        .data_we(data_we), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_be(data_be), .data_uncacheable(), .data_atomic(),
        .data_cache_op_valid(data_cache_op_valid), .data_cache_op(data_cache_op),
        .data_cache_op_addr(data_cache_op_addr),
        .data_cache_op_is_icache(data_cache_op_is_icache),
        .data_cache_op_done(data_cache_op_done), .data_cache_op_error(data_cache_op_error),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok),
        .data_resp_id(data_resp_id), .data_bus_error(data_bus_error),
        .data_cache_error(data_cache_error), .data_cache_tag_rdata(data_cache_tag_rdata),
        .data_cache_tag_wdata(data_cache_tag_wdata), .data_rdata(data_rdata),
        .ext_int(6'd0), .tlb_inv_en(1'b0), .tlb_inv_vpn2(19'd0),
        .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0), .tlb_inv_wired_floor(6'd0),
        .sim_exception_req(1'b0), .sim_exception_code(5'd0),
        .external_vec_id(8'd0), .coh_snoop_valid(1'b0), .coh_snoop_addr(32'd0),
        .ctx_save_req(1'b0), .ctx_save_done(), .ctx_save_pc(), .ctx_save_status(),
        .ctx_save_asid(), .ctx_save_ptebase(), .ctx_save_srsctl(),
        .ctx_save_userlocal(), .ctx_save_gpr(), .ctx_save_srs_gpr(),
        .ctx_save_fpr(), .ctx_save_fpr_hi(), .ctx_save_fcsr(),
        .ctx_restore_req(ctx_restore_req), .ctx_restore_pc(32'd0),
        .ctx_restore_status(32'd0), .ctx_restore_asid(8'd0),
        .ctx_restore_ptebase(32'd0), .ctx_restore_ptebase_valid(1'b0),
        .ctx_restore_srsctl(32'd0), .ctx_restore_userlocal(32'd0),
        .ctx_restore_gpr(1024'd0), .ctx_restore_srs_gpr(16384'd0),
        .ctx_restore_set(4'd0), .ctx_restore_fpr(1024'd0),
        .ctx_restore_fpr_hi(1024'd0), .ctx_restore_fcsr(32'd0),
        .ctx_restore_ack(), .hardware_walker_enable(1'b0),
        .hardware_walker_ptbr(32'd0), .ptw_mem_valid(), .ptw_mem_addr(),
        .ptw_mem_write_valid(), .ptw_mem_write_addr(), .ptw_mem_write_data(),
        .ptw_mem_ready(1'b0), .ptw_mem_rdata(32'd0), .ptw_mem_error(1'b0),
        .ptw_mem_write_ready(1'b0), .ptw_mem_write_error(1'b0),
        .ptw_fault_valid(), .ptw_fault_code(), .tlb_inv_applied(),
        .debug_stall(debug_stall), .debug_flush(debug_flush),
        .perf_cycle_count(), .perf_retire_count(), .perf_icache_miss_count(),
        .perf_dcache_miss_count(), .perf_branch_mispredict_count(),
        .perf_mdu_stall_count(), .inst_flush());

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fetch_addr_q <= 32'd0;
        else
            fetch_addr_q <= inst_addr;
    end

    task automatic fail(input [1023:0] message);
        begin
            failures = failures + 1;
            $display("BADVADDR_OWNER_CONTEXT_FAIL %0s", message);
        end
    endtask

    task automatic capture_owner;
        begin
            // Keep all unrelated WB/flush inputs inert while the owner token
            // is captured. These are hierarchical forces by design: this
            // test targets the token state machine, not MMU page-table policy.
            force u_cpu.dmem_translation_fault = 1'b1;
            force u_cpu.exception_flush = 1'b0;
            force u_cpu.wb_except_req = 1'b0;
            force u_cpu.wb_arch_valid = 1'b0;
            force u_cpu.mem_pc = 32'h8000_1000;
            force u_cpu.mem_inst = 32'h8c22_0040;
            force u_cpu.mem_access_addr = 32'h0040_2040;
            force u_cpu.d_fault_capture_code = 5'h02;
            force u_cpu.mem_mem_write = 1'b0;
            force u_cpu.cp0_asid = 8'h2a;
            @(posedge clk);
            #1;
            if (!u_cpu.d_fault_vaddr_pending_q)
                fail("fault owner was not captured");
            release u_cpu.dmem_translation_fault;
            release u_cpu.exception_flush;
            release u_cpu.wb_except_req;
            release u_cpu.wb_arch_valid;
            release u_cpu.mem_pc;
            release u_cpu.mem_inst;
            release u_cpu.mem_access_addr;
            release u_cpu.d_fault_capture_code;
            release u_cpu.mem_mem_write;
            release u_cpu.cp0_asid;
        end
    endtask

    task automatic require_clear(input [1023:0] reason);
        begin
            #1;
            if (u_cpu.d_fault_vaddr_pending_q !== 1'b0)
                fail(reason);
        end
    endtask

    task automatic capture_unaligned_owner;
        begin
            // The MMU sees an aligned word beat, and LUXC1/SUXC1 ignore the
            // low three effective-address bits before forming that access.
            force u_cpu.dmem_translation_fault = 1'b1;
            force u_cpu.exception_flush = 1'b0;
            force u_cpu.wb_except_req = 1'b0;
            force u_cpu.wb_arch_valid = 1'b0;
            force u_cpu.mem_pc = 32'h8000_2000;
            force u_cpu.mem_inst = 32'h4c83_0005; // COP1X LUXC1-shaped word
            force u_cpu.mem_unaligned_double_mem = 1'b1;
            force u_cpu.mem_ex_out = 32'h0040_2041;
            force u_cpu.mem_access_addr = 32'h0040_2048;
            force u_cpu.d_fault_capture_code = 5'h02;
            force u_cpu.mem_mem_write = 1'b0;
            force u_cpu.cp0_asid = 8'h2b;
            @(posedge clk);
            #1;
            if (!u_cpu.d_fault_vaddr_pending_q)
                fail("unaligned fault owner was not captured");
            if (u_cpu.d_fault_vaddr_q !== 32'h0040_2040)
                fail("COP1X fault owner did not retain the aligned effective address");
            release u_cpu.dmem_translation_fault;
            release u_cpu.exception_flush;
            release u_cpu.wb_except_req;
            release u_cpu.wb_arch_valid;
            release u_cpu.mem_pc;
            release u_cpu.mem_inst;
            release u_cpu.mem_unaligned_double_mem;
            release u_cpu.mem_ex_out;
            release u_cpu.mem_access_addr;
            release u_cpu.d_fault_capture_code;
            release u_cpu.mem_mem_write;
            release u_cpu.cp0_asid;

            // Clear the first token before starting the independent phase-1
            // fault case.
            ctx_restore_req = 1'b1;
            @(posedge clk);
            #1;
            ctx_restore_req = 1'b0;

            // A fault on the second aligned COP1X beat belongs to the next
            // virtual page.  BadVAddr must follow the phase-specific address
            // used by the MMU rather than the operation's aligned base.
            force u_cpu.dmem_translation_fault = 1'b1;
            force u_cpu.exception_flush = 1'b0;
            force u_cpu.wb_except_req = 1'b0;
            force u_cpu.wb_arch_valid = 1'b0;
            force u_cpu.mem_pc = 32'h8000_2000;
            force u_cpu.mem_inst = 32'h4c83_0005;
            force u_cpu.mem_unaligned_double_mem = 1'b1;
            force u_cpu.mem_double_phase = 2'd1;
            force u_cpu.mem_double_base_addr = 32'h0040_2ffc;
            force u_cpu.mem_access_addr = 32'h0040_3000;
            force u_cpu.d_fault_capture_code = 5'h02;
            force u_cpu.mem_mem_write = 1'b0;
            force u_cpu.cp0_asid = 8'h2b;
            @(posedge clk);
            #1;
            if (!u_cpu.d_fault_vaddr_pending_q)
                fail("second-beat COP1X fault owner was not captured");
            if (u_cpu.d_fault_vaddr_q !== 32'h0040_3000)
                fail("COP1X second-beat fault owner did not retain phase address");
            release u_cpu.dmem_translation_fault;
            release u_cpu.exception_flush;
            release u_cpu.wb_except_req;
            release u_cpu.wb_arch_valid;
            release u_cpu.mem_pc;
            release u_cpu.mem_inst;
            release u_cpu.mem_unaligned_double_mem;
            release u_cpu.mem_double_phase;
            release u_cpu.mem_double_base_addr;
            release u_cpu.mem_access_addr;
            release u_cpu.d_fault_capture_code;
            release u_cpu.mem_mem_write;
            release u_cpu.cp0_asid;
            ctx_restore_req = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            if (u_cpu.d_fault_vaddr_pending_q !== 1'b0)
                fail("unaligned owner survived cleanup");
            ctx_restore_req = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ctx_restore_req = 1'b0;
        fetch_addr_q = 32'd0;
        failures = 0;
        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'd0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        capture_owner();
        ctx_restore_req = 1'b1;
        @(posedge clk);
        require_clear("context restore retained a stale owner");
        ctx_restore_req = 1'b0;

        capture_owner();
        force u_cpu.wb_is_eret = 1'b1;
        force u_cpu.wb_commit_valid = 1'b1;
        force u_cpu.wb_arch_valid = 1'b1;
        force u_cpu.wb_except_req = 1'b0;
        @(posedge clk);
        require_clear("ERET retained a stale owner");
        release u_cpu.wb_is_eret;
        release u_cpu.wb_commit_valid;
        release u_cpu.wb_arch_valid;
        release u_cpu.wb_except_req;

        capture_owner();
        force u_cpu.interrupt_accept = 1'b1;
        force u_cpu.exception_flush = 1'b1;
        force u_cpu.wb_except_req = 1'b0;
        force u_cpu.wb_arch_valid = 1'b0;
        @(posedge clk);
        require_clear("interrupt flush retained a stale owner");
        release u_cpu.interrupt_accept;
        release u_cpu.exception_flush;
        release u_cpu.wb_except_req;
        release u_cpu.wb_arch_valid;

        capture_owner();
        rst_n = 1'b0;
        #1;
        require_clear("reset retained a stale owner");
        rst_n = 1'b1;

        capture_unaligned_owner();

        // 1. A younger MEM translation fault must not overwrite a live older owner.
        capture_owner();
        force u_cpu.dmem_translation_fault = 1'b1;
        force u_cpu.exception_flush = 1'b0;
        force u_cpu.wb_except_req = 1'b0;
        force u_cpu.wb_arch_valid = 1'b0;
        force u_cpu.mem_pc = 32'h8000_3000;
        force u_cpu.mem_inst = 32'h8c23_0080;
        force u_cpu.mem_access_addr = 32'h0040_9990;
        force u_cpu.d_fault_capture_code = 5'h03;
        force u_cpu.mem_mem_write = 1'b1;
        force u_cpu.cp0_asid = 8'h33;
        @(posedge clk);
        #1;
        if (!u_cpu.d_fault_vaddr_pending_q ||
            u_cpu.d_fault_owner_pc_q !== 32'h8000_1000 ||
            u_cpu.d_fault_vaddr_q !== 32'h0040_2040)
            fail("younger fault overwrote live older owner");
        release u_cpu.dmem_translation_fault;
        release u_cpu.exception_flush;
        release u_cpu.wb_except_req;
        release u_cpu.wb_arch_valid;
        release u_cpu.mem_pc;
        release u_cpu.mem_inst;
        release u_cpu.mem_access_addr;
        release u_cpu.d_fault_capture_code;
        release u_cpu.mem_mem_write;
        release u_cpu.cp0_asid;
        ctx_restore_req = 1'b1;
        @(posedge clk);
        require_clear("cleanup after younger-overwrite check failed");
        ctx_restore_req = 1'b0;

        // 2. An interrupt/exception flush coincident with dmem_translation_fault
        // must prevent the flushed fault from being captured.
        force u_cpu.dmem_translation_fault = 1'b1;
        force u_cpu.interrupt_accept = 1'b1;
        force u_cpu.exception_flush = 1'b1;
        force u_cpu.wb_except_req = 1'b0;
        force u_cpu.wb_arch_valid = 1'b0;
        force u_cpu.mem_pc = 32'h8000_4000;
        force u_cpu.mem_inst = 32'h8c24_0010;
        force u_cpu.mem_access_addr = 32'h0040_4010;
        force u_cpu.d_fault_capture_code = 5'h02;
        force u_cpu.mem_mem_write = 1'b0;
        force u_cpu.cp0_asid = 8'h2a;
        @(posedge clk);
        require_clear("interrupt-coincident D-fault was captured");
        release u_cpu.dmem_translation_fault;
        release u_cpu.interrupt_accept;
        release u_cpu.exception_flush;
        release u_cpu.wb_except_req;
        release u_cpu.wb_arch_valid;
        release u_cpu.mem_pc;
        release u_cpu.mem_inst;
        release u_cpu.mem_access_addr;
        release u_cpu.d_fault_capture_code;
        release u_cpu.mem_mem_write;
        release u_cpu.cp0_asid;

        if (failures == 0)
            $display("BADVADDR_OWNER_CONTEXT_PASS restore=1 eret=1 irq=1 reset=1 unaligned_ea=1 no_overwrite=1 irq_coincident=1");
        else
            $display("BADVADDR_OWNER_CONTEXT_FAIL failures=%0d", failures);
        $finish;
    end

    initial begin
        #2000;
        $display("BADVADDR_OWNER_CONTEXT_FAIL timeout");
        $finish;
    end
endmodule
