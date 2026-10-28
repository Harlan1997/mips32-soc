`ifndef RETIRE_TRACE_CAPTURE_SV
`define RETIRE_TRACE_CAPTURE_SV

`include "soc_config.vh"

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
    integer stop_at_max_records;
    integer compact_fpr;
    integer trace_schema_override;
    integer configured_trace_schema;
    integer flush_records;
    integer count_fd;
    integer count_schedule_started;
    integer count_schedule_retire_base;
    logic [31:0] count_schedule_start_pc;
    integer cycle_count;
    integer cycle_fd;
    integer cycle_schedule_started;
    integer cycle_schedule_retire_base;
    integer cycle_schedule_interval;
    integer cycle_schedule_last_seq;
    logic [31:0] cycle_schedule_start_pc;
    string trace_path;
    string count_schedule_path;
    string cycle_schedule_path;
    string fpr_text;
    logic [1023:0] fpr_state_d1, fpr_state_d2;
    logic [31:0] fcsr_state_d1, fcsr_state_d2;
    logic [1023:0] gpr_state_post;
    logic [63:0] retired_hilo_state;
    logic [63:0] hilo_result_queue [0:15];
    integer hilo_queue_head, hilo_queue_tail, hilo_queue_count;
    string state_fields;

    wire hilo_trace_enabled = (`SOC_RETIRE_TRACE_ENABLE != 0) &&
        ((trace_schema_override != 0 ? configured_trace_schema :
          known_int(obs_if.retire_schema)) == 32'h0002_0000);

    function automatic integer known_int(input logic [31:0] value);
        known_int = (^value === 1'bx) ? 0 : value;
    endfunction

    function automatic integer known_bit(input logic value);
        known_bit = (value === 1'b1) ? 1 : 0;
    endfunction

    function automatic logic writes_hilo(input logic [31:0] instruction);
        logic [5:0] opcode;
        logic [5:0] funct;
        begin
            opcode = instruction[31:26];
            funct = instruction[5:0];
            writes_hilo = (opcode == 6'h00 &&
                           (funct == 6'h11 || funct == 6'h13 ||
                            (funct >= 6'h18 && funct <= 6'h1b))) ||
                          (opcode == 6'h1c &&
                           (funct == 6'h00 || funct == 6'h01 ||
                            funct == 6'h02 || funct == 6'h04 ||
                            funct == 6'h05));
        end
    endfunction

    function automatic logic [31:0] double_store_high_word(
        input logic [31:0] instruction,
        input logic [1023:0] fpr_state
    );
        integer fpr_index;
        begin
            double_store_high_word = 32'd0;
            // This RTL stores a double's low word in the even FPR and high
            // word in the following odd FPR; fpr_state keeps FPR0 at bit 0.
            if (instruction[31:26] == 6'b111101 ||
                (instruction[31:26] == 6'b010011 &&
                 instruction[5:0] == 6'h09)) begin
                fpr_index = (instruction[31:26] == 6'b010011) ?
                            instruction[15:11] : instruction[20:16];
                fpr_index = (fpr_index == 31) ? 0 : fpr_index + 1;
                double_store_high_word = fpr_state[fpr_index*32 +: 32];
            end
        end
    endfunction

    initial begin
        if (!$value$plusargs("RETIRE_TRACE=%s", trace_path))
            trace_path = "retire_trace.jsonl";
        max_retire_records = 1000000;
        void'($value$plusargs("RETIRE_TRACE_MAX_RECORDS=%d", max_retire_records));
        stop_at_max_records = 0;
        void'($value$plusargs("RETIRE_TRACE_STOP_AT_MAX=%d", stop_at_max_records));
        compact_fpr = 0;
        void'($value$plusargs("RETIRE_TRACE_COMPACT_FPR=%d", compact_fpr));
        trace_schema_override = 0;
        configured_trace_schema = 32'h00010000;
        if ($value$plusargs("RETIRE_TRACE_SCHEMA=%h", configured_trace_schema))
            trace_schema_override = 1;
        flush_records = 0;
        void'($value$plusargs("RETIRE_TRACE_FLUSH=%d", flush_records));
        count_fd = 0;
        count_schedule_started = 0;
        count_schedule_retire_base = 0;
        count_schedule_start_pc = 32'd0;
        cycle_count = 0;
        cycle_fd = 0;
        cycle_schedule_started = 0;
        cycle_schedule_retire_base = 0;
        cycle_schedule_interval = 8;
        cycle_schedule_last_seq = -1;
        cycle_schedule_start_pc = 32'd0;
        if ($value$plusargs("RETIRE_COUNT_SCHEDULE=%s", count_schedule_path)) begin
            if (!$value$plusargs("RETIRE_COUNT_SCHEDULE_START_PC=%h",
                                 count_schedule_start_pc))
                $fatal(1, "RETIRE_COUNT_SCHEDULE_START_PC is required with RETIRE_COUNT_SCHEDULE");
            count_fd = $fopen(count_schedule_path, "w");
            if (count_fd == 0)
                $fatal(1, "cannot open RETIRE_COUNT_SCHEDULE=%s",
                       count_schedule_path);
        end
        if ($value$plusargs("RETIRE_CYCLE_SCHEDULE=%s", cycle_schedule_path)) begin
            if (!$value$plusargs("RETIRE_CYCLE_SCHEDULE_START_PC=%h",
                                 cycle_schedule_start_pc))
                $fatal(1, "RETIRE_CYCLE_SCHEDULE_START_PC is required with RETIRE_CYCLE_SCHEDULE");
            void'($value$plusargs("RETIRE_CYCLE_SCHEDULE_INTERVAL=%d",
                                  cycle_schedule_interval));
            if (cycle_schedule_interval <= 0)
                $fatal(1, "RETIRE_CYCLE_SCHEDULE_INTERVAL must be positive");
            cycle_fd = $fopen(cycle_schedule_path, "w");
            if (cycle_fd == 0)
                $fatal(1, "cannot open RETIRE_CYCLE_SCHEDULE=%s",
                       cycle_schedule_path);
            $fdisplay(cycle_fd,
                      "# cpu-cycle-schedule-v1 interval=%0d start_pc=%08x",
                      cycle_schedule_interval, cycle_schedule_start_pc);
        end
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
            cycle_count <= 0;
            retired_hilo_state = 64'd0;
            hilo_queue_head = 0;
            hilo_queue_tail = 0;
            hilo_queue_count = 0;
        end else begin
            fpr_state_d2 <= fpr_state_d1;
            fpr_state_d1 <= obs_if.retire_fpr_state;
            fcsr_state_d2 <= fcsr_state_d1;
            fcsr_state_d1 <= obs_if.retire_fcsr_state;
            cycle_count <= cycle_count + 1;
            if (hilo_trace_enabled && obs_if.retire_mdu_done &&
                obs_if.retire_mdu_op != 4'd4 &&
                obs_if.retire_mdu_op != 4'd5) begin
                if (hilo_queue_count == 16)
                    $fatal(1, "HI/LO result queue overflow at retire=%0d",
                           retire_count);
                hilo_result_queue[hilo_queue_tail] = obs_if.retire_hilo_state;
                hilo_queue_tail = (hilo_queue_tail + 1) % 16;
                hilo_queue_count = hilo_queue_count + 1;
            end
            if (hilo_trace_enabled && obs_if.retire_valid &&
                writes_hilo(obs_if.retire_instr) &&
                !obs_if.retire_except) begin
                if (hilo_queue_count == 0)
                    $fatal(1, "missing completed HI/LO result at retire=%0d",
                           retire_count);
                retired_hilo_state = hilo_result_queue[hilo_queue_head];
                hilo_queue_head = (hilo_queue_head + 1) % 16;
                hilo_queue_count = hilo_queue_count - 1;
            end
        end
        if (rst_n && obs_if.retire_valid) begin
            if (trace_schema_override != 0 &&
                configured_trace_schema != 32'h00010000 &&
                configured_trace_schema != 32'h00020000)
                $fatal(1, "unsupported RETIRE_TRACE_SCHEMA=%08x",
                       configured_trace_schema);
            if (count_fd != 0 && !count_schedule_started &&
                obs_if.retire_pc == count_schedule_start_pc) begin
                // QEMU system mode starts directly at the ELF entry; RTL
                // reaches it through the Boot ROM. Rebase samples to this
                // shared first retire so their sequence numbers match.
                count_schedule_started = 1;
                count_schedule_retire_base = retire_count;
            end
            if (cycle_fd != 0 && !cycle_schedule_started &&
                obs_if.retire_pc == cycle_schedule_start_pc) begin
                cycle_schedule_started = 1;
                cycle_schedule_retire_base = retire_count;
                $fdisplay(cycle_fd, "0 %0d", cycle_count);
                cycle_schedule_last_seq = 0;
            end
            if (cycle_fd != 0 && cycle_schedule_started &&
                ((retire_count + 1 - cycle_schedule_retire_base) %
                 cycle_schedule_interval) == 0) begin
                $fdisplay(cycle_fd, "%0d %0d",
                          retire_count + 1 - cycle_schedule_retire_base,
                          cycle_count);
                cycle_schedule_last_seq =
                    retire_count + 1 - cycle_schedule_retire_base;
            end
            if (count_fd != 0 && count_schedule_started &&
                obs_if.retire_instr[31:26] == 6'h10 &&
                obs_if.retire_instr[25:21] == 5'd0 &&
                obs_if.retire_instr[15:11] == 5'd9 &&
                obs_if.retire_instr[2:0] == 3'd0) begin
                $fdisplay(count_fd, "mfc0 %08x %0d %08x %0d",
                          obs_if.retire_pc,
                          obs_if.retire_instr[20:16],
                          obs_if.retire_gpr_data,
                          retire_count - count_schedule_retire_base);
                $fflush(count_fd);
            end
            if (count_fd != 0 && count_schedule_started &&
                obs_if.retire_instr[31:26] == 6'h1f &&
                obs_if.retire_instr[25:21] == 5'd0 &&
                obs_if.retire_instr[15:11] == 5'd2 &&
                obs_if.retire_instr[5:0] == 6'h3b) begin
                $fdisplay(count_fd, "rdhwr %08x %0d %08x %0d",
                          obs_if.retire_pc,
                          obs_if.retire_instr[15:11],
                          obs_if.retire_gpr_data,
                          retire_count - count_schedule_retire_base);
                $fflush(count_fd);
            end
            if (max_retire_records > 0 && retire_count >= max_retire_records &&
                stop_at_max_records != 0) begin
                // A bounded capture is an intentional verification stop.
                $display("RETIRE_TRACE_MAX_RECORDS_REACHED path=%s limit=%0d",
                         trace_path, max_retire_records);
                $finish;
            end else if (max_retire_records > 0 && retire_count >= max_retire_records) begin
                $fatal(2, "RETIRE_TRACE_MAX_RECORDS exceeded: path=%s limit=%0d",
                       trace_path, max_retire_records);
            end else begin
            fpr_text = compact_fpr != 0 ? "0" : $sformatf("%0256x", fpr_state_d2);
            gpr_state_post = obs_if.retire_gpr_state;
            if (obs_if.retire_gpr_we && obs_if.retire_gpr_addr != 5'd0)
                gpr_state_post[obs_if.retire_gpr_addr*32 +: 32] =
                    obs_if.retire_gpr_data;
            if ((trace_schema_override != 0 ? configured_trace_schema :
                 known_int(obs_if.retire_schema)) == 32'h00020000) begin
                if ((^gpr_state_post === 1'bx) ||
                    (^retired_hilo_state === 1'bx))
                    $fatal(1, "unknown full architectural state at retire=%0d",
                           retire_count);
                state_fields = $sformatf(
                    ",\"gpr_state\":\"%0256x\",\"hilo_state\":\"%016x\"",
                    gpr_state_post, retired_hilo_state);
            end else begin
                state_fields = "";
            end
            $fdisplay(fd,
              "{\"retire_seq\":%0d,\"schema\":\"%08x\",\"pc\":\"%08x\",\"instr\":\"%08x\",\"next_pc\":\"%08x\",\"gpr_we\":%0d,\"gpr_addr\":%0d,\"gpr_data\":\"%08x\",\"cp0_we\":%0d,\"cp0_addr\":%0d,\"cp0_sel\":%0d,\"cp0_data\":\"%08x\"%s,\"fpr_state\":\"%s\",\"fcsr_state\":\"%08x\",\"mem_valid\":%0d,\"mem_read\":%0d,\"mem_write\":%0d,\"mem_addr\":\"%08x\",\"mem_wdata\":\"%08x\",\"mem_wdata_hi\":\"%08x\",\"mem_be\":\"%x\",\"mem_rdata\":\"%08x\",\"except\":%0d,\"except_code\":%0d,\"bd\":%0d,\"eret\":%0d}",
              retire_count,
              trace_schema_override != 0 ? configured_trace_schema :
                                           known_int(obs_if.retire_schema),
              known_int(obs_if.retire_pc),
              known_int(obs_if.retire_instr), known_int(obs_if.retire_next_pc),
              known_bit(obs_if.retire_gpr_we), known_int(obs_if.retire_gpr_addr),
              known_int(obs_if.retire_gpr_data), known_bit(obs_if.retire_cp0_we),
              known_int(obs_if.retire_cp0_addr), known_int(obs_if.retire_cp0_sel),
              known_int(obs_if.retire_cp0_data), state_fields, fpr_text,
              known_int(fcsr_state_d2), known_bit(obs_if.retire_mem_valid),
              known_bit(obs_if.retire_mem_read), known_bit(obs_if.retire_mem_write),
              obs_if.retire_mem_addr, obs_if.retire_mem_wdata,
              double_store_high_word(obs_if.retire_instr, fpr_state_d2),
              obs_if.retire_mem_be, obs_if.retire_mem_rdata,
              known_bit(obs_if.retire_except), known_int(obs_if.retire_except_code),
              // `retire_bd` is also used internally as the pipeline delay-slot
              // marker.  The trace schema reserves BD for an architectural
              // exception payload, so suppress it on ordinary retire records.
              known_bit(obs_if.retire_except && obs_if.retire_bd),
              known_bit(obs_if.retire_eret));
            // FIFO consumers must never observe a buffered partial JSON line.
            if (flush_records != 0)
                $fflush(fd);
            retire_count = retire_count + 1;
            end
        end
    end

    final begin
        if (cycle_fd != 0) begin
            if (cycle_schedule_started &&
                (retire_count - cycle_schedule_retire_base) >
                cycle_schedule_last_seq) begin
                $fdisplay(cycle_fd, "%0d %0d",
                          retire_count - cycle_schedule_retire_base,
                          cycle_count);
            end
            $fclose(cycle_fd);
        end
        if (fd != 0) $fclose(fd);
        if (count_fd != 0) $fclose(count_fd);
    end
endmodule

`endif
