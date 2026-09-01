`timescale 1ns/1ps
module tb_l1_cache_nb;
 reg clk=0,rst_n=0,cpu_valid=0,cpu_we=0; reg [3:0] cpu_id=0,cpu_be=4'hf;
 reg [31:0] cpu_addr=0,cpu_wdata=0; reg cache_maint_invalidate=0;
 reg [4:0] cache_maint_op=0; reg [31:0] cache_maint_addr=0;
 reg [31:0] cache_tag_wdata=0; wire [31:0] cache_tag_rdata;
 wire cache_maint_ready, cache_maint_done, cache_maint_error;
 wire cpu_ready,rsp_valid,rsp_error;
 wire [3:0] rsp_id; wire [31:0] rsp_rdata; reg rsp_ready=1;
 wire mem_req_valid,mem_req_we; wire [31:0] mem_req_addr; wire [255:0] mem_req_wdata;
 reg mem_req_ready=1,mem_rsp_valid=0,mem_rsp_error=0; reg [31:0] mem_rsp_addr=0; reg [255:0] mem_rsp_data=0;
 wire [3:0] mshr_occupancy,wb_occupancy; integer errors=0; reg saw_hit_wb=0;
 reg coh_snoop_valid=0; reg [31:0] coh_snoop_addr=0;
 wire coh_store_valid; wire [31:0] coh_store_addr; reg saw_coh_store=0;
 always @(negedge clk) begin
  if (coh_store_valid) saw_coh_store <= 1'b1;
 end
 always #5 clk=~clk;
 always @(posedge clk) begin
  if (mem_req_valid && mem_req_we && mem_req_ready &&
      mem_req_addr == 32'h00001200 && mem_req_wdata[31:0] == 32'hdeadbeef)
   saw_hit_wb <= 1'b1;
 end
 l1_cache_nb #(.ENABLE_COHERENCY(1'b1)) dut(.*);
 task issue_read(input [3:0] id,input [31:0] addr);
  begin @(negedge clk); cpu_id=id;cpu_addr=addr;cpu_we=0;cpu_valid=1;
   while(!cpu_ready) @(negedge clk); @(negedge clk);cpu_valid=0; end
 endtask
 task return_line(input [31:0] addr,input [31:0] word);
  begin @(negedge clk);mem_rsp_addr=addr;mem_rsp_data=0;mem_rsp_data[(addr[4:2])*32 +: 32]=word;mem_rsp_valid=1;
   @(negedge clk);mem_rsp_valid=0; end
 endtask
 task issue_write(input [3:0] id,input [31:0] addr,input [31:0] data);
  begin @(negedge clk);cpu_id=id;cpu_addr=addr;cpu_wdata=data;cpu_be=4'hf;cpu_we=1;cpu_valid=1;
   while(!cpu_ready) @(negedge clk); @(negedge clk);cpu_valid=0;cpu_we=0; end
 endtask
 task maintain(input [4:0] op,input [31:0] addr);
  integer n;
  begin @(negedge clk); cache_maint_op=op; cache_maint_addr=addr;
   cache_maint_invalidate=1; @(negedge clk);
   for (n=0; n<40 && !cache_maint_done; n=n+1) @(negedge clk);
   if (!cache_maint_done || cache_maint_error) errors=errors+1;
   cache_maint_invalidate=0;
  end
 endtask
 task wait_wb_empty;
  integer n;
  begin
   for (n=0; n<20 && wb_occupancy != 0; n=n+1) @(negedge clk);
   #1;
   if (wb_occupancy != 0) begin
    $display("FAIL writeback queue did not drain occupancy=%0d",wb_occupancy);
    errors=errors+1;
   end
  end
 endtask
 initial begin
  repeat(2) @(posedge clk);rst_n=1;
  // Two requests to the same line must merge into one refill while retaining
  // both IDs and returning two responses.
  issue_read(4'ha,32'h00000040); issue_read(4'hb,32'h00000044);
  #1;if(!(dut.mvalid[0] ^ dut.mvalid[1])) begin $display("FAIL merged mshr slots=%b%b",dut.mvalid[1],dut.mvalid[0]);errors=errors+1;end
  return_line(32'h00000040,32'haaaa0001);#1;
  if(!rsp_valid||rsp_id!=4'ha||rsp_rdata!=32'haaaa0001) begin $display("FAIL rsp a id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end
  @(negedge clk);rsp_ready=1;
  #1;
  if(!rsp_valid||rsp_id!=4'hb) begin $display("FAIL secondary rsp id=%h",rsp_id);errors=errors+1;end
  @(negedge clk);
  // Distinct lines still occupy independent MSHRs and may complete OOO.
  issue_read(4'hc,32'h000000c0); issue_read(4'hd,32'h00000100);
  #1;if(!(dut.mvalid[0] && dut.mvalid[1])) begin $display("FAIL distinct mshr slots=%b%b",dut.mvalid[1],dut.mvalid[0]);errors=errors+1;end
  return_line(32'h00000100,32'hdddd0001);#1;
  if(!rsp_valid||rsp_id!=4'hd||rsp_rdata!=32'hdddd0001) begin $display("FAIL rsp d id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end
  @(negedge clk);rsp_ready=1;
  return_line(32'h000000c0,32'hcccc0001);#1;
  if(!rsp_valid||rsp_id!=4'hc||rsp_rdata!=32'hcccc0001) begin $display("FAIL rsp c id=%h data=%h",rsp_id,rsp_rdata);errors=errors+1;end

  // Fill one dirty line in each set, then hold the memory port blocked while
  // four conflicting misses enqueue dirty victims.  The fifth dirty victim
  // must remain backpressured until the writeback queue drains.
  issue_write(4'h1,32'h00000200,32'hd0000001); return_line(32'h00000200,32'h10000001);
  issue_write(4'h2,32'h00000220,32'hd0000002); return_line(32'h00000220,32'h10000002);
  issue_write(4'h3,32'h00000240,32'hd0000003); return_line(32'h00000240,32'h10000003);
  issue_write(4'h4,32'h00000260,32'hd0000004); return_line(32'h00000260,32'h10000004);
  mem_req_ready=0;
  issue_write(4'h5,32'h00000600,32'he0000001); return_line(32'h00000600,32'h20000001);
  issue_write(4'h6,32'h00000620,32'he0000002); return_line(32'h00000620,32'h20000002);
  issue_write(4'h7,32'h00000640,32'he0000003); return_line(32'h00000640,32'h20000003);
  issue_write(4'h8,32'h00000660,32'he0000004); return_line(32'h00000660,32'h20000004);
  #1;
  if (wb_occupancy != 4) begin
   $display("FAIL writeback queue fill occupancy=%0d expected=4",wb_occupancy);
   errors=errors+1;
  end
  @(negedge clk);cpu_id=4'h9;cpu_addr=32'h00000a00;cpu_wdata=32'hf0000001;cpu_we=1;cpu_valid=1;
  #1;
  if (cpu_ready) begin
   $display("FAIL fifth dirty victim was accepted while WB queue full");
   errors=errors+1;
  end
  cpu_valid=0;cpu_we=0;mem_req_ready=1;
  wait_wb_empty();
  // Exercise address-scoped maintenance after all outstanding responses and
  // writebacks are drained, so the check cannot perturb the MSHR stress.
  issue_write(4'ha,32'h00001120,32'haaaa0001); return_line(32'h00001120,32'h12000001);
  maintain(5'b10101,32'h00001120);
  issue_read(4'he,32'h00001120);
  #1;if (!dut.mvalid[0] && !dut.mvalid[1]) begin
   $display("FAIL hit invalidate did not force a refill");errors=errors+1;
  end
  return_line(32'h00001120,32'heeee0001);
  maintain(5'b00001,32'h00001140);
  issue_write(4'hb,32'h00001140,32'hbbbb0001); return_line(32'h00001140,32'h14000001);
  maintain(5'b00001,32'h00001140);
  issue_read(4'hf,32'h00001140);
  #1;if (!dut.mvalid[0] && !dut.mvalid[1]) begin
   $display("FAIL index invalidate did not force a refill");errors=errors+1;
  end
  return_line(32'h00001140,32'hffff0001);
  // A dirty hit-writeback must expose the old line on the downstream port
  // before completion and keep the line valid for a subsequent hit.
  issue_write(4'hc,32'h00001200,32'hcafebabe);
  return_line(32'h00001200,32'h12000001);
  issue_write(4'hd,32'h00001200,32'hdeadbeef);
  maintain(5'b11101,32'h00001200);
  if (!saw_hit_wb) begin
   $display("FAIL hit writeback payload was not observed");
   errors=errors+1;
  end
  @(negedge clk);
  issue_read(4'he,32'h00001200);
  #1;if (dut.mvalid[0] || dut.mvalid[1]) begin
   $display("FAIL hit writeback unnecessarily invalidated line");errors=errors+1;
  end
  // Index tag operations use the same completion contract as maintenance.
  maintain(5'b00101,32'h00001200);
  if (cache_tag_rdata !== 32'h00400024) begin
   $display("FAIL tag load data=%h expected=%h",cache_tag_rdata,32'h00400024);
   errors=errors+1;
  end
  cache_tag_wdata = 32'h00612345;
  maintain(5'b01001,32'h00001200);
  maintain(5'b00101,32'h00001200);
  if (cache_tag_rdata !== 32'h00612345) begin
   $display("FAIL tag store/load data=%h expected=%h",cache_tag_rdata,32'h00612345);
   errors=errors+1;
  end
  // A peer store must invalidate a clean line and block a same-cycle CPU
  // request; the local store event must also be broadcast to the peer.
  issue_read(4'h1,32'h00001300); return_line(32'h00001300,32'h13000001);
  @(negedge clk); coh_snoop_addr=32'h00001300; coh_snoop_valid=1;
  #1;if (cpu_ready) begin $display("FAIL snoop did not block CPU"); errors=errors+1; end
  @(posedge clk); #1;
  if (dut.valid[0]) begin $display("FAIL clean snoop did not invalidate line valid=%b hit=%b apply=%b mshr=%b",dut.valid[0],dut.snoop_line_hit,dut.snoop_apply,dut.snoop_mshr_match); errors=errors+1; end
  coh_snoop_valid=0;
  issue_read(4'h2,32'h00001300); #1;
  if (!dut.mvalid[0] && !dut.mvalid[1]) begin $display("FAIL clean snoop did not allow refill"); errors=errors+1; end
  return_line(32'h00001300,32'h13000002);
  // A snoop colliding with an outstanding refill is retained and applied
  // after the refill, rather than being silently lost.
  issue_read(4'h4,32'h00001400);
  @(negedge clk); coh_snoop_addr=32'h00001400; coh_snoop_valid=1;
  @(posedge clk); #1; coh_snoop_valid=0;
  return_line(32'h00001400,32'h14000001);
  @(posedge clk); #1;
  if (dut.valid[0]) begin $display("FAIL pending snoop did not invalidate refill pending=%b hit=%b apply=%b mshr=%b",dut.snoop_pending,dut.snoop_line_hit,dut.snoop_apply,dut.snoop_mshr_match); errors=errors+1; end
  issue_write(4'h3,32'h00001300,32'hfeed0001);
  if (!saw_coh_store) begin
   $display("FAIL local store was not broadcast addr=%h valid=%b hit=%b",coh_store_addr,coh_store_valid,dut.hit); errors=errors+1;
  end
  if(errors==0)$display("REGRESSION_TEST_SUCCESS l1nb mshr=2 wb=4");else $display("REGRESSION_TEST_FAILED l1nb errors=%0d",errors);$finish;
 end
endmodule
