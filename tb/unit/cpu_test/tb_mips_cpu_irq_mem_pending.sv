// Blocking MEM transaction versus asynchronous IRQ contract.
`timescale 1ns/1ps

module tb_mips_cpu_irq_mem_pending;
    reg clk, rst_n;
    reg [5:0] ext_int;
    reg data_data_ok;
    reg response_pending;
    integer response_delay;
    integer i;

    wire inst_req, data_req, data_we, debug_stall, debug_flush;
    wire [31:0] inst_addr, data_addr, data_wdata, data_rdata;
    wire [3:0] data_be, data_req_id;
    wire [3:0] data_resp_id = 4'd0;
    wire [31:0] inst_rdata;
    wire inst_addr_ok = 1'b1, inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0, inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1, data_bus_error = 1'b0;
    wire data_cache_error = 1'b0;
    wire data_cache_op_done = 1'b0, data_cache_op_error = 1'b0;
    wire [31:0] data_cache_tag_rdata = 32'd0;
    wire data_cache_op_valid;
    wire [4:0] data_cache_op;
    wire [31:0] data_cache_op_addr;
    wire data_cache_op_is_icache;
    wire [31:0] data_cache_tag_wdata;

    reg [31:0] imem [0:1023];
    reg [31:0] fetch_addr_q;
    reg load_retired, interrupt_seen, early_interrupt_seen;
    integer load_retire_count;

    assign inst_rdata = imem[fetch_addr_q[11:2]];
    assign data_rdata = 32'hcafe_1234;

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

    // Address acceptance starts a four-cycle response delay.  IP2 is raised
    // only after the request is live, exercising the address-accepted gap.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_pending <= 1'b0;
            response_delay <= 0;
            data_data_ok <= 1'b0;
        end else begin
            data_data_ok <= 1'b0;
            if (!response_pending && data_req && data_addr_ok) begin
                response_pending <= 1'b1;
                response_delay <= 4;
            end else if (response_pending && response_delay != 0) begin
                response_delay <= response_delay - 1;
            end else if (response_pending) begin
                data_data_ok <= 1'b1;
                response_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_addr_q <= 32'd0;
            load_retired <= 1'b0;
            interrupt_seen <= 1'b0;
            early_interrupt_seen <= 1'b0;
            load_retire_count <= 0;
        end else begin
            fetch_addr_q <= inst_addr;
            if (u_cpu.interrupt_accept) interrupt_seen <= 1'b1;
            if (u_cpu.interrupt_accept && data_req && !data_data_ok)
                early_interrupt_seen <= 1'b1;
            if (u_cpu.wb_arch_valid && u_cpu.wb_reg_write && u_cpu.wb_waddr == 5'd3) begin
                load_retired <= 1'b1;
                load_retire_count <= load_retire_count + 1;
                if (u_cpu.wb_wdata !== 32'hcafe_1234)
                    $display("REGRESSION_TEST_FAILED load data=%h", u_cpu.wb_wdata);
            end
        end
    end

    initial begin
        clk = 1'b0; rst_n = 1'b0; ext_int = 6'd0;
        data_data_ok = 1'b0; response_pending = 1'b0; response_delay = 0;
        fetch_addr_q = 32'd0; load_retired = 1'b0;
        interrupt_seen = 1'b0; early_interrupt_seen = 1'b0; load_retire_count = 0;
        for (i = 0; i < 1024; i = i + 1) imem[i] = 32'd0;

        imem[32'h000/4] = 32'h2401_0000; // clear BEV
        imem[32'h004/4] = 32'h4081_6000; // mtc0 $1,Status
        imem[32'h008/4] = 32'h0000_0000;
        imem[32'h00c/4] = 32'h2401_0401; // IE + IM2
        imem[32'h010/4] = 32'h4081_6000; // mtc0 $1,Status
        imem[32'h014/4] = 32'h0000_0000;
        imem[32'h018/4] = 32'h3c02_a000; // kseg1 base
        imem[32'h01c/4] = 32'h8c43_2000; // lw $3,0x2000($2)
        imem[32'h020/4] = 32'h0000_0000;
        imem[32'h024/4] = 32'h1000_ffff; // loop after return
        imem[32'h028/4] = 32'h0000_0000;
        imem[32'h180/4] = 32'h4200_0018; // eret
        imem[32'h184/4] = 32'h0000_0000;

        #17 rst_n = 1'b1;
        wait (response_pending);
        ext_int = 6'b000001;
        wait (interrupt_seen);
        ext_int = 6'd0;
        repeat (8) @(posedge clk);
        if (early_interrupt_seen)
            $display("REGRESSION_TEST_FAILED blocking MEM interrupted before response");
        else if (!load_retired || load_retire_count != 1)
            $display("REGRESSION_TEST_FAILED load retire count=%0d retired=%b", load_retire_count, load_retired);
        else
            $display("REGRESSION_TEST_SUCCESS mips_cpu_irq_mem_pending retire_count=%0d", load_retire_count);
        $finish;
    end

    initial begin
        #5000;
        $display("REGRESSION_TEST_FAILED timeout");
        $finish;
    end
endmodule
