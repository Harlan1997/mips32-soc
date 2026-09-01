`timescale 1ns/1ps
`ifdef WALKER_16K
  `define TEST_PAGE_MASK 16'h0003
`elsif WALKER_64K
  `define TEST_PAGE_MASK 16'h000f
`elsif WALKER_256K
  `define TEST_PAGE_MASK 16'h003f
`elsif WALKER_1M
  `define TEST_PAGE_MASK 16'h00ff
`elsif WALKER_4M
  `define TEST_PAGE_MASK 16'h03ff
`elsif WALKER_16M
  `define TEST_PAGE_MASK 16'h0fff
`else
  `define TEST_PAGE_MASK 16'h0000
`endif
module tb_page_table_walker;
  reg clk=0,rst_n=0,req_valid,user_mode,mem_ready,mem_error;
  reg [31:0] ptbr,va,mem_rdata; reg [1:0] access;
  wire req_ready,mem_valid,resp_valid,fault_valid; wire [31:0] mem_addr,pa,leaf_pte;
  wire pte_update_valid; wire [31:0] pte_update_addr,pte_update_data;
  reg pte_update_ready=1'b1; wire [2:0] fault_code;
  reg [31:0] mem[0:4095]; integer errors=0;
  integer pte_updates=0; reg [31:0] last_pte_update_addr,last_pte_update_data;
  mips_page_table_walker #(.PAGE_MASK(`TEST_PAGE_MASK), .ENABLE_AD_UPDATE(1'b1)) dut(.*);
  always #5 clk=~clk;
  always @(*) begin mem_rdata=mem[mem_addr[13:2]]; end
  always @(posedge clk) if (pte_update_valid && pte_update_ready) begin
    pte_updates = pte_updates + 1;
    last_pte_update_addr = pte_update_addr;
    last_pte_update_data = pte_update_data;
    mem[pte_update_addr[13:2]] = pte_update_data;
  end
  task walk(input [31:0] v,input [1:0] a,input u); begin
    @(negedge clk); va=v;access=a;user_mode=u;req_valid=1;
    // The request is accepted on this edge.  Deassert valid on the next
    // falling edge; waiting for req_ready would permit a second request to
    // be sampled when an A/D update adds latency.
    @(posedge clk); @(negedge clk); req_valid=0;
    while(!resp_valid)@(posedge clk);
  end endtask
  task walk_with_backpressure(input [31:0] v,input [1:0] a,input u); begin
    @(negedge clk); va=v;access=a;user_mode=u;req_valid=1;mem_ready=0;
    @(posedge clk); @(negedge clk); req_valid=0;
    /* The request must remain asserted while the memory side is stalled. */
    repeat (3) begin
      @(posedge clk);
      if (!mem_valid) errors=errors+1;
    end
    @(negedge clk); mem_ready=1;
    while(!resp_valid) @(posedge clk);
    mem_ready=1;
  end endtask

  initial begin
    ptbr=32'h0000_1000;req_valid=0;user_mode=0;mem_ready=1;mem_error=0;access=0;va=0;
    last_pte_update_addr=0; last_pte_update_data=0;
    #23 rst_n=1;
    mem[1024]=32'h0000_2003;
    case (`TEST_PAGE_MASK)
      16'h0003: mem[2048]=32'h0000_400f;
      16'h000f: mem[2048]=32'h0001_000f;
      16'h003f: mem[2048]=32'h0004_000f;
      16'h00ff: mem[2048]=32'h0010_000f;
      16'h03ff: mem[2048]=32'h0040_000f;
      16'h0fff: mem[2048]=32'h0100_000f;
      default:  mem[2048]=32'h0000_300f;
    endcase
    /* The common 4KB matrix below remains the detailed permission corpus. */
    if (`TEST_PAGE_MASK != 16'h0000) begin
      @(negedge clk); va=32'h0000_0123; access=2'd1; user_mode=1; req_valid=1;
      @(posedge clk); @(negedge clk); req_valid=0;
      while(!resp_valid) @(posedge clk);
      case (`TEST_PAGE_MASK)
        16'h0003: if (fault_valid || pa !== 32'h0000_4123) errors=errors+1;
        16'h000f: if (fault_valid || pa !== 32'h0001_0123) errors=errors+1;
        16'h003f: if (fault_valid || pa !== 32'h0004_0123) errors=errors+1;
        16'h00ff: if (fault_valid || pa !== 32'h0010_0123) errors=errors+1;
        16'h03ff: if (fault_valid || pa !== 32'h0040_0123) errors=errors+1;
        16'h0fff: if (fault_valid || pa !== 32'h0100_0123) errors=errors+1;
        default:  if (fault_valid || pa !== 32'h0000_3123) errors=errors+1;
      endcase

      /* A non-zero L2 index must advance by one 32-bit PTE word for every
       * supported large-page format.  The old implementation incorrectly
       * used the page-size shift as the PTE byte stride. */
      case (`TEST_PAGE_MASK)
        16'h0003: begin
          mem[2049]=32'h0000_800f;
          va=32'h0000_4000;
        end
        16'h000f: begin
          mem[2049]=32'h0002_000f;
          va=32'h0001_0000;
        end
        16'h003f: begin
          mem[2049]=32'h0008_000f;
          va=32'h0004_0000;
        end
        16'h00ff: begin
          mem[2050]=32'h0020_000f;
          va=32'h0020_0000;
        end
        16'h03ff: begin
          mem[2048]=32'h0080_000f;
          va=32'h0000_4004;
        end
        16'h0fff: begin
          mem[2048]=32'h0200_000f;
          va=32'h0001_0008;
        end
        default: begin
          mem[2049]=32'h0000_300f;
          va=32'h0000_1000;
        end
      endcase
      access=2'd1; user_mode=1; req_valid=1;
      @(posedge clk); @(negedge clk); req_valid=0;
      while(!resp_valid) @(posedge clk);
      case (`TEST_PAGE_MASK)
        16'h0003: if (fault_valid || pa !== 32'h0000_8000) errors=errors+1;
        16'h000f: if (fault_valid || pa !== 32'h0002_0000) errors=errors+1;
        16'h003f: if (fault_valid || pa !== 32'h0008_0000) errors=errors+1;
        16'h00ff: if (fault_valid || pa !== 32'h0020_0000) errors=errors+1;
        16'h03ff: if (fault_valid || pa !== 32'h0080_4004) errors=errors+1;
        16'h0fff: if (fault_valid || pa !== 32'h0201_0008) errors=errors+1;
        default:  if (fault_valid || pa !== 32'h0000_3000) errors=errors+1;
      endcase
    end
    else begin
    walk(32'h0000_0123,2'd1,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    if (pte_updates != 1 || last_pte_update_addr !== 32'h0000_2000 ||
        last_pte_update_data !== 32'h0000_301f) errors=errors+1;
    walk(32'h0000_0123,2'd1,1'b1);
    if (pte_updates != 1 || fault_valid || pa !== 32'h0000_3123)
      errors=errors+1;
    /* A store sets both A and D, and the update must be held under
     * backpressure until the page-table memory accepts it. */
    mem[2048]=32'h0000_3001; pte_update_ready=0;
    @(negedge clk); va=32'h0000_0123; access=2'd2; user_mode=1; req_valid=1;
    // Deassert after acceptance; req_ready must not be required while the
    // accepted request is waiting for its A/D writeback consumer.
    @(posedge clk); @(negedge clk); req_valid=0;
    while(!pte_update_valid) @(posedge clk);
    repeat (3) begin @(posedge clk); if(!pte_update_valid) errors=errors+1; end
    if (pte_update_addr !== 32'h0000_2000 || pte_update_data !== 32'h0000_3031)
      errors=errors+1;
    @(negedge clk); pte_update_ready=1;
    while(!resp_valid) @(posedge clk);
    if (fault_valid || pa !== 32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_300B; walk(32'h0000_0123,2'd2,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_3009; walk(32'h0000_0123,2'd2,1'b1);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[2048]=32'h0000_3003; walk(32'h0000_0123,2'd1,1'b0);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    mem[2048]=32'h0000_3001; walk(32'h0000_0123,2'd2,1'b0);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[2048]=32'h0000_3001; walk(32'h0000_0123,2'd1,1'b0);
    if(!fault_valid||fault_code!==3'd2) errors=errors+1;
    mem[1024]=32'd0; walk(32'h0000_0123,2'd1,1'b0);
    if(!fault_valid||fault_code!==3'd1) errors=errors+1;

    /* Both page-table reads must tolerate independent memory backpressure. */
    mem[1024]=32'h0000_2003; mem[2048]=32'h0000_300f;
    walk_with_backpressure(32'h0000_0123,2'd1,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;

    /* Reset in either outstanding-read state must cancel the walk cleanly. */
    @(negedge clk); req_valid=1; mem_ready=0;
    @(posedge clk); @(negedge clk); req_valid=0;
    if(!mem_valid) errors=errors+1;
    rst_n=0; #1;
    if(mem_valid || resp_valid || fault_valid || !req_ready) errors=errors+1;
    @(posedge clk); rst_n=1; mem_ready=1;
    walk(32'h0000_0123,2'd1,1'b1);
    if(fault_valid||pa!==32'h0000_3123) errors=errors+1;
    end
    if(errors==0)$display("REGRESSION_TEST_SUCCESS page_table_walker");
    else $display("REGRESSION_TEST_FAILED page_table_walker errors=%0d",errors);
    $finish;
  end
endmodule
