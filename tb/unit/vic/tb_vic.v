// Unit test: apb_vic — priority encoding, edge trigger, nesting, ACK, soft
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
        .irq(irq), .vec_id(vec_id), .vec_prio(vec_prio));

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

    initial begin
        #12 rst_n = 1;
        @(negedge clk);

        // ---- Setup: enable src 3 and src 7 as level, priority 3 and 5 ----
        apb_write(12'h004, 32'h0000_0088);       // enable src[3] and src[7] (0x004 ENABLE)
        apb_write(12'h100 + 4*3, 32'h3);         // prio[3] = 3
        apb_write(12'h100 + 4*7, 32'h5);         // prio[7] = 5
        apb_write(12'h014, 32'h0);               // all level
        apb_write(12'h018, 32'h0);               // all active-high

        // ---- Assert both sources; expect irq, vec_id=7 (higher prio) ----
        src_in = 32'h0000_0088;
        repeat (5) @(negedge clk);
        if (!irq) begin $display("FAIL: irq should be high"); errs=errs+1; end
        if (vec_id !== 8'd7)  begin $display("FAIL: vec_id=%d expected 7", vec_id); errs=errs+1; end
        if (vec_prio !== 4'd5) begin $display("FAIL: vec_prio=%d expected 5", vec_prio); errs=errs+1; end

        // ---- Read VEC_ID → source 7 becomes ACTIVE, running_prio=5 ----
        apb_read(12'h200, rd_data);
        if (rd_data !== 32'd7) begin $display("FAIL VEC_ID readback"); errs=errs+1; end
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h0000_0080) begin $display("FAIL ACTIVE=%h expected 0x80", rd_data); errs=errs+1; end
        apb_read(12'h210, rd_data);
        if (rd_data !== 32'd5) begin $display("FAIL RUNNING_PRIO=%d expected 5", rd_data); errs=errs+1; end

        // ---- Nesting: src 3 (prio 3) < running_prio 5 → irq stays low ----
        // Even though src 3 still pending, its prio doesn't preempt.
        repeat (3) @(negedge clk);
        if (irq) begin $display("FAIL: irq should be low (nested prio 3 < 5)"); errs=errs+1; end

        // ---- Level src 7 drops → still active; ACK required ----
        src_in = 32'h0000_0008; // only src 3 held
        repeat (3) @(negedge clk);
        // src 3 pending, but active src 7 has running_prio 5 > 3
        if (irq) begin $display("FAIL: irq should be low while src7 still active"); errs=errs+1; end

        // ---- ACK src 7 ----
        apb_write(12'h208, 32'h0000_0080);
        repeat (3) @(negedge clk);
        apb_read(12'h20C, rd_data);
        if (rd_data !== 32'h0) begin $display("FAIL ACTIVE post-ACK=%h", rd_data); errs=errs+1; end
        // Now src 3 (level, held) should raise irq
        if (!irq) begin $display("FAIL: irq should be high for src3 after ack"); errs=errs+1; end
        if (vec_id !== 8'd3) begin $display("FAIL vec_id=%d after ack", vec_id); errs=errs+1; end

        // ---- Edge trigger test on src 10 ----
        apb_write(12'h014, 32'h0000_0400);       // type[10] = edge
        apb_write(12'h004, 32'h0000_0400);       // enable only src 10
        apb_write(12'h100 + 4*10, 32'h7);        // prio[10] = 7
        src_in = 32'h0;                          // drop src 3 too
        @(negedge clk);
        // Pulse src 10
        src_in = 32'h0000_0400;
        @(negedge clk);
        src_in = 32'h0;
        repeat (5) @(negedge clk);
        if (!irq) begin $display("FAIL: edge irq should latch"); errs=errs+1; end
        if (vec_id !== 8'd10) begin $display("FAIL edge vec_id=%d", vec_id); errs=errs+1; end
        // ACK the edge
        apb_read(12'h200, rd_data);              // accept
        apb_write(12'h208, 32'h0000_0400);       // ack
        repeat (3) @(negedge clk);
        if (irq) begin $display("FAIL: edge irq should clear after ack"); errs=errs+1; end

        // ---- Soft trigger on src 1 ----
        apb_write(12'h004, 32'h0000_0002);
        apb_write(12'h100 + 4*1, 32'h9);
        apb_write(12'h01C, 32'h0000_0002);       // soft trigger src 1
        repeat (3) @(negedge clk);
        if (!irq) begin $display("FAIL: soft irq should fire"); errs=errs+1; end
        if (vec_id !== 8'd1) begin $display("FAIL soft vec_id=%d", vec_id); errs=errs+1; end
        // Clear soft
        apb_write(12'h020, 32'h0000_0002);
        repeat (3) @(negedge clk);
        if (irq) begin $display("FAIL: soft irq should clear"); errs=errs+1; end

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS vic");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #200000 $display("FAIL timeout"); $finish;
    end
endmodule
