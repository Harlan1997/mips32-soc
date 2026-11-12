// Synthetic testbench driving soc_observation_if into retire_trace_capture
// targeting a named FIFO under backpressure.
`timescale 1ns/1ps

module tb_retire_trace_fifo;
    logic clk;
    logic rst_n;
    integer total_records;
    integer cur_record;
    integer clk_period = 10;

    // Clock generation
    initial begin
        clk = 0;
        forever #(clk_period / 2) clk = ~clk;
    end

    // Observation interface instance
    soc_observation_if obs_if(clk, rst_n);

    // Capture module instance under test
    retire_trace_capture u_capture(
        .clk(clk),
        .rst_n(rst_n),
        .obs_if(obs_if)
    );

    initial begin
        total_records = 50000;
        void'($value$plusargs("RETIRE_TRACE_MAX_RECORDS=%d", total_records));

        // Initialize signals
        rst_n = 0;
        obs_if.retire_schema = 32'h00020000;
        obs_if.retire_valid = 0;
        obs_if.retire_pc = 32'h88000000;
        obs_if.retire_instr = 32'h24420001; // addiu v0, v0, 1
        obs_if.retire_next_pc = 32'h88000004;
        obs_if.retire_gpr_we = 1;
        obs_if.retire_gpr_addr = 5'd2;
        obs_if.retire_gpr_data = 32'd0;
        obs_if.retire_gpr_state = 1024'd0;
        obs_if.retire_hilo_state = 64'd0;
        obs_if.retire_mdu_done = 0;
        obs_if.retire_mdu_op = 4'd0;
        obs_if.retire_cp0_we = 0;
        obs_if.retire_cp0_addr = 5'd0;
        obs_if.retire_cp0_sel = 3'd0;
        obs_if.retire_cp0_data = 32'd0;
        obs_if.retire_fpr_state = 1024'd0;
        obs_if.retire_fpr_hi_state = 1024'd0;
        obs_if.retire_fcsr_state = 32'd0;
        obs_if.retire_mem_valid = 0;
        obs_if.retire_mem_read = 0;
        obs_if.retire_mem_write = 0;
        obs_if.retire_mem_addr = 32'd0;
        obs_if.retire_mem_wdata = 32'd0;
        obs_if.retire_mem_rdata = 32'd0;
        obs_if.retire_mem_be = 4'b1111;
        obs_if.retire_except = 0;
        obs_if.retire_except_code = 5'd0;
        obs_if.retire_bd = 0;
        obs_if.retire_eret = 0;
        obs_if.mailbox_valid = 0;
        obs_if.mailbox_wdata = 32'd0;
        obs_if.ex_reg_write = 0;
        obs_if.ex_pc = 32'd0;
        obs_if.jtag_axi_state = 3'd0;
        obs_if.cpu_cp0_except_req = 0;
        obs_if.cpu_cp0_except_code = 5'd0;
        obs_if.cpu_cp0_intr_req = 0;
        obs_if.cpu_cp0_eret = 0;
        obs_if.cpu_cp0_exl = 0;
        obs_if.cpu_cp0_epc = 32'd0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (cur_record = 0; cur_record < total_records; cur_record = cur_record + 1) begin
            obs_if.retire_valid <= 1'b1;
            obs_if.retire_pc <= 32'h88000000 + (cur_record * 4);
            obs_if.retire_next_pc <= 32'h88000004 + (cur_record * 4);
            obs_if.retire_instr <= 32'h24420001;
            obs_if.retire_gpr_we <= 1'b1;
            obs_if.retire_gpr_addr <= 5'd2;
            obs_if.retire_gpr_data <= cur_record;
            obs_if.retire_gpr_state[2*32 +: 32] <= cur_record;
            @(posedge clk);
        end
        obs_if.retire_valid <= 1'b0;
        repeat (5) @(posedge clk);
        $display("TB_RETIRE_TRACE_PRODUCER_DONE records=%0d", total_records);
        $finish;
    end
endmodule
