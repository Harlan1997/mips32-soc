`timescale 1ns/1ps
module tb_cpu_scheduler;
  reg clk=0,rst_n=0,enable,timer_tick,ipi_resched,yield_req;
  reg [3:0] active_mask; wire ack,busy; wire [7:0] current_task;
  wire sw,save_req,restore_req; wire [7:0] sw_from,sw_to,save_task,restore_task;
  reg save_done,restore_ack; reg [31:0] save_pc,save_sp,save_status; reg [7:0] save_asid;
  wire [31:0] restore_pc,restore_sp,restore_status; wire [7:0] restore_asid;
  reg [1023:0] save_gpr; wire [1023:0] restore_gpr;
  integer errors=0;
  cpu_scheduler dut(.clk(clk),.rst_n(rst_n),.enable(enable),.timer_tick(timer_tick),.ipi_resched(ipi_resched),.yield_req(yield_req),.active_mask(active_mask),.resched_ack(ack),.scheduler_busy(busy),.current_task(current_task),.switch_valid(sw),.switch_from(sw_from),.switch_to(sw_to),.ctx_save_req(save_req),.ctx_save_task(save_task),.ctx_save_done(save_done),.ctx_save_pc(save_pc),.ctx_save_sp(save_sp),.ctx_save_status(save_status),.ctx_save_asid(save_asid),.ctx_save_gpr(save_gpr),.ctx_restore_req(restore_req),.ctx_restore_task(restore_task),.ctx_restore_ack(restore_ack),.ctx_restore_pc(restore_pc),.ctx_restore_sp(restore_sp),.ctx_restore_status(restore_status),.ctx_restore_asid(restore_asid),.ctx_restore_gpr(restore_gpr));
  always #5 clk=~clk;
  initial begin
    enable=1;timer_tick=0;ipi_resched=0;yield_req=0;active_mask=4'b0011;save_done=0;restore_ack=0;save_pc=32'h1111;save_sp=32'h2222;save_status=32'h3333;save_asid=8'h12;save_gpr=1024'h0123;
    #23 rst_n=1; @(negedge clk); timer_tick=1; @(negedge clk); timer_tick=0;
    @(posedge clk); @(posedge clk); if(!save_req||save_task!==0) errors=errors+1;
    @(negedge clk); save_done=1; @(posedge clk); @(posedge clk); if(!restore_req||restore_task!==1) errors=errors+1; @(negedge clk); save_done=0;
    if(restore_pc!==0||restore_gpr!==0) errors=errors+1;
    @(negedge clk); restore_ack=1; @(posedge clk); if(!sw||sw_to!==1) errors=errors+1; @(negedge clk); restore_ack=0;
    if(current_task!==1) errors=errors+1;
    @(negedge clk); ipi_resched=1; @(posedge clk); ipi_resched=0; @(posedge clk); if(!save_req||save_task!==1) errors=errors+1;
    if(errors==0)$display("REGRESSION_TEST_SUCCESS cpu_scheduler"); else $display("REGRESSION_TEST_FAILED cpu_scheduler errors=%0d",errors);
    $finish;
  end
endmodule
