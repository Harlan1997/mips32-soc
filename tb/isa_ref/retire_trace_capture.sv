`ifndef RETIRE_TRACE_CAPTURE_SV
`define RETIRE_TRACE_CAPTURE_SV

// Verification-only JSONL sink.  The producer is deliberately a plain
// observation interface so this sink can be reused by UVM and directed tops.
module retire_trace_capture (
    input logic clk,
    input logic rst_n,
    soc_observation_if.consumer obs_if
);
    integer fd;
    integer retire_count;
    integer max_retire_records;
    string trace_path;
    logic [1023:0] fpr_state_d1, fpr_state_d2;
    logic [31:0] fcsr_state_d1, fcsr_state_d2;

    function automatic integer known_int(input logic [31:0] value);
        known_int = (^value === 1'bx) ? 0 : value;
    endfunction

    function automatic integer known_bit(input logic value);
        known_bit = (value === 1'b1) ? 1 : 0;
    endfunction

    initial begin
        if (!$value$plusargs("RETIRE_TRACE=%s", trace_path))
            trace_path = "retire_trace.jsonl";
        max_retire_records = 1000000;
        void'($value$plusargs("RETIRE_TRACE_MAX_RECORDS=%d", max_retire_records));
        retire_count = 0;
        fd = $fopen(trace_path, "w");
        if (fd == 0) $fatal(1, "cannot open RETIRE_TRACE=%s", trace_path);
    end

    // FPU state is committed in the CPU ID stage, while the common retire
    // observation is the later MEM/WB commit. Two clock history stages align
    // the state snapshot with the instruction represented by wb_valid.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fpr_state_d1 <= 1024'd0;
            fpr_state_d2 <= 1024'd0;
            fcsr_state_d1 <= 32'd0;
            fcsr_state_d2 <= 32'd0;
        end else begin
            fpr_state_d2 <= fpr_state_d1;
            fpr_state_d1 <= obs_if.retire_fpr_state;
            fcsr_state_d2 <= fcsr_state_d1;
            fcsr_state_d1 <= obs_if.retire_fcsr_state;
        end
        if (rst_n && obs_if.retire_valid) begin
            if (max_retire_records > 0 && retire_count >= max_retire_records)
                $fatal(2, "RETIRE_TRACE_MAX_RECORDS exceeded: path=%s limit=%0d",
                       trace_path, max_retire_records);
            $fdisplay(fd,
              "{\"schema\":\"%08x\",\"pc\":\"%08x\",\"instr\":\"%08x\",\"next_pc\":\"%08x\",\"gpr_we\":%0d,\"gpr_addr\":%0d,\"gpr_data\":\"%08x\",\"cp0_we\":%0d,\"cp0_addr\":%0d,\"cp0_sel\":%0d,\"cp0_data\":\"%08x\",\"fpr_state\":\"%0256x\",\"fcsr_state\":\"%08x\",\"mem_valid\":%0d,\"mem_read\":%0d,\"mem_write\":%0d,\"mem_addr\":\"%08x\",\"mem_wdata\":\"%08x\",\"mem_be\":\"%x\",\"mem_rdata\":\"%08x\",\"except\":%0d,\"except_code\":%0d,\"bd\":%0d,\"eret\":%0d}",
              known_int(obs_if.retire_schema), known_int(obs_if.retire_pc),
              known_int(obs_if.retire_instr), known_int(obs_if.retire_next_pc),
              known_bit(obs_if.retire_gpr_we), known_int(obs_if.retire_gpr_addr),
              known_int(obs_if.retire_gpr_data), known_bit(obs_if.retire_cp0_we),
              known_int(obs_if.retire_cp0_addr), known_int(obs_if.retire_cp0_sel),
              known_int(obs_if.retire_cp0_data), fpr_state_d2,
              known_int(fcsr_state_d2), known_bit(obs_if.retire_mem_valid),
              known_bit(obs_if.retire_mem_read), known_bit(obs_if.retire_mem_write),
              obs_if.retire_mem_addr, obs_if.retire_mem_wdata,
              obs_if.retire_mem_be, obs_if.retire_mem_rdata,
              known_bit(obs_if.retire_except), known_int(obs_if.retire_except_code),
              // `retire_bd` is also used internally as the pipeline delay-slot
              // marker.  The trace schema reserves BD for an architectural
              // exception payload, so suppress it on ordinary retire records.
              known_bit(obs_if.retire_except && obs_if.retire_bd),
              known_bit(obs_if.retire_eret));
            retire_count = retire_count + 1;
        end
    end

    final if (fd != 0) $fclose(fd);
endmodule

`endif
