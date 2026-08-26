// =============================================================================
// tb_mips_alu.sv — Standalone sanity for Phase B ISA R2 additions on the ALU.
// Verifies CLZ/CLO/SEB/SEH boundary values and typical inputs.
// =============================================================================

`timescale 1ns/1ps

module tb_mips_alu;
    reg  [31:0] op_a, op_b;
    reg  [4:0]  sa;
    reg  [4:0]  msbd;
    reg  [4:0]  alu_op;
    wire [31:0] alu_out;
    wire        overflow, zero;

    integer errors = 0;

    mips_alu dut (.*);

    task automatic check(input [255:0] name, input [31:0] expected);
        begin
            if (alu_out !== expected) begin
                $display("[FAIL] %0s (got %h, expected %h)", name, alu_out, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %h", name, alu_out);
            end
        end
    endtask

    initial begin
        // ----- CLZ (5'b10000) -----
        alu_op = 5'b10000;
        op_a   = 32'h0000_0000;  #1; check("CLZ(0) = 32",        32'd32);
        op_a   = 32'hFFFF_FFFF;  #1; check("CLZ(-1) = 0",        32'd0);
        op_a   = 32'h8000_0000;  #1; check("CLZ(0x80000000) = 0", 32'd0);
        op_a   = 32'h4000_0000;  #1; check("CLZ(0x40000000) = 1", 32'd1);
        op_a   = 32'h0000_0001;  #1; check("CLZ(0x00000001) = 31", 32'd31);
        op_a   = 32'h0000_00FF;  #1; check("CLZ(0x000000FF) = 24", 32'd24);
        op_a   = 32'h00FF_0000;  #1; check("CLZ(0x00FF0000) = 8",  32'd8);

        // ----- CLO (5'b10001) -----
        alu_op = 5'b10001;
        op_a   = 32'hFFFF_FFFF;  #1; check("CLO(-1) = 32",       32'd32);
        op_a   = 32'h0000_0000;  #1; check("CLO(0) = 0",         32'd0);
        op_a   = 32'hE000_0000;  #1; check("CLO(0xE0000000) = 3", 32'd3);
        op_a   = 32'hFFF0_0000;  #1; check("CLO(0xFFF00000) = 12", 32'd12);
        op_a   = 32'h7FFF_FFFF;  #1; check("CLO(0x7FFFFFFF) = 0",  32'd0);

        // ----- SEB (5'b10010) — sign-extend byte from op_b[7:0] -----
        alu_op = 5'b10010;
        op_b   = 32'hDEAD_BE00;  #1; check("SEB(0xDEADBE00) = 0",     32'h0000_0000);
        op_b   = 32'hDEAD_BE7F;  #1; check("SEB(0xDEADBE7F) = 0x7F",  32'h0000_007F);
        op_b   = 32'hDEAD_BE80;  #1; check("SEB(0xDEADBE80) = 0xFFFFFF80", 32'hFFFF_FF80);
        op_b   = 32'hDEAD_BEFF;  #1; check("SEB(0xDEADBEFF) = -1",    32'hFFFF_FFFF);

        // ----- SEH (5'b10011) — sign-extend halfword from op_b[15:0] -----
        alu_op = 5'b10011;
        op_b   = 32'hDEAD_0000;  #1; check("SEH(0xDEAD0000) = 0",         32'h0000_0000);
        op_b   = 32'hDEAD_7FFF;  #1; check("SEH(0xDEAD7FFF) = 0x7FFF",    32'h0000_7FFF);
        op_b   = 32'hDEAD_8000;  #1; check("SEH(0xDEAD8000) = 0xFFFF8000", 32'hFFFF_8000);
        op_b   = 32'hDEAD_FFFF;  #1; check("SEH(0xDEADFFFF) = -1",        32'hFFFF_FFFF);

        // ----- Sanity: legacy ADDU still works after widening -----
        alu_op = 5'b00001;    op_a = 32'd10; op_b = 32'd25; #1;
        check("ADDU(10, 25) = 35 (regression check)", 32'd35);

        // ----- WSBH (5'b10100) — byte-swap within each halfword of op_b -----
        alu_op = 5'b10100;
        op_b   = 32'h1122_3344;  #1; check("WSBH(0x11223344) = 0x22114433", 32'h2211_4433);
        op_b   = 32'hAABB_CCDD;  #1; check("WSBH(0xAABBCCDD) = 0xBBAADDCC", 32'hBBAA_DDCC);
        op_b   = 32'h0000_0000;  #1; check("WSBH(0) = 0",                    32'h0000_0000);
        op_b   = 32'hFFFF_FFFF;  #1; check("WSBH(-1) = -1",                  32'hFFFF_FFFF);

        // ----- WSBW (5'b11100) — swap the two halfwords -----
        alu_op = 5'b11100;
        op_b   = 32'h1122_3344;  #1; check("WSBW(0x11223344) = 0x33441122", 32'h3344_1122);
        op_b   = 32'hAABB_CCDD;  #1; check("WSBW(0xAABBCCDD) = 0xCCDDAABB", 32'hCCDD_AABB);

        // ----- ROTR (5'b10101) — rotate op_b right by sa -----
        alu_op = 5'b10101;
        op_b   = 32'h1234_5678; sa = 5'd0;  #1; check("ROTR(_,0) = original", 32'h1234_5678);
        op_b   = 32'h1234_5678; sa = 5'd4;  #1; check("ROTR(0x12345678,4)",   32'h8123_4567);
        op_b   = 32'h1234_5678; sa = 5'd8;  #1; check("ROTR(0x12345678,8)",   32'h7812_3456);
        op_b   = 32'h1234_5678; sa = 5'd16; #1; check("ROTR(0x12345678,16)",  32'h5678_1234);
        op_b   = 32'h1234_5678; sa = 5'd31; #1; check("ROTR(0x12345678,31)",
                                                       32'h2468_ACF0);   // = original << 1 wrap
        // sanity: ROTR(0, sa) always 0
        op_b   = 32'h0000_0000; sa = 5'd7;  #1; check("ROTR(0,7) = 0", 32'h0000_0000);

        // ----- MOV_PASS (5'b10110) — passes op_a through -----
        alu_op = 5'b10110;
        op_a   = 32'hCAFE_BABE; op_b = 32'h0; #1;
        check("MOV_PASS = op_a", 32'hCAFE_BABE);
        op_a   = 32'h1234_5678; op_b = 32'hFFFF_FFFF; #1;
        check("MOV_PASS ignores op_b", 32'h1234_5678);

        if (errors == 0) $display("TB PASS (0 errors)");
        else             $display("TB FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
