`timescale 1ns/1ps

module tb_mips_mem_stage_llsc_alignment;
    reg [31:0] mem_ex_out;
    reg [31:0] mem_val_rt;
    reg mem_read, mem_write;
    reg [2:0] mem_op;
    reg mem_done, enable_nonblocking_load;
    reg reverse_endian;
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
        .reverse_endian(reverse_endian),
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

    task automatic check_reverse_case;
        input [31:0] addr;
        input read_en;
        input write_en;
        input [2:0] op;
        input [31:0] expect_wdata;
        input [3:0] expect_be;
        input [31:0] expect_rdata;
        begin
            mem_ex_out = addr;
            mem_read = read_en;
            mem_write = write_en;
            mem_op = op;
            #1;
            if (dmem_wdata !== expect_wdata || dmem_be !== expect_be ||
                mem_rdata_ext !== expect_rdata) begin
                $display("FAIL reverse addr=%h read=%b write=%b op=%b wdata=%h/%h be=%b/%b rdata=%h/%h",
                         addr, read_en, write_en, op, dmem_wdata, expect_wdata,
                         dmem_be, expect_be, mem_rdata_ext, expect_rdata);
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
        reverse_endian = 0;
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

        // Reverse-endian data references map user byte 0 to the high cache
        // lane and use the big-endian merge forms.  The default little-endian
        // path above remains unchanged.
        reverse_endian = 1'b1;
        dmem_rdata = 32'h1122_3344;
        mem_val_rt = 32'hA1B2_C3D4;
        check_reverse_case(32'h0000_0000, 1'b1, 1'b0, 3'b000,
                           32'd0, 4'b0000, 32'h0000_0011); // LB
        check_reverse_case(32'h0000_0000, 1'b1, 1'b0, 3'b010,
                           32'd0, 4'b0000, 32'h0000_1122); // LH
        check_reverse_case(32'h0000_0000, 1'b0, 1'b1, 3'b000,
                           32'hD4D4_D4D4, 4'b1000, 32'h1122_3344); // SB
        check_reverse_case(32'h0000_0000, 1'b0, 1'b1, 3'b010,
                           32'hC3D4_C3D4, 4'b1100, 32'h1122_3344); // SH
        check_reverse_case(32'h0000_0001, 1'b1, 1'b0, 3'b101,
                           32'd0, 4'b0000, 32'h2233_44D4); // LWL
        check_reverse_case(32'h0000_0002, 1'b1, 1'b0, 3'b110,
                           32'd0, 4'b0000, 32'hA111_2233); // LWR
        check_reverse_case(32'h0000_0001, 1'b0, 1'b1, 3'b101,
                           32'hB2C3_D400, 4'b1110, 32'h1122_3344); // SWL
        check_reverse_case(32'h0000_0002, 1'b0, 1'b1, 3'b110,
                           32'h00A1_B2C3, 4'b0111, 32'h1122_3344); // SWR

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_mem_stage_llsc_alignment");
        else
            $display("REGRESSION_TEST_FAIL mips_mem_stage_llsc_alignment failures=%0d", failures);
        $finish;
    end
endmodule
