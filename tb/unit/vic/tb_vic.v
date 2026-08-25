// =============================================================================
// File Name: tb_vic.v
// Design:    Unit Testbench for Phase 4D apb_vic Commercial Closure
// Author:    Antigravity — Phase 4D
// Description:
//   Comprehensive testbench for apb_vic verifying all 16 required commercial
//   contract behaviors per docs/block_specs/vic_spec.md.
// =============================================================================
`timescale 1ns/1ps

module tb_vic;
    reg          clk = 0;
    reg          rst_n = 0;
    reg          psel = 0, penable = 0, pwrite = 0;
    reg  [11:0]  paddr = 0;
    reg  [31:0]  pwdata = 0;
    wire [31:0]  prdata;
    wire         pready, pslverr;
    reg  [31:0]  src_in = 0;
    wire         irq;
    wire [7:0]   vec_id;
    wire [3:0]   vec_prio;

    integer errs = 0;

    always #5 clk = ~clk;

    apb_vic #(.NUM_SOURCES(32)) dut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .src_in(src_in),
        .irq(irq), .vec_id(vec_id), .vec_prio(vec_prio)
    );

    task apb_write(input [11:0] a, input [31:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 1; paddr = a; pwdata = d;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        psel = 0; pwrite = 0; penable = 0;
    end
    endtask

    task apb_read(input [11:0] a, output [31:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 0; paddr = a;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        d = prdata;
        psel = 0; penable = 0;
    end
    endtask

    reg [31:0] rd_data;
    integer i;

    initial begin
        #12 rst_n = 1;
        @(negedge clk);

        // ------------------------------------------------------------------
        // Check 1: Reset defaults and no-IRQ state
        // ------------------------------------------------------------------
        $display("--- Check 1: Reset defaults ---");
        if (irq !== 1'b0) begin $display("FAIL Check 1: irq not 0 on reset"); errs=errs+1; end
        if (vec_id !== 8'hFF) begin $display("FAIL Check 1: vec_id not 0xFF on reset, got %h", vec_id); errs=errs+1; end
        if (vec_prio !== 4'h0) begin $display("FAIL Check 1: vec_prio not 0 on reset"); errs=errs+1; end

        apb_read(12'h000, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: RAW!=0"); errs=errs+1; end
        apb_read(12'h004, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: ENABLE!=0"); errs=errs+1; end
        apb_read(12'h008, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: MASKED!=0"); errs=errs+1; end
        apb_read(12'h014, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: TYPE!=0"); errs=errs+1; end
        apb_read(12'h018, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: POLARITY!=0"); errs=errs+1; end
        apb_read(12'h01C, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: SOFT!=0"); errs=errs+1; end
        apb_read(12'h200, rd_data); if (rd_data !== 32'hFF) begin $display("FAIL Check 1: VEC_ID!=0xFF"); errs=errs+1; end
        apb_read(12'h204, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: VEC_IPRIO!=0"); errs=errs+1; end
        apb_read(12'h20C, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: ACTIVE!=0"); errs=errs+1; end
        apb_read(12'h210, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 1: RUNNING_PRIO!=0"); errs=errs+1; end

        // ------------------------------------------------------------------
        // Check 2: RW enable plus ENABLE_SET / ENABLE_CLR
        // ------------------------------------------------------------------
        $display("--- Check 2: RW enable plus ENABLE_SET / ENABLE_CLR ---");
        apb_write(12'h004, 32'h0000_000F); // Direct write
        apb_read(12'h004, rd_data);
        if (rd_data !== 32'h0000_000F) begin $display("FAIL Check 2: ENABLE direct write=%h", rd_data); errs=errs+1; end

        apb_write(12'h00C, 32'h0000_00F0); // SET
        apb_read(12'h004, rd_data);
        if (rd_data !== 32'h0000_00FF) begin $display("FAIL Check 2: ENABLE_SET=%h", rd_data); errs=errs+1; end

        apb_write(12'h010, 32'h0000_0005); // CLR
        apb_read(12'h004, rd_data);
        if (rd_data !== 32'h0000_00FA) begin $display("FAIL Check 2: ENABLE_CLR=%h", rd_data); errs=errs+1; end

        apb_write(12'h004, 32'h0000_0000); // clear all enable

        // ------------------------------------------------------------------
        // Check 3: Priority arbitration and same-priority lower-ID tie-break
        // ------------------------------------------------------------------
        $display("--- Check 3: Priority arbitration and tie-break ---");
        apb_write(12'h004, 32'h0000_0288);       // enable src 3, 7, 9
        apb_write(12'h100 + 4*3, 32'h4);         // prio[3] = 4
        apb_write(12'h100 + 4*7, 32'h8);         // prio[7] = 8 (highest)
        apb_write(12'h100 + 4*9, 32'h8);         // prio[9] = 8 (same priority, higher ID)

        src_in = 32'h0000_0288;
        repeat (5) @(negedge clk);
        if (!irq) begin $display("FAIL Check 3: irq high expected"); errs=errs+1; end
        if (vec_id !== 8'd7) begin $display("FAIL Check 3: vec_id expected 7 (lower ID wins tie-break), got %d", vec_id); errs=errs+1; end
        if (vec_prio !== 4'd8) begin $display("FAIL Check 3: vec_prio expected 8, got %d", vec_prio); errs=errs+1; end

        src_in = 32'h0;
        apb_write(12'h004, 32'h0); // disable all

        // ------------------------------------------------------------------
        // Check 4: No-pending VEC_ID = 8'hFF and VEC_IPRIO = 0
        // ------------------------------------------------------------------
        $display("--- Check 4: No-pending defaults ---");
        repeat (3) @(negedge clk);
        if (vec_id !== 8'hFF || vec_prio !== 4'h0 || irq !== 1'b0) begin
            $display("FAIL Check 4: no-pending default state mismatch"); errs=errs+1;
        end

        // ------------------------------------------------------------------
        // Check 5 & 6 & 7 & 8 & 9: APB VEC_ID accept, ACTIVE, repeated reads,
        // nested suppression, preemption, ACK clear and RUNNING_PRIO rollback
        // ------------------------------------------------------------------
        $display("--- Check 5-9: Nesting, Preemption, Accept & ACK ---");
        // Setup: src 3 (prio 3), src 7 (prio 5), src 12 (prio 8)
        apb_write(12'h100 + 4*3, 32'h3);
        apb_write(12'h100 + 4*7, 32'h5);
        apb_write(12'h100 + 4*12, 32'h8);
        apb_write(12'h004, (1<<3) | (1<<7) | (1<<12)); // enable 3, 7, 12

        // Assert src 3 and src 7
        src_in = (1<<3) | (1<<7);
        repeat (5) @(negedge clk);
        if (!irq || vec_id !== 8'd7 || vec_prio !== 4'd5) begin
            $display("FAIL Check 5: initial irq/vec_id for src 7"); errs=errs+1;
        end

        // Accept src 7 by reading VEC_ID
        apb_read(12'h200, rd_data);
        if (rd_data !== 32'd7) begin $display("FAIL Check 5: VEC_ID read != 7"); errs=errs+1; end

        // Check ACTIVE = (1<<7) and RUNNING_PRIO = 5
        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<7)) begin $display("FAIL Check 5: ACTIVE expected 0x80, got %h", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'd5) begin $display("FAIL Check 5: RUNNING_PRIO expected 5, got %d", rd_data); errs=errs+1; end

        // Check 6: Repeated VEC_ID read when irq=0 must not corrupt active state
        repeat (3) @(negedge clk);
        if (irq !== 1'b0) begin $display("FAIL Check 7: irq should be 0 while src 3 (prio 3) < RUNNING_PRIO (5)"); errs=errs+1; end

        apb_read(12'h200, rd_data); // repeated read while irq=0
        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<7)) begin $display("FAIL Check 6: repeated read corrupted ACTIVE: %h", rd_data); errs=errs+1; end

        // Check 8: Strict higher-priority preemption by src 12 (prio 8)
        src_in = (1<<3) | (1<<7) | (1<<12);
        repeat (5) @(negedge clk);
        if (!irq || vec_id !== 8'd12 || vec_prio !== 4'd8) begin
            $display("FAIL Check 8: preemption irq/vec_id failed for src 12"); errs=errs+1;
        end

        // Accept src 12
        apb_read(12'h200, rd_data);
        apb_read(12'h20C, rd_data);
        if (rd_data !== ((1<<7) | (1<<12))) begin $display("FAIL Check 8: nested ACTIVE state expected 0x1080, got %h", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'd8) begin $display("FAIL Check 8: RUNNING_PRIO expected 8, got %d", rd_data); errs=errs+1; end

        // Check 9: ACK src 12, RUNNING_PRIO rollback to 5
        src_in = (1<<3) | (1<<7); // drop src 12
        apb_write(12'h208, (1<<12)); // ACK src 12
        repeat (5) @(negedge clk);

        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<7)) begin $display("FAIL Check 9: ACTIVE post ACK 12 expected 0x80, got %h", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'd5) begin $display("FAIL Check 9: RUNNING_PRIO rollback expected 5, got %d", rd_data); errs=errs+1; end

        // ACK src 7 & drop src 7 -> src 3 becomes active
        src_in = (1<<3);
        apb_write(12'h208, (1<<7)); // ACK src 7
        repeat (5) @(negedge clk);
        if (!irq || vec_id !== 8'd3) begin $display("FAIL Check 9: src 3 irq after ACK src 7"); errs=errs+1; end

        // ACK src 3
        apb_read(12'h200, rd_data); // accept src 3
        src_in = 32'h0;
        apb_write(12'h208, (1<<3));
        repeat (5) @(negedge clk);
        apb_read(12'h20C, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 9: ACTIVE post ACK 3 non-zero"); errs=errs+1; end
        apb_read(12'h210, rd_data); if (rd_data !== 32'h0) begin $display("FAIL Check 9: RUNNING_PRIO post ACK 3 non-zero"); errs=errs+1; end

        // ------------------------------------------------------------------
        // Check 9b: Four-level priority nesting and reverse unwind
        // ------------------------------------------------------------------
        $display("--- Check 9b: Four-level priority nesting ---");
        apb_write(12'h004, 32'h0);
        apb_write(12'h014, 32'h0); // level-high sources
        apb_write(12'h018, 32'h0);
        apb_write(12'h100 + 4*2, 32'h3);
        apb_write(12'h100 + 4*4, 32'h6);
        apb_write(12'h100 + 4*6, 32'h9);
        apb_write(12'h100 + 4*8, 32'hC);
        apb_write(12'h004, 32'h00000154); // sources 2,4,6,8

        // Accept one progressively higher-priority source at a time.
        src_in = 32'h00000004;
        repeat (4) @(negedge clk);
        if (!irq || vec_id !== 8'd2 || vec_prio !== 4'h3) begin
            $display("FAIL Check 9b: level 1 source 2 not selected"); errs=errs+1;
        end
        apb_read(12'h200, rd_data);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h00000004) begin $display("FAIL Check 9b: active level 1=%h", rd_data); errs=errs+1; end

        src_in = 32'h00000014; // add source 4
        repeat (4) @(negedge clk);
        if (!irq || vec_id !== 8'd4 || vec_prio !== 4'h6) begin
            $display("FAIL Check 9b: level 2 source 4 did not preempt"); errs=errs+1;
        end
        apb_read(12'h200, rd_data);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h00000014) begin $display("FAIL Check 9b: active level 2=%h", rd_data); errs=errs+1; end

        src_in = 32'h00000054; // add source 6
        repeat (4) @(negedge clk);
        if (!irq || vec_id !== 8'd6 || vec_prio !== 4'h9) begin
            $display("FAIL Check 9b: level 3 source 6 did not preempt"); errs=errs+1;
        end
        apb_read(12'h200, rd_data);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h00000054) begin $display("FAIL Check 9b: active level 3=%h", rd_data); errs=errs+1; end

        src_in = 32'h00000154; // add source 8
        repeat (4) @(negedge clk);
        if (!irq || vec_id !== 8'd8 || vec_prio !== 4'hC) begin
            $display("FAIL Check 9b: level 4 source 8 did not preempt"); errs=errs+1;
        end
        apb_read(12'h200, rd_data);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h00000154) begin $display("FAIL Check 9b: active level 4=%h", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'hC) begin $display("FAIL Check 9b: running priority level 4=%h", rd_data); errs=errs+1; end

        // Deassert levels before ACK so each frame unwinds without re-entry.
        src_in = 32'h0;
        apb_write(12'h208, 32'h00000100);
        apb_write(12'h208, 32'h00000040);
        apb_write(12'h208, 32'h00000010);
        apb_write(12'h208, 32'h00000004);
        repeat (4) @(negedge clk);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h0) begin $display("FAIL Check 9b: reverse ACK left active=%h", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'h0) begin $display("FAIL Check 9b: reverse ACK left running=%h", rd_data); errs=errs+1; end
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 10: Trigger modes (level high/low, rising/falling edge)
        // ------------------------------------------------------------------
        $display("--- Check 10: Trigger modes ---");
        // src 0: level high, src 1: level low, src 2: rising edge, src 3: falling edge
        apb_write(12'h014, (1<<2) | (1<<3)); // TYPE: 0, 1 level; 2, 3 edge
        apb_write(12'h018, (1<<1) | (1<<3)); // POLARITY: 0 high, 1 low, 2 rising, 3 falling
        apb_write(12'h004, 32'h0000_000F); // enable 0..3

        // Level low test on src 1 (src_in[1] = 0 -> active)
        src_in = 32'h0000_0001; // src 1 is 0, src 0 is 1
        repeat (5) @(negedge clk);
        apb_read(12'h000, rd_data); // RAW
        if ((rd_data & 32'h3) !== 32'h3) begin $display("FAIL Check 10: level high & level low RAW=%h", rd_data); errs=errs+1; end

        // Edge test: pulse src 2 (0 -> 1)
        src_in = 32'h0000_0005; // src 2 goes high
        repeat (2) @(negedge clk);
        src_in = 32'h0000_0001; // src 2 drops low
        repeat (5) @(negedge clk);
        apb_read(12'h000, rd_data);
        if (!(rd_data & (1<<2))) begin $display("FAIL Check 10: rising edge pending not latched"); errs=errs+1; end
        apb_write(12'h208, (1<<2)); // ACK edge 2

        // Falling edge test on src 3: 1 -> 0
        src_in = 32'h0000_0009; // src 3 set high first
        repeat (4) @(negedge clk);
        src_in = 32'h0000_0001; // src 3 goes low (falling edge)
        repeat (5) @(negedge clk);
        apb_read(12'h000, rd_data);
        if (!(rd_data & (1<<3))) begin $display("FAIL Check 10: falling edge pending not latched"); errs=errs+1; end
        apb_write(12'h208, (1<<3)); // ACK edge 3

        src_in = 32'h0;
        apb_write(12'h014, 32'h0);
        apb_write(12'h018, 32'h0);
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 11: ACK of level source while still asserted vs deassertion
        // ------------------------------------------------------------------
        $display("--- Check 11: ACK level source while asserted ---");
        apb_write(12'h004, (1<<5)); // enable src 5
        apb_write(12'h100 + 4*5, 32'h6);
        src_in = (1<<5); // assert src 5
        repeat (5) @(negedge clk);
        apb_read(12'h200, rd_data); // accept -> ACTIVE bit 5 set
        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<5)) begin $display("FAIL Check 11: ACTIVE bit 5 not set"); errs=errs+1; end

        // ACK src 5 while level is STILL asserted
        apb_write(12'h208, (1<<5));
        repeat (5) @(negedge clk);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h0) begin $display("FAIL Check 11: ACTIVE bit 5 not cleared post ACK"); errs=errs+1; end
        if (!irq) begin $display("FAIL Check 11: level source should remain pending and fire irq again post ACK while asserted"); errs=errs+1; end

        src_in = 32'h0; // deassert level source
        repeat (5) @(negedge clk);
        if (irq) begin $display("FAIL Check 11: irq should drop after level source deasserted"); errs=errs+1; end
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 12: Software trigger and SOFT_CLR
        // ------------------------------------------------------------------
        $display("--- Check 12: Software trigger ---");
        apb_write(12'h004, (1<<1)); // enable src 1
        apb_write(12'h100 + 4*1, 32'h9);
        apb_write(12'h01C, (1<<1)); // SOFT set
        repeat (5) @(negedge clk);
        if (!irq || vec_id !== 8'd1) begin $display("FAIL Check 12: soft IRQ failed to fire"); errs=errs+1; end
        apb_read(12'h01C, rd_data);
        if (rd_data !== (1<<1)) begin $display("FAIL Check 12: SOFT readback mismatch"); errs=errs+1; end

        apb_write(12'h020, (1<<1)); // SOFT_CLR
        repeat (5) @(negedge clk);
        if (irq) begin $display("FAIL Check 12: soft IRQ failed to clear via SOFT_CLR"); errs=errs+1; end
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 13: Mask while pending/active
        // ------------------------------------------------------------------
        $display("--- Check 13: Mask while pending/active ---");
        apb_write(12'h004, (1<<4)); // enable src 4
        src_in = (1<<4);
        repeat (5) @(negedge clk);
        apb_read(12'h200, rd_data); // accept -> active bit 4
        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<4)) begin $display("FAIL Check 13: active bit 4 not set"); errs=errs+1; end

        apb_write(12'h010, (1<<4)); // MASK (disable) src 4 while active
        repeat (3) @(negedge clk);
        apb_read(12'h20C, rd_data);
        if (rd_data !== (1<<4)) begin $display("FAIL Check 13: active bit 4 corrupted by mask clear"); errs=errs+1; end
        apb_read(12'h008, rd_data); // MASKED pending
        if (rd_data !== 32'h0) begin $display("FAIL Check 13: MASKED pending should be 0"); errs=errs+1; end

        apb_write(12'h208, (1<<4)); // ACK
        src_in = 32'h0;

        // ------------------------------------------------------------------
        // Check 14: 32-source all-pending read/selection consistency
        // ------------------------------------------------------------------
        $display("--- Check 14: 32-source all-pending selection ---");
        apb_write(12'h004, 32'hFFFF_FFFF); // enable all 32 sources
        for (i = 0; i < 32; i = i + 1) begin
            apb_write(12'h100 + 4*i, i[3:0]); // prio 0..15 repeating
        end
        src_in = 32'hFFFF_FFFF;
        repeat (5) @(negedge clk);
        if (!irq) begin $display("FAIL Check 14: irq not set for all-pending"); errs=errs+1; end
        // prio 15 set for src 15 and src 31. Lower ID (15) wins tie-break.
        if (vec_id !== 8'd15 || vec_prio !== 4'd15) begin
            $display("FAIL Check 14: expected vec_id=15, vec_prio=15; got vec_id=%d, vec_prio=%d", vec_id, vec_prio); errs=errs+1;
        end

        src_in = 32'h0;
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 15: Legacy low-offset compatibility
        // ------------------------------------------------------------------
        $display("--- Check 15: Legacy low-offset compatibility ---");
        apb_write(12'h004, 32'h0000_0010);       // enable src 4
        src_in = 32'h0000_0010;                  // assert src 4
        repeat (5) @(negedge clk);
        apb_read(12'h000, rd_data); // RAW
        if (rd_data !== 32'h0000_0010) begin $display("FAIL Check 15: low-offset RAW=%h", rd_data); errs=errs+1; end
        apb_read(12'h004, rd_data); // ENABLE
        if (rd_data !== 32'h0000_0010) begin $display("FAIL Check 15: low-offset ENABLE=%h", rd_data); errs=errs+1; end
        apb_read(12'h008, rd_data); // MASKED
        if (rd_data !== 32'h0000_0010) begin $display("FAIL Check 15: low-offset MASKED=%h", rd_data); errs=errs+1; end

        src_in = 32'h0;
        apb_write(12'h004, 32'h0);

        // ------------------------------------------------------------------
        // Check 16: Unsupported APB address read zero with no error
        // ------------------------------------------------------------------
        $display("--- Check 16: Unsupported APB address ---");
        apb_read(12'h300, rd_data);
        if (rd_data !== 32'h0 || pready !== 1'b1 || pslverr !== 1'b0) begin
            $display("FAIL Check 16: unsupported address 0x300 read failed: prdata=%h pready=%b pslverr=%b", rd_data, pready, pslverr); errs=errs+1;
        end
        apb_read(12'h400, rd_data);
        if (rd_data !== 32'h0 || pready !== 1'b1 || pslverr !== 1'b0) begin
            $display("FAIL Check 16: unsupported address 0x400 read failed: prdata=%h pready=%b pslverr=%b", rd_data, pready, pslverr); errs=errs+1;
        end

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        if (errs == 0) $display("REGRESSION_TEST_SUCCESS vic");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #300000 $display("FAIL timeout"); $finish;
    end
endmodule
