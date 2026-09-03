`timescale 1ns/1ps
module tb_mmu_context_status;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, psel=0, penable=0, pwrite=0; reg [7:0] paddr=0; reg [31:0] pwdata=0;
  wire [31:0] prdata; wire pready, pslverr;
  wire invalidate_valid; wire [7:0] invalidate_asid;
  wire [18:0] invalidate_vpn; wire [1:0] invalidate_scope;
  integer errors=0, n;
  apb_mmu_context_status dut(.*);
  task apb_write(input [7:0] a,input [31:0] d); begin @(negedge clk); paddr=a;pwdata=d;pwrite=1;psel=1;penable=1; @(negedge clk); psel=0;penable=0;pwrite=0; end endtask
  task apb_read(input [7:0] a,input [31:0] exp,input [127:0] n); begin @(negedge clk);paddr=a;pwrite=0;psel=1;penable=1;#1;if(prdata!==exp) begin $display("[FAIL] %0s got %h exp %h",n,prdata,exp);errors=errors+1;end else $display("[PASS] %0s",n);@(negedge clk);psel=0;penable=0; end endtask
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    apb_write(5'h00,32'h00003412); apb_read(5'h00,32'h00003412,"asid generation");
    apb_write(5'h04,32'h000ABCDE); apb_read(5'h04,32'h000ABCDE,"vpn");
    apb_write(5'h08,32'h2); apb_read(5'h08,32'h2,"scope");
    apb_write(5'h14,32'h1); apb_read(5'h00,32'h00000001,"allocator lease");
    apb_read(5'h0c,32'h1,"allocator valid event");
    apb_write(5'h18,32'h80000101); apb_read(5'h0c,32'h9,"release reject event");
    apb_write(6'h1c,32'h1); apb_read(6'h24,32'h1,"shootdown busy");
    apb_write(6'h20,32'h1); apb_read(6'h24,32'h6,"shootdown done");
    apb_write(6'h1c,32'h1); repeat(18) @(negedge clk); apb_read(6'h24,32'hA,"shootdown timeout");
    apb_write(5'h0c,32'h5); apb_read(5'h0c,32'hd,"sticky events");
    apb_write(5'h10,32'h1); apb_read(5'h0c,32'hc,"W1C event");
    apb_write(6'h1c,32'h1);
    apb_write(6'h20,32'h00000101);
    if (!dut.sd_status_r[5]) begin $display("[FAIL] stale shootdown ACK accepted"); errors=errors+1; end
    apb_write(6'h20,32'h1);
    apb_read(6'h24,32'h26,"generation-checked shootdown ACK");
    apb_write(6'h28,32'h1); apb_read(6'h28,32'h00100000,"root allocator lease");
    apb_read(6'h2c,32'h0,"root generation starts at zero");
    apb_write(6'h2c,32'h00100000);
    apb_write(6'h30,32'h80000001); apb_read(6'h34,32'h9,"root stale-release event");
    apb_write(6'h38,32'h8);
    apb_write(6'h30,32'h80000000); apb_read(6'h34,32'h5,"root valid-release event");
    apb_write(6'h38,32'h5);
    apb_write(6'h28,32'h1); apb_read(6'h28,32'h00100000,"root generation reuse");
    apb_read(6'h2c,32'h1,"root generation increments");
    // Atomic context leases bind the root, ASID and generation to one slot.
    for (n=0; n<4; n=n+1) begin
      apb_write(6'h3c,32'h1);
      apb_read(6'h00, (n+1), "combined context ASID");
      apb_read(6'h28, (32'h00100000 + n*32'h1000), "combined context root");
    end
    apb_write(6'h2c,32'h00101000);
    apb_write(6'h3c,32'h80000002); // slot 2: ASID=2, generation=0
    apb_write(6'h3c,32'h80000002); // second release must be rejected
    apb_read(6'h34,32'hd,"combined stale and duplicate release events");
    apb_write(6'h38,32'hc);
    apb_write(6'h3c,32'h1);
    apb_read(6'h00,32'h00000102,"combined generation reuse ASID");
    apb_read(6'h2c,32'h1,"combined generation reuse token");
    // Page-frame leases use the extended MMU context offsets 0x40..0x50.
    apb_write(8'h40,32'h1); apb_read(8'h40,32'h00006000,"page allocator lease");
    apb_read(8'h44,32'h0,"page generation starts at zero");
    apb_write(8'h44,32'h00006000);
    apb_write(8'h48,32'h80000001); apb_read(8'h4c,32'h9,"page stale-release event");
    apb_write(8'h50,32'hc);
    apb_write(8'h48,32'h80000000); apb_read(8'h4c,32'h5,"page valid-release event");
    apb_write(8'h50,32'h4); // clear release event and retain allocator state
    apb_write(8'h40,32'h1); apb_read(8'h40,32'h00006000,"page generation reuse");
    apb_read(8'h44,32'h1,"page generation increments");
    if(!pready || pslverr) begin $display("[FAIL] APB handshake");errors=errors+1;end
    if(errors==0) $display("REGRESSION_TEST_SUCCESS mmu_context_status"); else $display("REGRESSION_TEST_FAILED mmu_context_status"); $finish;
  end
endmodule
