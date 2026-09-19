// Focused CPU integration test for an ALU-result RAW dependency in address
// generation.  The load must use the value produced by the immediately
// preceding LUI through EX-to-ID forwarding.
`timescale 1ns/1ps

module tb_mips_cpu_lui_lw_forward;
    reg clk, rst_n;
    reg data_data_ok;
    reg data_pending;
    reg [31:0] fetch_addr_q;
    integer response_delay;
    integer i;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, inst_rdata;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0] data_be, data_req_id;
    wire [3:0] data_resp_id = 4'd0;
    wire inst_addr_ok = 1'b1;
    reg fetch_stall;
    wire inst_data_ok = !fetch_stall;
    wire inst_bus_error = 1'b0;
    wire inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1;
    wire data_bus_error = 1'b0;
    wire data_cache_error = 1'b0;
    wire data_cache_op_done = 1'b0;
    wire data_cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire data_cache_op_valid;
    wire [4:0] data_cache_op;
    wire [31:0] data_cache_op_addr;
    wire data_cache_op_is_icache;
    wire [31:0] data_cache_tag_wdata;

    reg [31:0] imem [0:255];
    reg request_seen;
    reg request_address_ok;
    reg load_retired;
    reg [31:0] observed_address;
    integer errors;
    integer cycle_count;
    reg forward_seen;
    reg stall_mode;

    wire [31:0] expected_address = (`SOC_MMU_ENABLE != 0) ?
                                   32'h08d4_7620 : 32'h88d4_7620;

    assign inst_rdata = imem[fetch_addr_q[9:2]];
    assign data_rdata = (data_addr == expected_address) ?
                        32'hfeed_beef : 32'hdead_beef;

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
        .ext_int(6'd0), .tlb_inv_en(1'b0), .tlb_inv_vpn2(19'd0),
        .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0), .tlb_inv_wired_floor(6'd0),
        .sim_exception_req(1'b0), .sim_exception_code(5'd0),
        .external_vec_id(8'd0), .coh_snoop_valid(1'b0), .coh_snoop_addr(32'd0),
        .ctx_save_req(1'b0), .ctx_save_done(), .ctx_save_pc(), .ctx_save_status(),
        .ctx_save_asid(), .ctx_save_ptebase(), .ctx_save_srsctl(),
        .ctx_save_gpr(), .ctx_save_srs_gpr(), .ctx_save_fpr(), .ctx_save_fcsr(),
        .ctx_restore_req(1'b0), .ctx_restore_pc(32'd0), .ctx_restore_status(32'd0),
        .ctx_restore_asid(8'd0), .ctx_restore_ptebase(32'd0),
        .ctx_restore_ptebase_valid(1'b0), .ctx_restore_srsctl(32'd0),
        .ctx_restore_gpr(1024'd0), .ctx_restore_srs_gpr(16384'd0),
        .ctx_restore_set(4'd0), .ctx_restore_fpr(1024'd0), .ctx_restore_fcsr(32'd0),
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

    // IF is a one-cycle look-ahead interface in the standalone CPU harness.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_addr_q <= 32'd0;
            fetch_stall <= 1'b0;
            cycle_count <= 0;
        end else begin
            fetch_addr_q <= inst_addr;
            cycle_count <= cycle_count + 1;
            // Hold the complete pipeline across two short instruction-bus
            // backpressure windows. The windows are deliberately independent
            // of the data response and exercise forwarding after a front-end
            // stall has left historical EX/MEM control fields in place.
            fetch_stall <= stall_mode &&
                           (((cycle_count >= 4) && (cycle_count <= 6)) ||
                            ((cycle_count >= 11) && (cycle_count <= 13)));
        end
    end

    // Return one cycle after address acceptance and keep the response
    // independent of the instruction stream.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_data_ok <= 1'b0;
            data_pending <= 1'b0;
            response_delay <= 0;
        end else begin
            data_data_ok <= 1'b0;
            if (!data_pending && data_req && data_addr_ok) begin
                data_pending <= 1'b1;
                response_delay <= 1;
            end else if (data_pending && response_delay != 0) begin
                response_delay <= response_delay - 1;
            end else if (data_pending) begin
                data_data_ok <= 1'b1;
                data_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_seen <= 1'b0;
            request_address_ok <= 1'b0;
            observed_address <= 32'd0;
            load_retired <= 1'b0;
            forward_seen <= 1'b0;
        end else begin
            if (data_req && !data_we && !request_seen) begin
                request_seen <= 1'b1;
                observed_address <= data_addr;
                request_address_ok <= (data_addr == expected_address);
            end
            if (u_cpu.ex_inst == 32'h3c02_88d4 &&
                u_cpu.id_inst == 32'h8c42_7620) begin
                if (u_cpu.ex_out !== 32'h88d4_0000 ||
                    u_cpu.id_val_rs !== 32'h88d4_0000 ||
                    u_cpu.fw_ex_we !== 1'b1 ||
                    u_cpu.ex_flush_valid !== 1'b1) begin
                    $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward raw ex_out=%h id_rs=%h fw=%b valid=%b",
                             u_cpu.ex_out, u_cpu.id_val_rs, u_cpu.fw_ex_we,
                             u_cpu.ex_flush_valid);
                    errors = errors + 1;
                end else begin
                    forward_seen <= 1'b1;
                end
            end
            if (u_cpu.wb_arch_valid && u_cpu.wb_reg_write &&
                u_cpu.wb_waddr == 5'd2 && u_cpu.wb_wdata == 32'hfeed_beef)
                load_retired <= 1'b1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        data_data_ok = 1'b0;
        data_pending = 1'b0;
        response_delay = 0;
        fetch_addr_q = 32'd0;
        request_seen = 1'b0;
        request_address_ok = 1'b0;
        observed_address = 32'd0;
        load_retired = 1'b0;
        forward_seen = 1'b0;
        stall_mode = $test$plusargs("FETCH_STALL");
        fetch_stall = 1'b0;
        cycle_count = 0;
        errors = 0;
        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'd0;

        // PC 0x00: lui $v0,0x88d4
        imem[0] = 32'h3c02_88d4;
        // PC 0x04: lw $v0,0x7620($v0)
        imem[1] = 32'h8c42_7620;
        imem[2] = 32'h0000_0000;
        #17 rst_n = 1'b1;

        repeat (80) @(posedge clk);
        #1;
        if (!request_seen) begin
            $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward no load request");
            errors = errors + 1;
        end
        if (!request_address_ok) begin
            $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward address=%h expected=%h",
                     observed_address, expected_address);
            errors = errors + 1;
        end
        if (!forward_seen) begin
            $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward forwarding pair was not observed");
            errors = errors + 1;
        end
        if (!load_retired) begin
            $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward load did not retire reg2=%h wb=%b/%b/%0d/%h except=%b/%0d mmu=%b/%0d data=%b/%b/%b/%h",
                     u_cpu.u_mips_id_stage.u_mips_regfile.regs[2],
                     u_cpu.wb_valid, u_cpu.wb_arch_valid, u_cpu.wb_waddr,
                     u_cpu.wb_wdata, u_cpu.wb_except_req, u_cpu.wb_except_code,
                     u_cpu.mmu_d_ok, u_cpu.mmu_d_fault_type, data_req, data_we,
                     data_data_ok, data_addr);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS mips_cpu_lui_lw_forward address=%h",
                     observed_address);
        $finish;
    end

    initial begin
        #5000;
        $display("REGRESSION_TEST_FAILED mips_cpu_lui_lw_forward timeout");
        $finish;
    end
endmodule
