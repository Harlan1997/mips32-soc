`timescale 1ns/1ps

module tb_mips_mem_stage_llsc_alignment;
    reg [31:0] mem_ex_out;
    reg [31:0] mem_val_rt;
    reg mem_read, mem_write;
    reg [2:0] mem_op;
    reg mem_done, enable_nonblocking_load;
    reg mem_cache_op_valid;
    reg [4:0] mem_cache_op;
    reg [31:0] dmem_rdata;
    reg dmem_addr_ok, dmem_data_ok, translation_fault;
    reg cache_op_done, cache_op_error;
    wire [31:0] dmem_addr, dmem_wdata;
    wire dmem_we, dmem_en;
    wire [3:0] dmem_be;
    wire stall_req_mem, cache_op_valid, cache_op_fault;
    wire [4:0] cache_op;
    wire [31:0] cache_op_addr, mem_rdata_ext;
    wire adel_exception, ades_exception;
    integer failures;

    mips_mem_stage dut (
        .mem_ex_out(mem_ex_out), .mem_val_rt(mem_val_rt),
        .mem_read(mem_read), .mem_write(mem_write), .mem_op(mem_op),
        .mem_done(mem_done), .enable_nonblocking_load(enable_nonblocking_load),
        .mem_cache_op_valid(mem_cache_op_valid), .mem_cache_op(mem_cache_op),
        .dmem_rdata(dmem_rdata), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_we(dmem_we), .dmem_be(dmem_be),
        .dmem_en(dmem_en), .dmem_addr_ok(dmem_addr_ok),
        .dmem_data_ok(dmem_data_ok), .translation_fault(translation_fault),
        .cache_op_done(cache_op_done), .cache_op_error(cache_op_error),
        .stall_req_mem(stall_req_mem), .cache_op_valid(cache_op_valid),
        .cache_op(cache_op), .cache_op_addr(cache_op_addr),
        .cache_op_fault(cache_op_fault), .mem_rdata_ext(mem_rdata_ext),
        .adel_exception(adel_exception), .ades_exception(ades_exception)
    );

    task automatic check_case;
        input [31:0] addr;
        input read_en;
        input write_en;
        input [2:0] op;
        input expect_adel;
        input expect_ades;
        input expect_en;
        begin
            mem_ex_out = addr;
            mem_read = read_en;
            mem_write = write_en;
            mem_op = op;
            #1;
            if (adel_exception !== expect_adel || ades_exception !== expect_ades ||
                dmem_en !== expect_en) begin
                $display("FAIL addr=%h read=%b write=%b op=%b adel=%b/%b ades=%b/%b en=%b/%b",
                         addr, read_en, write_en, op, adel_exception, expect_adel,
                         ades_exception, expect_ades, dmem_en, expect_en);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        mem_ex_out = 0;
        mem_val_rt = 32'h1122_3344;
        mem_read = 0;
        mem_write = 0;
        mem_op = 0;
        mem_done = 0;
        enable_nonblocking_load = 0;
        mem_cache_op_valid = 0;
        mem_cache_op = 0;
        dmem_rdata = 0;
        dmem_addr_ok = 1;
        dmem_data_ok = 1;
        translation_fault = 0;
        cache_op_done = 0;
        cache_op_error = 0;

        check_case(32'h0000_0001, 1'b1, 1'b0, 3'b111, 1'b1, 1'b0, 1'b0); // LL
        check_case(32'h0000_0000, 1'b1, 1'b0, 3'b111, 1'b0, 1'b0, 1'b1); // LL
        check_case(32'h0000_0002, 1'b0, 1'b1, 3'b111, 1'b0, 1'b1, 1'b0); // SC
        check_case(32'h0000_0000, 1'b0, 1'b1, 3'b111, 1'b0, 1'b0, 1'b1); // SC
        check_case(32'h0000_0001, 1'b1, 1'b0, 3'b101, 1'b0, 1'b0, 1'b1); // LWL

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_mem_stage_llsc_alignment");
        else
            $display("REGRESSION_TEST_FAIL mips_mem_stage_llsc_alignment failures=%0d", failures);
        $finish;
    end
endmodule
