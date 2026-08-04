// Integrated I-cache index tag ABI gate.
// The CPU must route the I-cache index tag operations away from D-cache while
// preserving the existing MEM-stage completion and CP0 TagLo contract.
`timescale 1ns/1ps

module tb_mips_core_icache_tag;
    localparam [31:0] TAGLO_I_VALUE = 32'h0041_2345;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire [3:0]  inst_arid;
    wire [31:0] inst_araddr;
    wire [7:0]  inst_arlen;
    wire [2:0]  inst_arsize;
    wire [1:0]  inst_arburst, inst_arlock;
    wire [3:0]  inst_arcache;
    wire [2:0]  inst_arprot;
    wire        inst_arvalid;
    wire        inst_arready;
    reg  [3:0]  inst_rid = 4'd0;
    reg  [31:0] inst_rdata = 32'd0;
    reg  [1:0]  inst_rresp = 2'b00;
    reg         inst_rlast = 1'b0;
    reg         inst_rvalid = 1'b0;
    wire        inst_rready;

    wire [3:0]  inst_awid;
    wire [31:0] inst_awaddr;
    wire [7:0]  inst_awlen;
    wire [2:0]  inst_awsize;
    wire [1:0]  inst_awburst, inst_awlock;
    wire [3:0]  inst_awcache;
    wire [2:0]  inst_awprot;
    wire        inst_awvalid;
    wire [31:0] inst_wdata;
    wire [3:0]  inst_wstrb;
    wire        inst_wlast, inst_wvalid, inst_bready;
    wire [3:0]  inst_bid = 4'd0;
    wire [1:0]  inst_bresp = 2'b00;
    wire        inst_bvalid = 1'b0;
    wire        inst_wready = 1'b1;
    wire        inst_awready = 1'b1;

    wire [3:0]  data_awid;
    wire [31:0] data_awaddr;
    wire [7:0]  data_awlen;
    wire [2:0]  data_awsize;
    wire [1:0]  data_awburst, data_awlock;
    wire [3:0]  data_awcache;
    wire [2:0]  data_awprot;
    wire        data_awvalid;
    wire        data_awready = 1'b1;
    wire [31:0] data_wdata;
    wire [3:0]  data_wstrb;
    wire        data_wlast, data_wvalid;
    wire        data_wready = 1'b1;
    wire [3:0]  data_bid = 4'd0;
    wire [1:0]  data_bresp = 2'b00;
    wire        data_bvalid = 1'b0;
    wire        data_bready;
    wire [3:0]  data_arid;
    wire [31:0] data_araddr;
    wire [7:0]  data_arlen;
    wire [2:0]  data_arsize;
    wire [1:0]  data_arburst, data_arlock;
    wire [3:0]  data_arcache;
    wire [2:0]  data_arprot;
    wire        data_arvalid;
    wire        data_arready = 1'b1;
    wire [3:0]  data_rid = 4'd0;
    wire [31:0] data_rdata = 32'd0;
    wire [1:0]  data_rresp = 2'b00;
    wire        data_rlast = 1'b1;
    wire        data_rvalid = 1'b0;
    wire        data_rready;
    wire        debug_stall, debug_flush;

    reg        i_active;
    reg [31:0] i_base;
    reg [2:0]  i_beat;
    integer    ar_count;
    integer    op_count;
    integer    failures;
    integer    cycles;
    reg        prev_op_valid;
    reg        stall_seen;

    function [31:0] program_word(input [31:0] addr);
        begin
            program_word = 32'h0000_0000;
            if ((addr & 32'hffff_ffe0) == 32'h0000_0000) begin
                case (addr[4:2])
                    3'd0: program_word = 32'h3c08_0041; // LUI t0, 0x0041
                    3'd1: program_word = 32'h3508_2345; // ORI t0, t0, 0x2345
                    3'd2: program_word = 32'h4088_e000; // MTC0 t0, TagLo
                    3'd3: program_word = 32'hbc08_2800; // CACHE Index_Store_Tag_I
                    3'd4: program_word = 32'hbc00_2800; // CACHE Index_Invalidate_I
                    3'd5: program_word = 32'hbc04_2800; // CACHE Index_Load_Tag_I
                    3'd6: program_word = 32'h041f_0000; // SYNCI 0($zero)
                    3'd7: program_word = 32'h4009_e000; // MFC0 t1, TagLo
                    default: program_word = 32'h0000_0000;
                endcase
            end
        end
    endfunction

    assign inst_arready = !i_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_active    <= 1'b0;
            i_base      <= 32'd0;
            i_beat      <= 3'd0;
            inst_rvalid <= 1'b0;
            inst_rlast  <= 1'b0;
            inst_rdata  <= 32'd0;
            ar_count    <= 0;
        end else begin
            if (inst_arvalid && inst_arready && !i_active) begin
                i_active <= 1'b1;
                i_base   <= inst_araddr;
                i_beat   <= 3'd0;
                ar_count <= ar_count + 1;
            end
            if (i_active && !inst_rvalid) begin
                inst_rvalid <= 1'b1;
                inst_rdata  <= program_word(i_base + (i_beat << 2));
                inst_rresp  <= 2'b00;
                inst_rlast  <= (i_beat == 3'd7);
            end
            if (inst_rvalid && inst_rready) begin
                inst_rvalid <= 1'b0;
                if (inst_rlast) begin
                    i_active   <= 1'b0;
                    inst_rlast <= 1'b0;
                end else begin
                    i_beat <= i_beat + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_count      <= 0;
            failures      <= 0;
            cycles        <= 0;
            prev_op_valid <= 1'b0;
            stall_seen    <= 1'b0;
        end else begin
            cycles <= cycles + 1;
            if (u_core.u_cpu.data_cache_op_valid && debug_stall)
                stall_seen <= 1'b1;
            if (u_core.u_cpu.data_cache_op_valid && !prev_op_valid) begin
                case (op_count)
                    0: begin
                        if (u_core.u_cpu.data_cache_op !== 5'b01000)
                            failures = failures + 1;
                        if (!u_core.icache_op_valid || u_core.dcache_op_valid)
                            failures = failures + 1;
                        if (u_core.u_cpu.data_cache_op_addr !== 32'h0000_2800)
                            failures = failures + 1;
                    end
                    1: begin
                        if (u_core.u_cpu.data_cache_op !== 5'b00000)
                            failures = failures + 1;
                        if (!u_core.icache_op_valid || u_core.dcache_op_valid)
                            failures = failures + 1;
                    end
                    2: begin
                        if (u_core.u_cpu.data_cache_op !== 5'b00100)
                            failures = failures + 1;
                        if (!u_core.icache_op_valid || u_core.dcache_op_valid)
                            failures = failures + 1;
                    end
                    3: begin
                        if (u_core.u_cpu.data_cache_op !== 5'b10000)
                            failures = failures + 1;
                        if (!u_core.icache_op_valid || u_core.dcache_op_valid)
                            failures = failures + 1;
                    end
                    default: ;
                endcase
                op_count = op_count + 1;
            end
            prev_op_valid <= u_core.u_cpu.data_cache_op_valid;

            if ((op_count == 4) &&
                (u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[9] === 32'd0)) begin
                if (u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] !== 5'd0)
                    failures = failures + 1;
                if (ar_count != 2)
                    failures = failures + 1;
                if (!stall_seen)
                    failures = failures + 1;
                if (failures != 0)
                    $display("REGRESSION_TEST_FAIL mips_core_icache_tag failures=%0d ops=%0d ar_count=%0d", failures, op_count, ar_count);
                else
                    $display("REGRESSION_TEST_SUCCESS mips_core_icache_tag ops=%0d ar_count=%0d", op_count, ar_count);
                $finish;
            end

            if (cycles > 5000) begin
                if (op_count != 4)
                    failures = failures + 1;
                if (u_core.u_cpu.u_mips_id_stage.u_mips_regfile.regs[9] !== 32'd0)
                    failures = failures + 1;
                if (u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] !== 5'd0)
                    failures = failures + 1;
                if (ar_count != 2)
                    failures = failures + 1;
                if (failures != 0)
                    $display("REGRESSION_TEST_FAIL mips_core_icache_tag failures=%0d ops=%0d ar_count=%0d", failures, op_count, ar_count);
                else
                    $display("REGRESSION_TEST_SUCCESS mips_core_icache_tag ops=%0d ar_count=%0d", op_count, ar_count);
                $finish;
            end
        end
    end

    mips_core u_core (
        .clk(clk), .rst_n(rst_n), .ext_int(6'd0),
        .inst_awid(inst_awid), .inst_awaddr(inst_awaddr), .inst_awlen(inst_awlen),
        .inst_awsize(inst_awsize), .inst_awburst(inst_awburst), .inst_awlock(inst_awlock),
        .inst_awcache(inst_awcache), .inst_awprot(inst_awprot), .inst_awvalid(inst_awvalid),
        .inst_awready(inst_awready), .inst_wdata(inst_wdata), .inst_wstrb(inst_wstrb),
        .inst_wlast(inst_wlast), .inst_wvalid(inst_wvalid), .inst_wready(inst_wready),
        .inst_bid(inst_bid), .inst_bresp(inst_bresp), .inst_bvalid(inst_bvalid),
        .inst_bready(inst_bready), .inst_arid(inst_arid), .inst_araddr(inst_araddr),
        .inst_arlen(inst_arlen), .inst_arsize(inst_arsize), .inst_arburst(inst_arburst),
        .inst_arlock(inst_arlock), .inst_arcache(inst_arcache), .inst_arprot(inst_arprot),
        .inst_arvalid(inst_arvalid), .inst_arready(inst_arready), .inst_rid(inst_rid),
        .inst_rdata(inst_rdata), .inst_rresp(inst_rresp), .inst_rlast(inst_rlast),
        .inst_rvalid(inst_rvalid), .inst_rready(inst_rready),
        .data_awid(data_awid), .data_awaddr(data_awaddr), .data_awlen(data_awlen),
        .data_awsize(data_awsize), .data_awburst(data_awburst), .data_awlock(data_awlock),
        .data_awcache(data_awcache), .data_awprot(data_awprot), .data_awvalid(data_awvalid),
        .data_awready(data_awready), .data_wdata(data_wdata), .data_wstrb(data_wstrb),
        .data_wlast(data_wlast), .data_wvalid(data_wvalid), .data_wready(data_wready),
        .data_bid(data_bid), .data_bresp(data_bresp), .data_bvalid(data_bvalid),
        .data_bready(data_bready), .data_arid(data_arid), .data_araddr(data_araddr),
        .data_arlen(data_arlen), .data_arsize(data_arsize), .data_arburst(data_arburst),
        .data_arlock(data_arlock), .data_arcache(data_arcache), .data_arprot(data_arprot),
        .data_arvalid(data_arvalid), .data_arready(data_arready), .data_rid(data_rid),
        .data_rdata(data_rdata), .data_rresp(data_rresp), .data_rlast(data_rlast),
        .data_rvalid(data_rvalid), .data_rready(data_rready),
        .debug_stall(debug_stall), .debug_flush(debug_flush)
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
