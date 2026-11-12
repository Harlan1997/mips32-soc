`timescale 1ns/1ps
module tb_page_table_tlb_refill;
  reg clk=0, rst_n=0;
  integer errors=0;

  // -------------------------------------------------------------------------
  // DUT 1: Default instance (ENABLE_AD_UPDATE = 0 by default)
  // Verifies that default behavior is preserved: no writeback request is emitted
  // and the existing TLB refill transaction operates unchanged.
  // -------------------------------------------------------------------------
  reg miss_valid, mem_ready, mem_error, tlb_wr_ready;
  reg [31:0] miss_va, ptbr, mem_rdata;
  reg [1:0] miss_access;
  reg miss_user;
  reg [7:0] miss_asid;
  wire miss_ready, mem_valid, walk_resp_valid, walk_fault_valid, tlb_wr_valid;
  wire [31:0] mem_addr, walk_pa;
  wire [2:0] walk_fault_code;
  wire [18:0] tlb_wr_vpn2;
  wire [7:0] tlb_wr_asid;
  wire [15:0] tlb_wr_mask;
  wire [31:0] tlb_wr_entrylo0, tlb_wr_entrylo1;
  wire pte_update_valid;
  wire [31:0] pte_update_addr, pte_update_data;
  reg pte_update_ready, pte_update_error;

  reg [31:0] mem[0:4095];
  always @(*) mem_rdata = mem[mem_addr[13:2]];

  mips_page_table_tlb_refill dut (
    .clk(clk), .rst_n(rst_n),
    .miss_valid(miss_valid), .miss_ready(miss_ready),
    .miss_va(miss_va), .ptbr(ptbr),
    .miss_access(miss_access), .miss_user(miss_user),
    .miss_asid(miss_asid),
    .mem_valid(mem_valid), .mem_addr(mem_addr),
    .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_error(mem_error),
    .walk_resp_valid(walk_resp_valid), .walk_fault_valid(walk_fault_valid),
    .walk_fault_code(walk_fault_code), .walk_pa(walk_pa),
    .tlb_wr_valid(tlb_wr_valid), .tlb_wr_ready(tlb_wr_ready),
    .tlb_wr_vpn2(tlb_wr_vpn2), .tlb_wr_asid(tlb_wr_asid),
    .tlb_wr_mask(tlb_wr_mask),
    .tlb_wr_entrylo0(tlb_wr_entrylo0), .tlb_wr_entrylo1(tlb_wr_entrylo1),
    .pte_update_valid(pte_update_valid),
    .pte_update_addr(pte_update_addr),
    .pte_update_data(pte_update_data),
    .pte_update_ready(pte_update_ready),
    .pte_update_error(pte_update_error)
  );

  task automatic run_walk;
    integer guard;
    begin
      @(negedge clk); miss_valid = 1;
      @(posedge clk); while (!miss_ready) @(posedge clk);
      @(negedge clk); miss_valid = 0;
      guard = 0;
      while (!tlb_wr_valid && !walk_fault_valid && guard < 200) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (!tlb_wr_valid && !walk_fault_valid) begin
        $display("ERROR: Timeout waiting for default dut walk completion");
        errors = errors + 1;
      end
    end
  endtask

  // Monitor: in disabled mode, pte_update_valid must NEVER assert.
  always @(posedge clk) begin
    if (rst_n && pte_update_valid) begin
      $display("ERROR: pte_update_valid asserted in disabled mode (time %0t)", $time);
      errors = errors + 1;
    end
  end

  // -------------------------------------------------------------------------
  // DUT 2: Enabled instance (ENABLE_AD_UPDATE = 1)
  // Verifies accessed-only update, dirty update for a store, backpressure stability,
  // write-error fault, even/odd TLB entry selection, and non-duplication when permanently ready.
  // -------------------------------------------------------------------------
  reg miss_valid_ad, mem_ready_ad, mem_error_ad, tlb_wr_ready_ad;
  reg [31:0] miss_va_ad, ptbr_ad, mem_rdata_ad;
  reg [1:0] miss_access_ad;
  reg miss_user_ad;
  reg [7:0] miss_asid_ad;
  wire miss_ready_ad, mem_valid_ad, walk_resp_valid_ad, walk_fault_valid_ad, tlb_wr_valid_ad;
  wire [31:0] mem_addr_ad, walk_pa_ad;
  wire [2:0] walk_fault_code_ad;
  wire [18:0] tlb_wr_vpn2_ad;
  wire [7:0] tlb_wr_asid_ad;
  wire [15:0] tlb_wr_mask_ad;
  wire [31:0] tlb_wr_entrylo0_ad, tlb_wr_entrylo1_ad;
  wire pte_update_valid_ad;
  wire [31:0] pte_update_addr_ad, pte_update_data_ad;
  reg pte_update_ready_ad, pte_update_error_ad;

  reg [31:0] mem_ad[0:4095];
  always @(*) mem_rdata_ad = mem_ad[mem_addr_ad[13:2]];

  integer pte_updates_ad = 0;
  reg [31:0] last_pte_update_addr_ad = 0, last_pte_update_data_ad = 0;

  always @(posedge clk) begin
    if (pte_update_valid_ad && pte_update_ready_ad) begin
      pte_updates_ad <= pte_updates_ad + 1;
      last_pte_update_addr_ad <= pte_update_addr_ad;
      last_pte_update_data_ad <= pte_update_data_ad;
      if (!pte_update_error_ad) begin
        mem_ad[pte_update_addr_ad[13:2]] <= pte_update_data_ad;
      end
    end
  end

  mips_page_table_tlb_refill #(.ENABLE_AD_UPDATE(1'b1)) dut_ad (
    .clk(clk), .rst_n(rst_n),
    .miss_valid(miss_valid_ad), .miss_ready(miss_ready_ad),
    .miss_va(miss_va_ad), .ptbr(ptbr_ad),
    .miss_access(miss_access_ad), .miss_user(miss_user_ad),
    .miss_asid(miss_asid_ad),
    .mem_valid(mem_valid_ad), .mem_addr(mem_addr_ad),
    .mem_ready(mem_ready_ad), .mem_rdata(mem_rdata_ad), .mem_error(mem_error_ad),
    .walk_resp_valid(walk_resp_valid_ad), .walk_fault_valid(walk_fault_valid_ad),
    .walk_fault_code(walk_fault_code_ad), .walk_pa(walk_pa_ad),
    .tlb_wr_valid(tlb_wr_valid_ad), .tlb_wr_ready(tlb_wr_ready_ad),
    .tlb_wr_vpn2(tlb_wr_vpn2_ad), .tlb_wr_asid(tlb_wr_asid_ad),
    .tlb_wr_mask(tlb_wr_mask_ad),
    .tlb_wr_entrylo0(tlb_wr_entrylo0_ad), .tlb_wr_entrylo1(tlb_wr_entrylo1_ad),
    .pte_update_valid(pte_update_valid_ad),
    .pte_update_addr(pte_update_addr_ad),
    .pte_update_data(pte_update_data_ad),
    .pte_update_ready(pte_update_ready_ad),
    .pte_update_error(pte_update_error_ad)
  );

  task automatic run_walk_ad;
    integer guard;
    begin
      @(negedge clk); miss_valid_ad = 1;
      @(posedge clk); while (!miss_ready_ad) @(posedge clk);
      @(negedge clk); miss_valid_ad = 0;
      guard = 0;
      while (!tlb_wr_valid_ad && !walk_fault_valid_ad && guard < 200) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (!tlb_wr_valid_ad && !walk_fault_valid_ad) begin
        $display("ERROR: Timeout waiting for dut_ad walk completion");
        errors = errors + 1;
      end
    end
  endtask

  always #5 clk = ~clk;

  initial begin
    integer g;
    // -----------------------------------------------------------------------
    // Initial signal values
    // -----------------------------------------------------------------------
    ptbr = 32'h1000; miss_va = 32'h0000_0123; miss_asid = 8'h2;
    miss_access = 2'd1; miss_user = 1; miss_valid = 0;
    mem_ready = 1; mem_error = 0; tlb_wr_ready = 0;
    pte_update_ready = 1'b0; pte_update_error = 1'b0;

    ptbr_ad = 32'h1000; miss_va_ad = 32'h0000_0123; miss_asid_ad = 8'h2;
    miss_access_ad = 2'd1; miss_user_ad = 1; miss_valid_ad = 0;
    mem_ready_ad = 1; mem_error_ad = 0; tlb_wr_ready_ad = 0;
    pte_update_ready_ad = 1'b1; pte_update_error_ad = 1'b0;

    #23 rst_n = 1;

    // =======================================================================
    // Part 1: Default / Disabled Mode Tests
    // =======================================================================
    mem[1024] = 32'h0000_2003;
    mem[2048] = 32'h0000_300f; // A=0, D=0 in PTE, but update disabled
    run_walk;
    if (!tlb_wr_valid || tlb_wr_vpn2 !== 19'd0 || tlb_wr_asid !== 8'h2 ||
        tlb_wr_entrylo0[29:6] !== 24'h000003) errors = errors + 1;
    if (tlb_wr_entrylo1[1] !== 1'b0) errors = errors + 1;
    if (pte_update_valid) errors = errors + 1;
    @(negedge clk); tlb_wr_ready = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready = 0; @(posedge clk);
    if (tlb_wr_valid) errors = errors + 1;

    // Permanently-ready TLB in disabled mode
    mem[2048] = 32'h0000_300f; miss_access = 2'd1; tlb_wr_ready = 1; run_walk;
    if (!tlb_wr_valid || tlb_wr_entrylo0[29:6] !== 24'h000003) errors = errors + 1;
    @(posedge clk); #1; if (tlb_wr_valid) errors = errors + 1;
    @(negedge clk); tlb_wr_ready = 0;

    // Odd 4KB leaf occupies EntryLo1 only
    mem[2049] = 32'h0000_500f; miss_va = 32'h0000_1123; run_walk;
    if (!tlb_wr_valid || tlb_wr_entrylo0[1] !== 1'b0 ||
        !tlb_wr_entrylo1[1] || tlb_wr_entrylo1[29:6] !== 24'h000005) errors = errors + 1;
    @(negedge clk); tlb_wr_ready = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready = 0; @(posedge clk);
    miss_va = 32'h0000_0123;

    // D-side store permission
    mem[2048] = 32'h0000_300b; miss_access = 2'd2; run_walk;
    if (!tlb_wr_valid || !tlb_wr_entrylo0[6] || tlb_wr_entrylo0[2:0] !== 3'b110) errors = errors + 1;
    @(negedge clk); tlb_wr_ready = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready = 0; @(posedge clk);

    // User store without W must fault
    mem[2048] = 32'h0000_3009; miss_access = 2'd2; run_walk;
    if (!walk_fault_valid || walk_fault_code !== 3'd2 || tlb_wr_valid) errors = errors + 1;

    // =======================================================================
    // Part 2: Enabled Mode Tests (ENABLE_AD_UPDATE = 1)
    // =======================================================================
    // Set up page table: L1 at 0x1000 points to L2 at 0x2000
    mem_ad[1024] = 32'h0000_2003;

    // 2.1: Accessed-only update for read/load
    // Leaf PTE at 0x2000: PFN=3, W=1, X=1, U=1, V=1, A=0, D=0 (32'h0000_300f)
    mem_ad[2048] = 32'h0000_300f;
    miss_va_ad = 32'h0000_0123;
    miss_access_ad = 2'd1; // Load access
    miss_user_ad = 1;
    miss_asid_ad = 8'h2;
    pte_update_ready_ad = 1'b1;
    pte_update_error_ad = 1'b0;
    tlb_wr_ready_ad = 1'b0;
    pte_updates_ad = 0;

    run_walk_ad;
    if (!tlb_wr_valid_ad || walk_fault_valid_ad) errors = errors + 1;
    if (pte_updates_ad != 1) errors = errors + 1;
    if (last_pte_update_addr_ad !== 32'h0000_2000) errors = errors + 1;
    // Accessed bit 4 must be set (32'h0000_301f), Dirty bit 5 remains 0
    if (last_pte_update_data_ad !== 32'h0000_301f) errors = errors + 1;
    if (mem_ad[2048] !== 32'h0000_301f) errors = errors + 1;
    if (tlb_wr_vpn2_ad !== 19'd0 || tlb_wr_asid_ad !== 8'h2) errors = errors + 1;
    if (tlb_wr_entrylo0_ad[29:6] !== 24'h000003) errors = errors + 1;
    if (tlb_wr_entrylo1_ad[1] !== 1'b0) errors = errors + 1; // even page: entrylo1 invalid

    // Drain TLB write
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);
    if (tlb_wr_valid_ad) errors = errors + 1;

    // Re-walk with A already set: no second writeback request should occur
    run_walk_ad;
    if (pte_updates_ad != 1 || !tlb_wr_valid_ad || walk_fault_valid_ad) errors = errors + 1;
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);

    // 2.2: Dirty update for a store
    // Leaf PTE has W=1, U=1, V=1, A=0, D=0 (32'h0000_300b)
    mem_ad[2048] = 32'h0000_300b;
    miss_access_ad = 2'd2; // Store access
    pte_updates_ad = 0;
    run_walk_ad;
    if (!tlb_wr_valid_ad || walk_fault_valid_ad) errors = errors + 1;
    if (pte_updates_ad != 1) errors = errors + 1;
    if (last_pte_update_addr_ad !== 32'h0000_2000) errors = errors + 1;
    // Both Accessed (bit 4) and Dirty (bit 5) must be set -> 32'h0000_303b
    if (last_pte_update_data_ad !== 32'h0000_303b) errors = errors + 1;
    if (mem_ad[2048] !== 32'h0000_303b) errors = errors + 1;
    // MIPS EntryLo0 D bit (bit 2) must be 1 because PTE has W=1
    if (tlb_wr_entrylo0_ad[2:0] !== 3'b110) errors = errors + 1;
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);

    // 2.3: Backpressure stability on PTE update
    mem_ad[2048] = 32'h0000_300b;
    miss_access_ad = 2'd2;
    pte_update_ready_ad = 1'b0; // Hold consumer unready
    @(negedge clk); miss_valid_ad = 1;
    @(posedge clk); while (!miss_ready_ad) @(posedge clk);
    @(negedge clk); miss_valid_ad = 0;
    g = 0;
    while (!pte_update_valid_ad && g < 200) begin
      @(posedge clk);
      g = g + 1;
    end
    if (!pte_update_valid_ad) begin
      $display("ERROR: Timeout waiting for pte_update_valid_ad under backpressure");
      errors = errors + 1;
    end
    // Verify request and payload remain strictly stable across multiple stall cycles
    repeat (5) begin
      @(posedge clk);
      if (!pte_update_valid_ad) errors = errors + 1;
      if (pte_update_addr_ad !== 32'h0000_2000) errors = errors + 1;
      if (pte_update_data_ad !== 32'h0000_303b) errors = errors + 1;
      // TLB write must NOT be emitted until writeback handshake completes
      if (tlb_wr_valid_ad) errors = errors + 1;
      if (walk_resp_valid_ad) errors = errors + 1;
    end
    // Release backpressure
    @(negedge clk); pte_update_ready_ad = 1'b1;
    g = 0;
    while (!tlb_wr_valid_ad && g < 200) begin
      @(posedge clk);
      g = g + 1;
    end
    if (!tlb_wr_valid_ad) begin
      $display("ERROR: Timeout waiting for tlb_wr_valid_ad after releasing update backpressure");
      errors = errors + 1;
    end
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);

    // 2.4: Write-error fault propagation
    mem_ad[2048] = 32'h0000_300b;
    miss_access_ad = 2'd2;
    pte_update_ready_ad = 1'b1;
    pte_update_error_ad = 1'b1; // Signal write error
    run_walk_ad;
    // Walker must report fault with FAULT_BUS (3'd3)
    if (!walk_fault_valid_ad || walk_fault_code_ad !== 3'd3) errors = errors + 1;
    // TLB write must NOT be emitted on write error
    if (tlb_wr_valid_ad) errors = errors + 1;
    pte_update_error_ad = 1'b0;
    repeat(2) @(posedge clk);
    if (!miss_ready_ad) errors = errors + 1; // Adapter must return to idle and accept new misses

    // 2.5: Existing even/odd TLB entry selection in enabled mode
    // Even page (va[12] = 0): TLB EntryLo0 populated, EntryLo1 invalid
    mem_ad[2048] = 32'h0000_300f;
    miss_va_ad = 32'h0000_0123;
    miss_access_ad = 2'd1;
    pte_update_ready_ad = 1'b1;
    pte_update_error_ad = 1'b0;
    run_walk_ad;
    if (!tlb_wr_valid_ad || tlb_wr_vpn2_ad !== 19'd0 ||
        tlb_wr_entrylo0_ad[29:6] !== 24'h000003 || !tlb_wr_entrylo0_ad[1] ||
        tlb_wr_entrylo1_ad[1] !== 1'b0) errors = errors + 1;
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);

    // Odd page (va[12] = 1): TLB EntryLo1 populated, EntryLo0 invalid
    mem_ad[2049] = 32'h0000_500f; // leaf at 0x2004: PFN=5, A=0
    miss_va_ad = 32'h0000_1123;
    miss_access_ad = 2'd1;
    pte_updates_ad = 0;
    run_walk_ad;
    if (!tlb_wr_valid_ad || tlb_wr_vpn2_ad !== 19'd0 ||
        tlb_wr_entrylo0_ad[1] !== 1'b0 || !tlb_wr_entrylo1_ad[1] ||
        tlb_wr_entrylo1_ad[29:6] !== 24'h000005) errors = errors + 1;
    if (pte_updates_ad != 1 || last_pte_update_addr_ad !== 32'h0000_2004 ||
        last_pte_update_data_ad !== 32'h0000_501f) errors = errors + 1;
    @(negedge clk); tlb_wr_ready_ad = 1; repeat(2) @(posedge clk); @(negedge clk); tlb_wr_ready_ad = 0; @(posedge clk);

    // 2.6: Permanently-ready TLB with A/D update (never duplicate TLB write)
    mem_ad[2048] = 32'h0000_300f;
    miss_va_ad = 32'h0000_0123;
    miss_access_ad = 2'd1;
    tlb_wr_ready_ad = 1'b1; // Permanently ready
    run_walk_ad;
    if (!tlb_wr_valid_ad || tlb_wr_entrylo0_ad[29:6] !== 24'h000003) errors = errors + 1;
    @(posedge clk); #1;
    // Exactly 1 cycle pulse when tlb_wr_ready is 1
    if (tlb_wr_valid_ad) errors = errors + 1;
    repeat(3) begin
      @(posedge clk);
      if (tlb_wr_valid_ad) errors = errors + 1;
    end
    @(negedge clk); tlb_wr_ready_ad = 1'b0;

    // =======================================================================
    // Final signoff display
    // =======================================================================
    if (errors == 0) begin
      $display("REGRESSION_TEST_SUCCESS page_table_tlb_refill");
      $display("REGRESSION_TEST_SUCCESS page_table_tlb_refill_ad");
    end else begin
      $display("REGRESSION_TEST_FAILED page_table_tlb_refill errors=%0d", errors);
    end
    $finish;
  end
endmodule
