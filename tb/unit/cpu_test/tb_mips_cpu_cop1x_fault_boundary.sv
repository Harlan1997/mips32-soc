`timescale 1ns/1ps

// Focused COP1X fault-boundary evidence.  The test drives the MEM-side
// handshake directly so it can distinguish the first and second aligned word
// beats without depending on a page-table setup or a long firmware run.
module tb_mips_cpu_cop1x_fault_boundary;
    reg clk, rst_n;
    reg data_data_ok;
    reg data_bus_error;
    reg data_cache_error;
    reg [31:0] data_rdata;
    reg [31:0] imem [0:255];
    reg [31:0] fetch_addr_q;
    integer i;
    integer failures;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, inst_rdata;
    wire [31:0] data_addr;
    wire [3:0] data_req_id, data_be;
    wire [3:0] data_resp_id = 4'd0;
    wire inst_addr_ok = 1'b1, inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0, inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1;
    wire data_cache_op_done = 1'b0, data_cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire data_cache_op_valid;
    wire [4:0] data_cache_op;
    wire [31:0] data_cache_op_addr;
    wire data_cache_op_is_icache;
    wire [31:0] data_cache_tag_wdata;

    assign inst_rdata = imem[fetch_addr_q[9:2]];

    mips_cpu u_cpu (
        .clk(clk), .rst_n(rst_n), .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
        .inst_bus_error(inst_bus_error), .inst_cache_error(inst_cache_error),
        .inst_rdata(inst_rdata), .data_req(data_req), .data_req_id(data_req_id),
        .data_we(data_we), .data_addr(data_addr), .data_wdata(),
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
        .ctx_restore_req(1'b0), .ctx_restore_pc(32'd0),
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

    // A second instance checks the external store request boundary directly.
    reg [31:0] store_addr;
    reg [31:0] store_low, store_high;
    reg store_write, store_unaligned_double;
    reg [1:0] store_phase;
    reg store_translation_fault;
    wire [31:0] store_dmem_addr, store_dmem_wdata;
    wire store_dmem_we, store_dmem_en;
    wire [3:0] store_dmem_be;
    wire store_stall_req, store_cache_op_valid, store_cache_op_fault;
    wire [4:0] store_cache_op;
    wire [31:0] store_cache_op_addr, store_rdata_ext;
    wire store_adel, store_ades;

    mips_mem_stage u_store_stage (
        .mem_ex_out(store_addr), .mem_val_rt(32'd0), .mem_read(1'b0),
        .mem_write(store_write), .mem_op(3'b100), .mem_done(1'b0),
        .mem_unaligned_double(store_unaligned_double),
        .mem_double_phase(store_phase), .mem_double_store_low(store_low),
        .mem_double_store_high(store_high), .enable_nonblocking_load(1'b0),
        .reverse_endian(1'b0), .mem_cache_op_valid(1'b0), .mem_cache_op(5'd0),
        .dmem_rdata(32'd0), .dmem_addr(store_dmem_addr),
        .dmem_wdata(store_dmem_wdata), .dmem_we(store_dmem_we),
        .dmem_be(store_dmem_be), .dmem_en(store_dmem_en),
        .dmem_addr_ok(1'b1), .dmem_data_ok(1'b0),
        .translation_fault(store_translation_fault), .cache_op_done(1'b0),
        .cache_op_error(1'b0), .stall_req_mem(store_stall_req),
        .cache_op_valid(store_cache_op_valid), .cache_op(store_cache_op),
        .cache_op_addr(store_cache_op_addr), .cache_op_fault(store_cache_op_fault),
        .mem_rdata_ext(store_rdata_ext), .adel_exception(store_adel),
        .ades_exception(store_ades));

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
            $display("COP1X_FAULT_BOUNDARY_FAIL %0s", message);
        end
    endtask

    task automatic setup_cpu_mem;
        begin
            force u_cpu.mem_inst = 32'h4f19_4005; // LUXC1 $f8, index($t8)
            force u_cpu.mem_mem_read = 1'b1;
            force u_cpu.mem_mem_write = 1'b0;
            force u_cpu.mem_mem_op = 3'b100;
            force u_cpu.dmem_request_blocked = 1'b0;
            force u_cpu.cpu_fpu_fr = 1'b1;
            force u_cpu.exception_flush = 1'b0;
            force u_cpu.global_stall = 1'b0;
            force u_cpu.stall_req_id = 1'b0;
        end
    endtask

    task automatic release_cpu_mem;
        begin
            release u_cpu.mem_inst;
            release u_cpu.mem_mem_read;
            release u_cpu.mem_mem_write;
            release u_cpu.mem_mem_op;
            release u_cpu.dmem_request_blocked;
            release u_cpu.cpu_fpu_fr;
            release u_cpu.exception_flush;
            release u_cpu.global_stall;
            release u_cpu.stall_req_id;
        end
    endtask

    task automatic check_fpr(input [31:0] low, input [31:0] high,
                             input [1023:0] reason);
        begin
            if (u_cpu.fpr[8] !== low || u_cpu.fpr_hi[8] !== high)
                fail(reason);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        data_data_ok = 1'b0;
        data_bus_error = 1'b0;
        data_cache_error = 1'b0;
        data_rdata = 32'd0;
        fetch_addr_q = 32'd0;
        failures = 0;
        store_addr = 32'h0040_2040;
        store_low = 32'haabb_ccdd;
        store_high = 32'heeff_0011;
        store_write = 1'b1;
        store_unaligned_double = 1'b1;
        store_phase = 2'd0;
        store_translation_fault = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'd0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        setup_cpu_mem();
        u_cpu.fpr[8] = 32'h1111_2222;
        u_cpu.fpr_hi[8] = 32'h3333_4444;

        // First-beat fault: no FPR word may be committed.
        force u_cpu.mem_double_phase = 2'd0;
        force u_cpu.dmem_request_blocked = 1'b1;
        data_rdata = 32'haaaa_bbbb;
        data_data_ok = 1'b1;
        @(posedge clk);
        #1;
        check_fpr(32'h1111_2222, 32'h3333_4444,
                  "first-beat fault partially committed the FPR");
        release u_cpu.dmem_request_blocked;

        // A clean first beat is only buffered.  Architectural FPR state still
        // must remain unchanged until the second beat completes.
        data_data_ok = 1'b0;
        @(posedge clk);
        data_rdata = 32'haaaa_bbbb;
        data_data_ok = 1'b1;
        @(posedge clk);
        #1;
        check_fpr(32'h1111_2222, 32'h3333_4444,
                  "first clean beat committed the FPR early");

        // Second-beat fault: the buffered low word must be discarded and the
        // high word must never reach the architectural FPR.
        data_data_ok = 1'b0;
        force u_cpu.mem_double_phase = 2'd1;
        force u_cpu.dmem_request_blocked = 1'b1;
        data_rdata = 32'hdead_beef;
        data_data_ok = 1'b1;
        @(posedge clk);
        #1;
        check_fpr(32'h1111_2222, 32'h3333_4444,
                  "second-beat fault partially committed the FPR");
        release u_cpu.dmem_request_blocked;
        release u_cpu.mem_double_phase;
        release_cpu_mem();

        // SUXC1 store request: both clean beats are full words, and a fault on
        // beat 1 suppresses that request entirely.
        #1;
        if (store_dmem_addr !== 32'h0040_2040 ||
            store_dmem_wdata !== 32'haabb_ccdd ||
            store_dmem_be !== 4'b1111 || !store_dmem_en || !store_dmem_we)
            fail("first SUXC1 beat was not a complete aligned store");
        store_phase = 2'd1;
        #1;
        if (store_dmem_wdata !== 32'heeff_0011 ||
            store_dmem_be !== 4'b1111 || !store_dmem_en || !store_dmem_we)
            fail("second SUXC1 beat was not a complete aligned store");
        store_translation_fault = 1'b1;
        #1;
        if (store_dmem_en !== 1'b0)
            fail("faulting SUXC1 beat still issued a store request");

        if (failures == 0)
            $display("COP1X_FAULT_BOUNDARY_PASS first_fault=1 second_fault=1 fpr_atomic=1 store_blocked=1");
        else
            $display("COP1X_FAULT_BOUNDARY_FAIL failures=%0d", failures);
        $finish;
    end

    initial begin
        #2000;
        $display("COP1X_FAULT_BOUNDARY_FAIL timeout");
        $finish;
    end
endmodule
