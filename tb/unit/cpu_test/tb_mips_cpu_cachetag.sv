// CPU pipeline directed test for the D-cache TagLo/TagHi/SYNC contract.
`timescale 1ns/1ps

module tb_mips_cpu_cachetag;
    localparam [31:0] TAGLO_VALUE = 32'h0061_2345;
    localparam [31:0] TAGHI_VALUE = 32'h0000_1234;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire        inst_req;
    wire [31:0] inst_addr;
    reg  [31:0] inst_rdata;
    wire        data_req, data_we;
    wire [31:0] data_addr, data_wdata;
    wire [3:0]  data_be;
    wire        data_uncacheable;
    wire        cache_op_valid;
    wire [4:0]  cache_op;
    wire [31:0] cache_op_addr;
    reg         cache_op_done = 1'b0;
    wire        cache_op_error = 1'b0;
    reg  [31:0] data_cache_tag_rdata = TAGLO_VALUE;
    wire [31:0] data_cache_tag_wdata;
    wire [31:0] data_rdata = 32'd0;

    wire inst_addr_ok = 1'b1;
    wire inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0;
    wire inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1;
    wire data_data_ok = 1'b1;
    wire data_bus_error = 1'b0;
    wire data_cache_error = 1'b0;
    wire debug_stall, debug_flush;

    reg [31:0] imem [0:255];
    reg [31:0] fetch_addr_q;
    reg        prev_op_valid;
    integer   op_count;
    integer   i;
    integer   failures;

    always @(*) inst_rdata = imem[fetch_addr_q[9:2]];

    // The model completes each maintenance request one cycle after acceptance.
    // TagLo read data is returned by the model for Index_Load_Tag_D.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_addr_q <= 32'd0;
            cache_op_done <= 1'b0;
            prev_op_valid <= 1'b0;
            op_count <= 0;
        end else begin
            fetch_addr_q <= inst_addr;
            cache_op_done <= cache_op_valid;
            if (cache_op_valid && !prev_op_valid) begin
                case (op_count)
                    0: begin
                        if (cache_op !== 5'b01001) begin
                            $display("FAIL cache op[0]=%b expected Index_Store_Tag_D", cache_op);
                            failures = failures + 1;
                        end
                        if (cache_op_addr !== 32'h0000_0800) begin
                            $display("FAIL store address=%h expected 00000800", cache_op_addr);
                            failures = failures + 1;
                        end
                        if (data_cache_tag_wdata !== TAGLO_VALUE) begin
                            $display("FAIL TagLo write data=%h expected %h",
                                     data_cache_tag_wdata, TAGLO_VALUE);
                            failures = failures + 1;
                        end
                    end
                    1: begin
                        if (cache_op !== 5'b00101) begin
                            $display("FAIL cache op[1]=%b expected Index_Load_Tag_D", cache_op);
                            failures = failures + 1;
                        end
                        if (cache_op_addr !== 32'h0000_0800) begin
                            $display("FAIL load address=%h expected 00000800", cache_op_addr);
                            failures = failures + 1;
                        end
                    end
                    2: begin
                        if (cache_op !== 5'b11110) begin
                            $display("FAIL cache op[2]=%b expected SYNC barrier", cache_op);
                            failures = failures + 1;
                        end
                        if (cache_op_addr !== 32'd0) begin
                            $display("FAIL SYNC address=%h expected zero", cache_op_addr);
                            failures = failures + 1;
                        end
                    end
                    default: begin
                        $display("FAIL unexpected extra cache op=%b", cache_op);
                        failures = failures + 1;
                    end
                endcase
                op_count = op_count + 1;
            end
            prev_op_valid <= cache_op_valid;
        end
    end

    mips_cpu u_cpu (
        .clk(clk), .rst_n(rst_n),
        .inst_req(inst_req), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok),
        .inst_bus_error(inst_bus_error), .inst_cache_error(inst_cache_error),
        .inst_rdata(inst_rdata),
        .data_req(data_req), .data_we(data_we), .data_addr(data_addr),
        .data_wdata(data_wdata), .data_be(data_be),
        .data_uncacheable(data_uncacheable),
        .data_cache_op_valid(cache_op_valid), .data_cache_op(cache_op),
        .data_cache_op_addr(cache_op_addr), .data_cache_op_done(cache_op_done),
        .data_cache_op_error(cache_op_error),
        .data_cache_tag_rdata(data_cache_tag_rdata),
        .data_cache_tag_wdata(data_cache_tag_wdata),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok),
        .data_bus_error(data_bus_error), .data_cache_error(data_cache_error),
        .data_rdata(data_rdata), .ext_int(6'd0),
        .debug_stall(debug_stall), .debug_flush(debug_flush)
    );

    initial begin
        failures = 0;
        for (i = 0; i < 256; i = i + 1) imem[i] = 32'd0;

        // t0 = 0x00612345, then MTC0 TagLo and store it into way 1, set 0.
        imem[0] = 32'h3c08_0061; // LUI   t0, 0x0061
        imem[1] = 32'h3508_2345; // ORI   t0, t0, 0x2345
        imem[2] = 32'h4088_e000; // MTC0  t0, TagLo
        imem[3] = 32'hbc09_0800; // CACHE Index_Store_Tag_D, 0x800($0)

        // Exercise the independent TagHi CP0 register before the load-tag op.
        imem[4] = 32'h240a_1234; // ADDIU t2, $0, 0x1234
        imem[5] = 32'h408a_e800; // MTC0  t2, TagHi
        imem[6] = 32'h400b_e800; // MFC0  t3, TagHi
        imem[7] = 32'hbc05_0800; // CACHE Index_Load_Tag_D, 0x800($0)
        imem[8] = 32'h4009_e000; // MFC0  t1, TagLo
        imem[9] = 32'h0000_000f; // SYNC

        #17 rst_n = 1'b1;
        #500;
        if (op_count != 3) begin
            $display("FAIL cache op count=%0d expected 3", op_count);
            failures = failures + 1;
        end
        if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[9] !== TAGLO_VALUE) begin
            $display("FAIL MFC0 TagLo readback=%h expected %h",
                     u_cpu.u_mips_id_stage.u_mips_regfile.regs[9], TAGLO_VALUE);
            failures = failures + 1;
        end
        if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[11] !== TAGHI_VALUE) begin
            $display("FAIL MFC0 TagHi readback=%h expected %h",
                     u_cpu.u_mips_id_stage.u_mips_regfile.regs[11], TAGHI_VALUE);
            failures = failures + 1;
        end
        if (u_cpu.u_mips_cp0.cp0_cause[6:2] !== 5'd0) begin
            $display("FAIL unexpected exception Cause.ExcCode=%0d",
                     u_cpu.u_mips_cp0.cp0_cause[6:2]);
            failures = failures + 1;
        end
        if (failures != 0)
            $display("REGRESSION_TEST_FAIL mips_cpu_cachetag failures=%0d", failures);
        else
            $display("REGRESSION_TEST_SUCCESS mips_cpu_cachetag");
        $finish;
    end
endmodule
