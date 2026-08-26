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
    string trace_path;

    function automatic integer known_int(input logic [31:0] value);
        known_int = (^value === 1'bx) ? 0 : value;
    endfunction

    function automatic integer known_bit(input logic value);
        known_bit = (value === 1'b1) ? 1 : 0;
    endfunction

    initial begin
        if (!$value$plusargs("RETIRE_TRACE=%s", trace_path))
            trace_path = "retire_trace.jsonl";
        fd = $fopen(trace_path, "w");
        if (fd == 0) $fatal(1, "cannot open RETIRE_TRACE=%s", trace_path);
    end

    always @(posedge clk) begin
        if (rst_n && obs_if.retire_valid) begin
            $fdisplay(fd,
              "{\"schema\":\"%08x\",\"pc\":\"%08x\",\"instr\":\"%08x\",\"next_pc\":\"%08x\",\"gpr_we\":%0d,\"gpr_addr\":%0d,\"gpr_data\":\"%08x\",\"cp0_we\":%0d,\"cp0_addr\":%0d,\"cp0_sel\":%0d,\"cp0_data\":\"%08x\",\"mem_valid\":%0d,\"mem_read\":%0d,\"mem_write\":%0d,\"mem_addr\":\"%08x\",\"mem_wdata\":\"%08x\",\"mem_be\":\"%x\",\"mem_rdata\":\"%08x\",\"except\":%0d,\"except_code\":%0d,\"bd\":%0d,\"eret\":%0d}",
              known_int(obs_if.retire_schema), known_int(obs_if.retire_pc),
              known_int(obs_if.retire_instr), known_int(obs_if.retire_next_pc),
              known_bit(obs_if.retire_gpr_we), known_int(obs_if.retire_gpr_addr),
              known_int(obs_if.retire_gpr_data), known_bit(obs_if.retire_cp0_we),
              known_int(obs_if.retire_cp0_addr), known_int(obs_if.retire_cp0_sel),
              known_int(obs_if.retire_cp0_data), known_bit(obs_if.retire_mem_valid),
              known_bit(obs_if.retire_mem_read), known_bit(obs_if.retire_mem_write),
              obs_if.retire_mem_addr, obs_if.retire_mem_wdata,
              obs_if.retire_mem_be, obs_if.retire_mem_rdata,
              known_bit(obs_if.retire_except), known_int(obs_if.retire_except_code),
              // `retire_bd` is also used internally as the pipeline delay-slot
              // marker.  The trace schema reserves BD for an architectural
              // exception payload, so suppress it on ordinary retire records.
              known_bit(obs_if.retire_except && obs_if.retire_bd),
              known_bit(obs_if.retire_eret));
        end
    end

    final if (fd != 0) $fclose(fd);
endmodule

`endif
