`timescale 1ns/1ps
module tb_scheduler_timer_ipi;
  reg clk=0,rst_n=0; always #5 clk=~clk;
  reg [31:0] paddr,pwdata; reg psel,penable,pwrite;
  wire [31:0] prdata; wire pready,pslverr,timer_int;
  reg timer_tick,ipi_resched,save_done,restore_ack;
  wire busy,ack; wire [7:0] current_task,save_task,restore_task;
  wire save_req,restore_req,switch_valid; wire [7:0] switch_to;
  wire [31:0] restore_pc,restore_sp,restore_status; wire [7:0] restore_asid;
  integer errors=0;
  apb_timer timer(.pclk(clk),.presetn(rst_n),.paddr(paddr),.psel(psel),.penable(penable),.pwrite(pwrite),.pwdata(pwdata),.prdata(prdata),.pready(pready),.pslverr(pslverr),.timer_int(timer_int));
  cpu_scheduler sched(.clk(clk),.rst_n(rst_n),.enable(1'b1),.timer_tick(timer_int),.ipi_resched(ipi_resched),.yield_req(1'b0),.active_mask(4'b0011),.resched_ack(ack),.scheduler_busy(busy),.current_task(current_task),.switch_valid(switch_valid),.switch_from(),.switch_to(switch_to),.ctx_save_req(save_req),.ctx_save_task(save_task),.ctx_save_done(save_done),.ctx_save_pc(32'h1111),.ctx_save_sp(32'h2222),.ctx_save_status(32'h3333),.ctx_save_asid(8'h1),.ctx_restore_req(restore_req),.ctx_restore_task(restore_task),.ctx_restore_ack(restore_ack),.ctx_restore_pc(restore_pc),.ctx_restore_sp(restore_sp),.ctx_restore_status(restore_status),.ctx_restore_asid(restore_asid));
  task apb_write(input [7:0] a,input [31:0] d); begin @(negedge clk);paddr=a;pwdata=d;pwrite=1;psel=1;penable=1;@(posedge clk);while(!pready)@(posedge clk);@(negedge clk);psel=0;penable=0;pwrite=0;end endtask
  task complete_switch; begin
    while(!save_req)@(posedge clk); @(negedge clk);save_done=1; repeat(2) @(negedge clk);save_done=0;
    while(!restore_req)@(posedge clk); @(negedge clk);restore_ack=1; repeat(2) @(negedge clk);restore_ack=0;
    if(!switch_valid && current_task!==1) errors=errors+1;
  end endtask
  initial begin
    paddr=0;pwdata=0;psel=0;penable=0;pwrite=0;timer_tick=0;ipi_resched=0;save_done=0;restore_ack=0;
    #23 rst_n=1;
    fork
      begin #2000; $display("REGRESSION_TEST_FAILED scheduler_timer_ipi timeout"); $finish; end
    join_none
    apb_write(8'h04,32'd2); apb_write(8'h00,32'h3);
    repeat(20) @(posedge clk);
    if(!timer_int) begin $display("FAIL timer did not assert");errors=errors+1;end
    complete_switch;
    apb_write(8'h0c,32'h1);
    @(negedge clk);ipi_resched=1;@(posedge clk);ipi_resched=0;
    if(!save_req && !busy) begin $display("FAIL IPI did not enter scheduler");errors=errors+1;end
    if(errors==0)$display("REGRESSION_TEST_SUCCESS scheduler_timer_ipi");else $display("REGRESSION_TEST_FAILED scheduler_timer_ipi errors=%0d",errors);
    $finish;
  end
endmodule
