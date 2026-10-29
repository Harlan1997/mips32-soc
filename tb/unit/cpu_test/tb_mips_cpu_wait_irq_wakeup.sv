`timescale 1ns/1ps

module tb_mips_cpu_wait_irq_wakeup;
    reg clk, rst_n;
    reg [5:0] ext_int;
    reg [31:0] imem [0:1023];
    reg [31:0] fetch_addr_q;
    reg interrupt_seen, eret_seen, resume_seen;
    integer i;
    integer wait_cycles;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, data_addr, data_wdata, data_rdata;
    wire [3:0] data_be, data_req_id;
    wire [3:0] data_resp_id = 4'd0;
    wire [31:0] inst_rdata = imem[fetch_addr_q[11:2]];
    wire inst_addr_ok = 1'b1, inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0, inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1, data_data_ok = 1'b0;
    wire data_bus_error = 1'b0, data_cache_error = 1'b0;
    wire data_cache_op_done = 1'b0, data_cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire data_cache_op_valid;
    wire [4:0] data_cache_op;
    wire [31:0] data_cache_op_addr;
    wire data_cache_op_is_icache;
    wire [31:0] data_cache_tag_wdata;

    assign data_rdata = 32'd0;

    mips_cpu u_cpu (
        .clk(clk), .rst_n(rst_n), .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
        .inst_bus_error(inst_bus_error), .inst_cache_error(inst_cache_error),
        .inst_rdata(inst_rdata), .data_req(data_req), .data_req_id(data_req_id),
        .data_we(data_we), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_be(data_be), .data_uncacheable(),
        .data_cache_op_valid(data_cache_op_valid), .data_cache_op(data_cache_op),
        .data_cache_op_addr(data_cache_op_addr),
        .data_cache_op_is_icache(data_cache_op_is_icache),
        .data_cache_op_done(data_cache_op_done), .data_cache_op_error(data_cache_op_error),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok),
        .data_resp_id(data_resp_id), .data_bus_error(data_bus_error),
        .data_cache_error(data_cache_error), .data_cache_tag_rdata(data_cache_tag_rdata),
        .data_cache_tag_wdata(data_cache_tag_wdata), .data_rdata(data_rdata),
        .ext_int(ext_int), .tlb_inv_en(1'b0), .tlb_inv_vpn2(19'd0),
        .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0), .tlb_inv_wired_floor(6'd0),
        .sim_exception_req(1'b0), .sim_exception_code(5'd0),
        .external_vec_id(8'd0), .coh_snoop_valid(1'b0), .coh_snoop_addr(32'd0),
        .ctx_save_req(1'b0), .ctx_save_done(), .ctx_save_pc(), .ctx_save_status(),
        .ctx_save_asid(), .ctx_save_srsctl(), .ctx_save_gpr(), .ctx_save_srs_gpr(),
        .ctx_save_fpr(), .ctx_save_fcsr(), .ctx_restore_req(1'b0),
        .ctx_restore_pc(32'd0), .ctx_restore_status(32'd0), .ctx_restore_asid(8'd0),
        .ctx_restore_srsctl(32'd0), .ctx_restore_gpr(1024'd0),
        .ctx_restore_srs_gpr(16384'd0), .ctx_restore_set(4'd0),
        .ctx_restore_fpr(1024'd0), .ctx_restore_fcsr(32'd0), .ctx_restore_ack(),
        .hardware_walker_enable(1'b0), .hardware_walker_ptbr(32'd0),
        .ptw_mem_valid(), .ptw_mem_addr(), .ptw_mem_ready(1'b0),
        .ptw_mem_rdata(32'd0), .ptw_mem_error(1'b0), .ptw_fault_valid(),
        .ptw_fault_code(), .debug_stall(debug_stall), .debug_flush(debug_flush),
        .perf_cycle_count(), .perf_retire_count(), .perf_icache_miss_count(),
        .perf_dcache_miss_count(), .perf_branch_mispredict_count(),
        .perf_mdu_stall_count());

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_addr_q <= 32'd0;
            interrupt_seen <= 1'b0;
            eret_seen <= 1'b0;
            resume_seen <= 1'b0;
        end else begin
            fetch_addr_q <= inst_addr;
            if (u_cpu.interrupt_accept)
                interrupt_seen <= 1'b1;
            if (u_cpu.wb_is_eret && u_cpu.wb_commit_valid)
                eret_seen <= 1'b1;
            if (u_cpu.wb_arch_valid && (u_cpu.wb_pc == 32'h0000_0044))
                resume_seen <= 1'b1;

            // A committed WB producer is already architectural.  It must not
            // hold the Linux IRQ restart guard high after the younger pipeline
            // stages are empty, or a polling load can starve timer delivery.
            if (!u_cpu.wait_state && u_cpu.wb_arch_valid &&
                u_cpu.irq_wb_gpr_write &&
                !(u_cpu.ex_flush_valid && u_cpu.irq_ex_gpr_write) &&
                !(u_cpu.id_flush_valid && u_cpu.irq_id_gpr_write) &&
                !(u_cpu.mem_flush_valid && u_cpu.irq_mem_gpr_write) &&
                u_cpu.linux_irq_restart_hazard) begin
                $display("WAIT_IRQ_TEST_FAIL WB-only restart hazard");
                $finish;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ext_int = 6'd0;
        fetch_addr_q = 32'd0;
        interrupt_seen = 1'b0;
        eret_seen = 1'b0;
        resume_seen = 1'b0;
        for (i = 0; i < 1024; i = i + 1)
            imem[i] = 32'd0;

        imem[32'h000/4] = 32'h2401_0000; // clear BEV
        imem[32'h004/4] = 32'h4081_6000; // mtc0 $1,Status
        imem[32'h008/4] = 32'h0000_00c0; // ehb
        imem[32'h00c/4] = 32'h2401_0401; // IE + IM2
        imem[32'h010/4] = 32'h4081_6000; // mtc0 $1,Status
        imem[32'h014/4] = 32'h0000_00c0; // ehb
        imem[32'h018/4] = 32'h0c00_0010; // jal wait_helper
        imem[32'h01c/4] = 32'h0000_0000; // delay slot
        imem[32'h020/4] = 32'h8f9f_0000; // younger lw ra held behind WAIT
        imem[32'h024/4] = 32'h03e0_0008; // jr ra
        imem[32'h028/4] = 32'h0000_0000; // delay slot
        imem[32'h02c/4] = 32'h1000_ffff; // loop
        imem[32'h030/4] = 32'h0000_0000;
        imem[32'h040/4] = 32'h4200_0020; // WAIT in called helper
        imem[32'h044/4] = 32'h03e0_0008; // return after interrupt
        imem[32'h048/4] = 32'h0000_0000;
        imem[32'h180/4] = 32'h4200_0018; // eret
        imem[32'h184/4] = 32'h0000_0000;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        wait_cycles = 0;
        while (!u_cpu.wait_state && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!u_cpu.wait_state) begin
            $display("WAIT_IRQ_TEST_FAIL core did not enter WAIT");
        end else if (u_cpu.wait_resume_pc !== 32'h0000_0044) begin
            $display("WAIT_IRQ_TEST_FAIL resume PC=%08h", u_cpu.wait_resume_pc);
        end else if (u_cpu.id_pc !== 32'h0000_0020 ||
                     u_cpu.id_inst !== 32'h8f9f_0000) begin
            $display("WAIT_IRQ_TEST_FAIL fixture ID=%08h/%08h",
                     u_cpu.id_pc, u_cpu.id_inst);
        end else begin
            $display("WAIT_IRQ_TEST_STATE hazard=%b idpc=%08h idinst=%08h meminst=%08h",
                     u_cpu.linux_irq_restart_hazard, u_cpu.id_pc, u_cpu.id_inst,
                     u_cpu.mem_inst);
            ext_int = 6'b000001;
            repeat (8) @(posedge clk);
            #1 ext_int = 6'd0;
            if (!interrupt_seen) begin
                $display("WAIT_IRQ_TEST_FAIL post-WAIT GPR producer blocked IRQ");
            end else begin
                repeat (24) @(posedge clk);
                if (!eret_seen || !resume_seen)
                    $display("WAIT_IRQ_TEST_FAIL eret=%b resumed=%b", eret_seen, resume_seen);
                else
                    $display("WAIT_IRQ_TEST_PASS");
            end
        end
        $finish;
    end

    initial begin
        #5000;
        $display("WAIT_IRQ_TEST_FAIL timeout");
        $finish;
    end
endmodule
