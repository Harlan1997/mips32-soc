// =============================================================================
// tb_mips_bpu.sv — Standalone sanity for Phase B.6 mips_bpu.
// Verifies:
//   1) Reset state — no BTB hits.
//   2) Resolve a taken conditional branch → subsequent predict at same PC hits
//      BTB and returns predicted taken with correct target after BHT ramps.
//   3) BHT saturation: 4 taken updates keep counter at ST; 4 not-taken drop
//      it to SN.
//   4) Direct jump (type=01) always predicted taken with target.
//   5) RAS push on call (type=11) → pop on return (type=10) returns pushed
//      target.
// =============================================================================

`timescale 1ns/1ps

module tb_mips_bpu;
    reg  clk = 0, rst_n = 0;
    reg  if_valid = 0;
    reg  [31:0] if_pc = 0;
    wire predict_hit, predict_taken;
    wire [31:0] predict_target;
    wire [1:0]  predict_type;

    reg  resolve_valid = 0;
    reg  [31:0] resolve_pc = 0;
    reg  resolve_taken = 0;
    reg  [31:0] resolve_target = 0;
    reg  [1:0]  resolve_type = 0;
    reg  resolve_mispredict = 0;
    reg  flush_if = 0;

    integer errors = 0;

    mips_bpu dut (.*);

    always #5 clk = ~clk;

    task automatic check(input [255:0] name, input cond);
        begin
            if (!cond) begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s", name);
            end
        end
    endtask

    task automatic do_resolve(input [31:0] pc, input taken,
                              input [31:0] tgt, input [1:0] rtype);
        begin
            @(posedge clk);
            resolve_valid  <= 1'b1;
            resolve_pc     <= pc;
            resolve_taken  <= taken;
            resolve_target <= tgt;
            resolve_type   <= rtype;
            @(posedge clk);
            resolve_valid  <= 1'b0;
        end
    endtask

    initial begin
        #12 rst_n = 1;
        @(posedge clk);

        // 1) Reset state
        if_valid = 1; if_pc = 32'h0000_1000;
        #1;
        check("Reset: BTB miss", predict_hit == 1'b0);

        // 2) Resolve a taken conditional branch at PC=0x1000 → target=0x1080
        do_resolve(32'h0000_1000, 1'b1, 32'h0000_1080, 2'b00);
        if_pc = 32'h0000_1000; #1;
        check("Cond taken: BTB hit after resolve", predict_hit == 1'b1);
        // BHT was WN(01) → taken bump → WT(10) → predict_taken now = 1
        check("Cond taken: predict_taken=1 after 1 taken bump", predict_taken == 1'b1);
        check("Cond taken: target = 0x1080", predict_target == 32'h0000_1080);
        check("Cond taken: type = 00", predict_type == 2'b00);

        // 3) BHT saturation: 4 more taken updates → still ST (11)
        do_resolve(32'h0000_1000, 1'b1, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b1, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b1, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b1, 32'h0000_1080, 2'b00);
        if_pc = 32'h0000_1000; #1;
        check("BHT sat: still predict_taken after 4 more taken", predict_taken == 1'b1);

        // 4 not-taken updates → back down to SN(00)
        do_resolve(32'h0000_1000, 1'b0, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b0, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b0, 32'h0000_1080, 2'b00);
        do_resolve(32'h0000_1000, 1'b0, 32'h0000_1080, 2'b00);
        if_pc = 32'h0000_1000; #1;
        check("BHT sat: predict_taken=0 after 4 not-taken", predict_taken == 1'b0);

        // A not-taken conditional branch retains its BTB entry while the
        // direction counter learns the fall-through path.
        check("Not-taken: BTB entry retained", predict_hit == 1'b1);

        // 5) Direct jump: type 01 always predicted taken
        do_resolve(32'h0000_2000, 1'b1, 32'h0000_20A0, 2'b01);
        if_pc = 32'h0000_2000; #1;
        check("Direct jump: predict_hit",   predict_hit   == 1'b1);
        check("Direct jump: predict_taken", predict_taken == 1'b1);
        check("Direct jump: target = 0x20A0", predict_target == 32'h0000_20A0);

        // 6) RAS: push on call (type=11) then pop on return (type=10)
        do_resolve(32'h0000_3000, 1'b1, 32'h0000_4000, 2'b11);
        // predict on the return PC should hit and predict target = 0x3008 (call+8)
        if_pc = 32'h0000_5000;
        // First need to allocate BTB entry for PC=0x5000 as type 10 (JR)
        do_resolve(32'h0000_5000, 1'b1, 32'h0000_dead, 2'b10);
        if_pc = 32'h0000_5000; #1;
        check("RAS: JR predict_hit",     predict_hit == 1'b1);
        check("RAS: JR type readback",   predict_type == 2'b10);
        check("RAS: JR target = call+8", predict_target == 32'h0000_3008);

        if (errors == 0) $display("TB PASS (0 errors)");
        else             $display("TB FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin #200000; $display("TB TIMEOUT"); $finish; end
endmodule
