`timescale 1ns/1ps

module tb_mips_mmu_active;
    reg req_valid = 1'b1;
    reg [31:0] req_va = 32'b0;
    reg req_is_store = 1'b0;
    reg req_is_fetch = 1'b0;
    reg [7:0] asid = 8'h12;
    reg [2:0] config_k0 = 3'b011;
    reg is_kernel = 1'b1;
    reg tlb_lookup_hit = 1'b1;
    reg tlb_lookup_v = 1'b1;
    reg tlb_lookup_d = 1'b1;
    reg [2:0] tlb_lookup_c = 3'b011;
    reg [19:0] tlb_lookup_pfn = 20'h12345;

    wire [31:0] tlb_lookup_va;
    wire [7:0] tlb_lookup_asid;
    wire [31:0] pa;
    wire [2:0] cache_attr;
    wire translation_ok;
    wire [2:0] fault_type;
    integer errors = 0;

    mips_mmu dut (.*);

    task automatic check(input [255:0] name, input cond);
        begin
            if (!cond) begin $display("[FAIL] %0s", name); errors = errors + 1; end
            else $display("[PASS] %0s", name);
        end
    endtask

    initial begin
        // sseg uses the TLB when MMU is enabled.
        req_va = 32'hC123_4567;
        #1;
        check("sseg hit translates PFN and offset", pa == 32'h12345_567);
        check("sseg hit preserves C attribute", cache_attr == 3'b011);
        check("sseg hit succeeds", translation_ok && fault_type == 3'b000);

        // kseg3 follows the same translated path.
        req_va = 32'hE123_4000;
        #1;
        check("kseg3 hit translates", pa == 32'h12345_000 && translation_ok);

        // Invalid entries classify as TLBL/TLBS, not as a miss or Mod.
        tlb_lookup_v = 1'b0;
        req_va = 32'hC123_4000;
        req_is_store = 1'b0;
        #1;
        check("sseg invalid load is TLBL", !translation_ok && fault_type == 3'b001);
        req_is_store = 1'b1;
        #1;
        check("sseg invalid store is TLBS", !translation_ok && fault_type == 3'b010);

        // A valid, clean page rejects stores with Mod.
        tlb_lookup_v = 1'b1;
        tlb_lookup_d = 1'b0;
        req_va = 32'hE123_4000;
        #1;
        check("kseg3 clean store is Mod", !translation_ok && fault_type == 3'b011);
        req_is_store = 1'b0;
        #1;
        check("kseg3 clean load still succeeds", translation_ok && pa == 32'h12345_000);

        // Lookup sideband remains visible for the translated request.
        check("lookup VA sideband", tlb_lookup_va == req_va);
        check("lookup ASID sideband", tlb_lookup_asid == asid);

        if (errors == 0) $display("TB PASS (0 errors)");
        else $display("TB FAIL (%0d errors)", errors);
        $finish;
    end
    initial begin
        #100000;
        $display("TB TIMEOUT");
        $finish;
    end
endmodule
