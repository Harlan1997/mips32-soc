// Focused TLB/MMU contract test.
// Verifies ASID isolation, Global matching, and the distinction between
// matching-invalid, modified, and refill faults at the MMU boundary.
`timescale 1ns/1ps

module tb_tlb_asid_policy;
    localparam integer TLB_ENTRIES = 4;
    localparam integer INDEX_BITS  = 2;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg                  wr_en = 1'b0;
    reg  [INDEX_BITS-1:0] wr_index = {INDEX_BITS{1'b0}};
    reg  [18:0]          wr_vpn2 = 19'b0;
    reg  [7:0]           wr_asid = 8'b0;
    reg  [15:0]          wr_mask = 16'b0;
    reg  [31:0]          wr_entrylo0 = 32'b0;
    reg  [31:0]          wr_entrylo1 = 32'b0;

    wire [18:0]          rd_vpn2;
    wire [7:0]           rd_asid;
    wire [15:0]          rd_mask;
    wire [31:0]          rd_entrylo0;
    wire [31:0]          rd_entrylo1;
    wire                 probe_hit;
    wire [INDEX_BITS-1:0] probe_index;

    wire [31:0] mmu_tlb_va;
    wire [7:0]  mmu_tlb_asid;
    wire        tlb_hit;
    wire        tlb_v;
    wire        tlb_d;
    wire [2:0]  tlb_c;
    wire [19:0] tlb_pfn;

    reg         req_valid = 1'b0;
    reg  [31:0] req_va = 32'b0;
    reg         req_is_store = 1'b0;
    reg         req_is_fetch = 1'b0;
    reg  [7:0]  asid = 8'b0;
    reg  [2:0]  config_k0 = 3'b011;
    reg         is_kernel = 1'b1;

    wire [31:0] pa;
    wire [2:0]  cache_attr;
    wire        translation_ok;
    wire [2:0]  fault_type;

    integer errors = 0;

    function [31:0] make_lo;
        input [19:0] pfn;
        input [2:0]  c;
        input        d;
        input        v;
        input        g;
        begin
            make_lo = {6'b0, pfn, c, d, v, g};
        end
    endfunction

    task automatic check;
        input [511:0] name;
        input         condition;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s", name);
            end
        end
    endtask

    task automatic write_entry;
        input [1:0]  index;
        input [18:0] vpn2;
        input [7:0]  entry_asid;
        input [31:0] lo0;
        input [31:0] lo1;
        begin
            @(negedge clk);
            wr_index    = index;
            wr_vpn2     = vpn2;
            wr_asid     = entry_asid;
            wr_mask     = 16'b0; // 4 KiB pair for this contract gate
            wr_entrylo0 = lo0;
            wr_entrylo1 = lo1;
            wr_en       = 1'b1;
            @(posedge clk);
            #1;
            wr_en       = 1'b0;
        end
    endtask

    mips_tlb #(
        .TLB_ENTRIES (TLB_ENTRIES),
        .INDEX_BITS  (INDEX_BITS)
    ) dut_tlb (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en),
        .wr_index     (wr_index),
        .wr_vpn2      (wr_vpn2),
        .wr_asid      (wr_asid),
        .wr_mask      (wr_mask),
        .wr_entrylo0  (wr_entrylo0),
        .wr_entrylo1  (wr_entrylo1),
        .rd_index     (wr_index),
        .rd_vpn2      (rd_vpn2),
        .rd_asid      (rd_asid),
        .rd_mask      (rd_mask),
        .rd_entrylo0  (rd_entrylo0),
        .rd_entrylo1  (rd_entrylo1),
        .probe_vpn2   (wr_vpn2),
        .probe_asid   (wr_asid),
        .probe_hit    (probe_hit),
        .probe_index  (probe_index),
        .lookup0_va   (mmu_tlb_va),
        .lookup0_asid (mmu_tlb_asid),
        .lookup0_hit  (tlb_hit),
        .lookup0_v    (tlb_v),
        .lookup0_d    (tlb_d),
        .lookup0_c    (tlb_c),
        .lookup0_pfn  (tlb_pfn),
        .lookup1_va   (mmu_tlb_va),
        .lookup1_asid (mmu_tlb_asid),
        .lookup1_hit  (),
        .lookup1_v    (),
        .lookup1_d    (),
        .lookup1_c    (),
        .lookup1_pfn  ()
    );

    mips_mmu dut_mmu (
        .req_valid       (req_valid),
        .req_va          (req_va),
        .req_is_store    (req_is_store),
        .req_is_fetch    (req_is_fetch),
        .asid            (asid),
        .config_k0       (config_k0),
        .is_kernel       (is_kernel),
        .tlb_lookup_va   (mmu_tlb_va),
        .tlb_lookup_asid (mmu_tlb_asid),
        .tlb_lookup_hit  (tlb_hit),
        .tlb_lookup_v    (tlb_v),
        .tlb_lookup_d    (tlb_d),
        .tlb_lookup_c    (tlb_c),
        .tlb_lookup_pfn  (tlb_pfn),
        .pa              (pa),
        .cache_attr      (cache_attr),
        .translation_ok  (translation_ok),
        .fault_type      (fault_type)
    );

    initial begin
        #2;
        rst_n = 1'b1;

        // Same VPN, non-global entry: only ASID 0x11 may use it.
        write_entry(2'd0, 19'h01234, 8'h11,
                    make_lo(20'h12345, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h12346, 3'b011, 1'b1, 1'b1, 1'b0));

        req_valid = 1'b1;
        req_va    = {19'h01234, 13'h034};
        asid      = 8'h11;
        #1;
        check("ASID match translates even page", translation_ok && tlb_hit &&
              pa == {20'h12345, 12'h034} && cache_attr == 3'b011);

        req_va = {19'h01234, 13'h100A};
        #1;
        check("ASID match selects odd page", translation_ok && tlb_hit &&
              pa == {20'h12346, 12'h00A});

        asid = 8'h22;
        req_va = {19'h01234, 13'h034};
        #1;
        check("ASID mismatch causes refill classification", !tlb_hit &&
              !translation_ok && fault_type == 3'b001);

        // Global entry: ASID is ignored, but both halves must carry G=1.
        write_entry(2'd1, 19'h01235, 8'h33,
                    make_lo(20'h2A000, 3'b010, 1'b1, 1'b1, 1'b1),
                    make_lo(20'h2A001, 3'b010, 1'b1, 1'b1, 1'b1));
        asid   = 8'h44;
        req_va = {19'h01235, 13'h080};
        #1;
        check("Global entry crosses ASID", tlb_hit && translation_ok &&
              pa == {20'h2A000, 12'h080} && cache_attr == 3'b010);

        // Matching entry with V=0 is an invalid fault, not a refill miss.
        write_entry(2'd2, 19'h01236, 8'h55,
                    make_lo(20'h30000, 3'b011, 1'b1, 1'b0, 1'b0),
                    make_lo(20'h30001, 3'b011, 1'b1, 1'b0, 1'b0));
        asid    = 8'h55;
        req_va  = {19'h01236, 13'h010};
        req_is_store = 1'b0;
        #1;
        check("Matching invalid load is TLBL", tlb_hit && !tlb_v &&
              !translation_ok && fault_type == 3'b001);
        req_is_store = 1'b1;
        #1;
        check("Matching invalid store is TLBS", tlb_hit && !tlb_v &&
              !translation_ok && fault_type == 3'b010);

        // Valid, clean page: loads work, stores raise Modified.
        write_entry(2'd3, 19'h01237, 8'h66,
                    make_lo(20'h31000, 3'b011, 1'b0, 1'b1, 1'b0),
                    make_lo(20'h31001, 3'b011, 1'b0, 1'b1, 1'b0));
        asid        = 8'h66;
        req_va      = {19'h01237, 13'h020};
        req_is_store = 1'b0;
        #1;
        check("Valid clean page accepts load", tlb_hit && tlb_v &&
              translation_ok && pa == {20'h31000, 12'h020});
        req_is_store = 1'b1;
        #1;
        check("Clean page store is Modified", tlb_hit && tlb_v && !tlb_d &&
              !translation_ok && fault_type == 3'b011);

        req_valid = 1'b0;
        #1;
        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS tlb_asid_policy");
        else
            $display("REGRESSION_TEST_FAILED tlb_asid_policy errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("REGRESSION_TEST_FAILED tlb_asid_policy timeout");
        $finish;
    end
endmodule
