`timescale 1ns/1ps
module tb_mips_rob_fifo;
    reg clk=0, rst_n=0, stall=0, flush=0, complete_valid=0;
    reg [1:0] complete_tag=0;
    reg [31:0] complete_rdata=0;
    reg complete_error=0;
    reg [31:0] mem_rdata_fmt=0, mem_ex_out=0, mem_pc_plus_8=0, mem_inst=0, mem_val_rt=0;
    reg mem_mem_read=0, mem_mem_write=0; reg [2:0] mem_mem_op=0;
    reg [4:0] mem_waddr=0, mem_rd_addr=0, mem_cp0_raddr=0; reg [2:0] mem_cp0_sel=0;
    reg mem_reg_write=0, mem_cp0_we=0, mem_is_eret=0; reg [2:0] mem_tlb_op=0;
    reg mem_except_req=0; reg [4:0] mem_except_code=0;
    reg mem_except_is_data=0, mem_except_is_tlb_refill=0, mem_bd=0;
    reg [31:0] mem_delay_slot_next_pc=0; reg [1:0] mem_mem_to_reg=0;
    wire [31:0] wb_rdata_fmt, wb_ex_out, wb_pc_plus_8, wb_inst, wb_val_rt;
    wire wb_mem_read, wb_mem_write, wb_valid, wb_reg_write, wb_cp0_we, wb_is_eret;
    wire [2:0] wb_mem_op, wb_cp0_sel, wb_tlb_op; wire [4:0] wb_waddr, wb_rd_addr, wb_cp0_raddr;
    wire wb_except_req, wb_except_is_data, wb_except_is_tlb_refill, wb_bd;
    wire [4:0] wb_except_code; wire [31:0] wb_delay_slot_next_pc; wire [1:0] wb_mem_to_reg;
    wire mem_alloc_valid = (mem_pc_plus_8 >= 32'd8);
    wire mem_ready_at_alloc = 1'b0;

    always #5 clk=~clk;
    mips_rob_fifo #(.DEPTH(4), .READY_AT_ALLOC(1'b0)) dut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .complete_valid(complete_valid), .complete_tag(complete_tag),
        .complete_rdata(complete_rdata), .complete_error(complete_error),
        .mem_alloc_valid(mem_alloc_valid), .mem_ready_at_alloc(mem_ready_at_alloc),
        .mem_rdata_fmt(mem_rdata_fmt), .mem_ex_out(mem_ex_out),
        .mem_pc_plus_8(mem_pc_plus_8), .mem_inst(mem_inst), .mem_val_rt(mem_val_rt),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write), .mem_mem_op(mem_mem_op),
        .mem_waddr(mem_waddr), .mem_rd_addr(mem_rd_addr), .mem_cp0_raddr(mem_cp0_raddr),
        .mem_cp0_sel(mem_cp0_sel), .mem_reg_write(mem_reg_write), .mem_cp0_we(mem_cp0_we),
        .mem_is_eret(mem_is_eret), .mem_tlb_op(mem_tlb_op), .mem_except_req(mem_except_req),
        .mem_except_code(mem_except_code), .mem_except_is_data(mem_except_is_data),
        .mem_except_is_tlb_refill(mem_except_is_tlb_refill), .mem_bd(mem_bd),
        .mem_delay_slot_next_pc(mem_delay_slot_next_pc), .mem_mem_to_reg(mem_mem_to_reg),
        .wb_rdata_fmt(wb_rdata_fmt), .wb_ex_out(wb_ex_out), .wb_pc_plus_8(wb_pc_plus_8),
        .wb_inst(wb_inst), .wb_val_rt(wb_val_rt), .wb_mem_read(wb_mem_read),
        .wb_mem_write(wb_mem_write), .wb_mem_op(wb_mem_op), .wb_valid(wb_valid),
        .wb_waddr(wb_waddr), .wb_rd_addr(wb_rd_addr), .wb_cp0_raddr(wb_cp0_raddr),
        .wb_cp0_sel(wb_cp0_sel), .wb_reg_write(wb_reg_write), .wb_cp0_we(wb_cp0_we),
        .wb_is_eret(wb_is_eret), .wb_tlb_op(wb_tlb_op), .wb_except_req(wb_except_req),
        .wb_except_code(wb_except_code), .wb_except_is_data(wb_except_is_data),
        .wb_except_is_tlb_refill(wb_except_is_tlb_refill), .wb_bd(wb_bd),
        .wb_delay_slot_next_pc(wb_delay_slot_next_pc), .wb_mem_to_reg(wb_mem_to_reg)
    );

    task automatic alloc(input [31:0] pc, input [31:0] inst);
        begin @(negedge clk); mem_pc_plus_8=pc; mem_inst=inst;
            mem_mem_op=3'b100;
            @(posedge clk); @(negedge clk); mem_pc_plus_8=0; mem_inst=0; end
    endtask
    task automatic complete(input [1:0] tag, input [31:0] rdata, input input_error);
        begin @(negedge clk); complete_tag=tag; complete_rdata=rdata;
            complete_error=input_error; complete_valid=1;
            @(negedge clk); complete_valid=0; complete_error=0; end
    endtask
    initial begin
        repeat(2) @(posedge clk); rst_n=1;
        alloc(32'h108,32'h11111111); alloc(32'h208,32'h22222222);
        @(posedge clk);
        #1; if (dut.count != 2) $fatal(1,"ROB did not retain two incomplete entries");
        complete(0, 32'hA0A0A0A0, 1'b0); @(posedge clk); #1; if (!wb_valid || wb_pc_plus_8 != 32'h108 || wb_inst != 32'h11111111 || wb_rdata_fmt != 32'hA0A0A0A0)
            $fatal(1,"ROB did not commit oldest completed entry");
        complete(1, 32'hB0B0B0B0, 1'b0); @(posedge clk); #1; if (!wb_valid || wb_pc_plus_8 != 32'h208 || wb_inst != 32'h22222222 || wb_rdata_fmt != 32'hB0B0B0B0)
            $fatal(1,"ROB did not commit second completed entry");
        alloc(32'h308,32'h33333333);
        @(posedge clk);
        complete(2, 32'hDEAD0000, 1'b1); @(posedge clk); #1;
        if (!wb_valid || !wb_except_req || wb_except_code != 5'h1E ||
            !wb_except_is_data || wb_rdata_fmt != 32'hDEAD0000)
            $fatal(1,"ROB did not retire late response CacheErr precisely");
        alloc(32'h408,32'h44444444); flush=1; @(negedge clk); flush=0;
        #1; if (wb_valid || dut.count != 0) $fatal(1,"ROB flush did not cancel younger entry");
        alloc(32'h508,32'h55555555); @(negedge clk); rst_n=0; @(negedge clk); rst_n=1;
        #1; if (dut.count != 0 || wb_valid) $fatal(1,"ROB reset-in-flight did not clear state");
        $display("REGRESSION_TEST_SUCCESS rob_fifo ordered_complete_flush");
        $finish;
    end
endmodule
