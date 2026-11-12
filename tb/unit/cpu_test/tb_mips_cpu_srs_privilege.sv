`timescale 1ns/1ps

// User mode must not execute the opt-in shadow-register-set instructions.
// The existing SRS firmware gate covers the kernel-mode data path; this test
// drives the CPU through its architectural context-restore interface so the
// privilege check is exercised at the real ID/exception boundary.
module tb_mips_cpu_srs_privilege;
    reg clk, rst_n;
    reg ctx_restore_req;
    reg [31:0] ctx_restore_status;
    reg [31:0] fetch_addr_q;
    reg [31:0] imem [0:255];
    integer i;
    integer cycles;
    reg saw_cop_unusable;
    reg user_privilege_pass;
    reg di_ei_privilege_pass;
    reg saw_supervisor_adel;
    reg saw_supervisor_sseg_req;
    reg saw_supervisor_kseg3_req;
    reg [31:0] supervisor_sseg_addr;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, inst_rdata;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0] data_be, data_req_id;
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
        .ctx_save_gpr(), .ctx_save_srs_gpr(), .ctx_save_fpr(), .ctx_save_fcsr(),
        .ctx_restore_req(ctx_restore_req), .ctx_restore_pc(32'd0),
        .ctx_restore_status(ctx_restore_status), .ctx_restore_asid(8'd0),
        .ctx_restore_ptebase(32'd0), .ctx_restore_ptebase_valid(1'b0),
        .ctx_restore_srsctl(32'd0), .ctx_restore_gpr(1024'd0),
        .ctx_restore_srs_gpr(16384'd0), .ctx_restore_set(4'd0),
        .ctx_restore_fpr(1024'd0), .ctx_restore_fcsr(32'd0), .ctx_restore_ack(),
        .hardware_walker_enable(1'b0), .hardware_walker_ptbr(32'd0),
        .ptw_mem_valid(), .ptw_mem_addr(), .ptw_mem_write_valid(),
        .ptw_mem_write_addr(), .ptw_mem_write_data(), .ptw_mem_ready(1'b0),
        .ptw_mem_rdata(32'd0), .ptw_mem_error(1'b0), .ptw_mem_write_ready(1'b0),
        .ptw_mem_write_error(1'b0), .ptw_fault_valid(), .ptw_fault_code(),
        .tlb_inv_applied(), .debug_stall(debug_stall), .debug_flush(debug_flush),
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            saw_cop_unusable <= 1'b0;
        else if (u_cpu.wb_commit_valid && u_cpu.wb_except_req &&
                 u_cpu.wb_except_code == 5'h0b)
            saw_cop_unusable <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_supervisor_adel <= 1'b0;
            saw_supervisor_sseg_req <= 1'b0;
            saw_supervisor_kseg3_req <= 1'b0;
            supervisor_sseg_addr <= 32'd0;
        end else begin
            if (u_cpu.wb_commit_valid && u_cpu.wb_except_req &&
                u_cpu.wb_except_code == 5'h04)
                saw_supervisor_adel <= 1'b1;
            if (data_req && data_addr[31:29] == 3'b110) begin
                saw_supervisor_sseg_req <= 1'b1;
                supervisor_sseg_addr <= data_addr;
            end
            if (data_req && data_addr[31:29] == 3'b111)
                saw_supervisor_kseg3_req <= 1'b1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ctx_restore_req = 1'b0;
        // KSU=User (10b), IE/EXL/ERL clear, CU0/CU1 clear.
        ctx_restore_status = 32'h0000_0010;
        fetch_addr_q = 32'd0;
        saw_cop_unusable = 1'b0;
        user_privilege_pass = 1'b0;
        di_ei_privilege_pass = 1'b0;
        saw_supervisor_adel = 1'b0;
        saw_supervisor_sseg_req = 1'b0;
        saw_supervisor_kseg3_req = 1'b0;
        supervisor_sseg_addr = 32'd0;
        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'd0;
        // RDPGPR $t1,$t0; this is legal only with SRS enabled and kernel mode.
        imem[0] = 32'h4148_4800;
        imem[1] = 32'h0000_0000;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk);
        ctx_restore_req = 1'b1;
        @(posedge clk);
        ctx_restore_req = 1'b0;

        cycles = 0;
        while (!saw_cop_unusable && cycles < 160) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        #1;
        if (!saw_cop_unusable) begin
            $display("SRS_PRIVILEGE_TEST_FAIL no Coprocessor Unusable exception");
        end else if (u_cpu.u_mips_cp0.cp0_status[4:3] !== 2'b10 ||
                     u_cpu.u_mips_cp0.cp0_status[1] !== 1'b1) begin
            $display("SRS_PRIVILEGE_TEST_FAIL status=%08h", u_cpu.u_mips_cp0.cp0_status);
        end else begin
            $display("SRS_PRIVILEGE_USER_PASS exc_code=0x0b status=%08h",
                     u_cpu.u_mips_cp0.cp0_status);
            user_privilege_pass = 1'b1;
        end

        // A scheduler context restore can enter Supervisor mode with EXL/ERL
        // clear. Supervisor remains privileged for MFC0, while address-space
        // checks must allow sseg while rejecting kernel-only kseg3 before a
        // denied load reaches the data bus.
        imem[0] = 32'h4008_6000; // MFC0 $t0, Status
        imem[1] = 32'h3c09_c000; // LUI $t1, 0xc000
        imem[2] = 32'h8d2a_0000; // LW $t2, 0($t1), supervisor sseg access
        imem[3] = 32'h3c0b_e000; // LUI $t3, 0xe000
        imem[4] = 32'h8d6c_0000; // LW $t4, 0($t3), supervisor kseg3 fault
        ctx_restore_status = 32'h0000_0008; // KSU=Supervisor, EXL/ERL clear
        saw_supervisor_adel = 1'b0;
        saw_supervisor_sseg_req = 1'b0;
        saw_supervisor_kseg3_req = 1'b0;
        supervisor_sseg_addr = 32'd0;
        ctx_restore_req = 1'b1;
        @(posedge clk);
        #1 ctx_restore_req = 1'b0;

        cycles = 0;
        while (!saw_supervisor_adel && cycles < 160) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        #1;
        if (!user_privilege_pass) begin
            $display("SRS_PRIVILEGE_TEST_FAIL user-mode CpU check failed");
        end else if (!saw_supervisor_adel) begin
            $display("SRS_PRIVILEGE_TEST_FAIL supervisor kseg3 did not raise AdEL");
        end else if (!saw_supervisor_sseg_req ||
                     supervisor_sseg_addr !== 32'hc000_0000) begin
            $display("SRS_PRIVILEGE_TEST_FAIL supervisor sseg request=%b addr=%08h",
                     saw_supervisor_sseg_req, supervisor_sseg_addr);
        end else if (saw_supervisor_kseg3_req) begin
            $display("SRS_PRIVILEGE_TEST_FAIL rejected supervisor kseg3 load reached data bus");
        end else if (u_cpu.u_mips_cp0.cp0_status[4:3] !== 2'b01 ||
                     u_cpu.u_mips_cp0.cp0_status[1] !== 1'b1 ||
                     u_cpu.u_mips_cp0.cp0_badvaddr !== 32'he000_0000 ||
                     u_cpu.u_mips_cp0.cp0_cause[6:2] !== 5'h04) begin
            $display("SRS_PRIVILEGE_TEST_FAIL supervisor status=%08h badvaddr=%08h cause=%08h",
                     u_cpu.u_mips_cp0.cp0_status,
                     u_cpu.u_mips_cp0.cp0_badvaddr,
                     u_cpu.u_mips_cp0.cp0_cause);
        end else begin
            $display("SRS_PRIVILEGE_TEST_PASS user_exc=0x0b supervisor_sseg=%08h supervisor_adel=0x04 badvaddr=%08h",
                     supervisor_sseg_addr, u_cpu.u_mips_cp0.cp0_badvaddr);
        end
        // MFMC0 DI/EI are privileged even though they return old Status.
        // Execute both from User mode and require CpU without changing IE.
        // Reset between scenarios so the prior Supervisor AdEL cannot leave
        // an in-flight exception frame ahead of the context restore.
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        imem[0] = 32'h4168_6000; // DI $t0
        imem[1] = 32'h0000_0000;
        ctx_restore_status = 32'h0000_0010; // User, IE=0, EXL/ERL=0
        saw_cop_unusable = 1'b0;
        ctx_restore_req = 1'b1;
        @(posedge clk);
        #1 ctx_restore_req = 1'b0;
        cycles = 0;
        while (!saw_cop_unusable && cycles < 160) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!saw_cop_unusable || u_cpu.u_mips_cp0.cp0_status[0] !== 1'b0)
            $display("SRS_PRIVILEGE_TEST_FAIL user DI did not trap or changed IE status=%08h",
                     u_cpu.u_mips_cp0.cp0_status);
        else begin
            imem[0] = 32'h4169_6020; // EI $t1
            imem[1] = 32'h0000_0000;
            ctx_restore_status = 32'h0000_0010; // User, IE=0, EXL/ERL=0
            saw_cop_unusable = 1'b0;
            ctx_restore_req = 1'b1;
            @(posedge clk);
            #1 ctx_restore_req = 1'b0;
            cycles = 0;
            while (!saw_cop_unusable && cycles < 160) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!saw_cop_unusable || u_cpu.u_mips_cp0.cp0_status[0] !== 1'b0)
                $display("SRS_PRIVILEGE_TEST_FAIL user EI did not trap or changed IE status=%08h",
                         u_cpu.u_mips_cp0.cp0_status);
            else begin
                di_ei_privilege_pass = 1'b1;
                $display("DI_EI_USER_PRIVILEGE_PASS di_exc=0x0b ei_exc=0x0b ie_unchanged=1");
            end
        end
        if (!di_ei_privilege_pass)
            $display("SRS_PRIVILEGE_TEST_FAIL DI/EI user privilege boundary");
        $finish;
    end

    initial begin
        #4000;
        $display("SRS_PRIVILEGE_TEST_FAIL timeout");
        $finish;
    end
endmodule
