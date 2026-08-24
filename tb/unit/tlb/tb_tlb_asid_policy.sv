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
    wire                 probe_multi_hit;

    wire [31:0] mmu_tlb_va;
    wire [7:0]  mmu_tlb_asid;
    wire        tlb_hit;
    wire        tlb_v;
    wire        tlb_d;
    wire [2:0]  tlb_c;
    wire [19:0] tlb_pfn;
    wire        tlb_multi_hit;

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
            write_entry_mask(index, vpn2, entry_asid, 16'b0, lo0, lo1);
        end
    endtask

    task automatic write_entry_mask;
        input [1:0]  index;
        input [18:0] vpn2;
        input [7:0]  entry_asid;
        input [15:0] entry_mask;
        input [31:0] lo0;
        input [31:0] lo1;
        begin
            @(negedge clk);
            wr_index    = index;
            wr_vpn2     = vpn2;
            wr_asid     = entry_asid;
            wr_mask     = entry_mask;
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
        .probe_multi_hit (probe_multi_hit),
        .lookup0_va   (mmu_tlb_va),
        .lookup0_asid (mmu_tlb_asid),
        .lookup0_hit  (tlb_hit),
        .lookup0_v    (tlb_v),
        .lookup0_d    (tlb_d),
        .lookup0_c    (tlb_c),
        .lookup0_pfn  (tlb_pfn),
        .lookup0_multi_hit (tlb_multi_hit),
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
        .tlb_lookup_multi_hit (tlb_multi_hit),
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

        // ASID rollover contract: reusing an index for a new context must
        // invalidate the old ASID mapping before the replacement is visible.
        write_entry(2'd0, 19'h01234, 8'hFE,
                    make_lo(20'h40000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h40001, 3'b011, 1'b1, 1'b1, 1'b0));
        req_is_store = 1'b0;
        asid         = 8'hFE;
        req_va       = {19'h01234, 13'h004};
        #1;
        check("Rollover old ASID mapping is initially valid", tlb_hit &&
              translation_ok && pa == {20'h40000, 12'h004});

        asid = 8'hFF;
        #1;
        check("Rollover new ASID misses before replacement", !tlb_hit &&
              !translation_ok && fault_type == 3'b001);

        write_entry(2'd0, 19'h01234, 8'hFF,
                    make_lo(20'h41000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h41001, 3'b011, 1'b1, 1'b1, 1'b0));
        #1;
        check("Rollover replacement selects new PFN", tlb_hit &&
              translation_ok && pa == {20'h41000, 12'h004});

        asid = 8'hFE;
        #1;
        check("Rollover old ASID stays isolated", !tlb_hit &&
              !translation_ok && fault_type == 3'b001);

        // PageMask-aware even/odd selection: a 16 KiB page pair uses VA[14]
        // as the half selector. VA[12] must remain part of the page offset.
        write_entry_mask(2'd3, 19'h02200, 8'h77, 16'h0003,
                         make_lo(20'h52000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h52004, 3'b011, 1'b1, 1'b1, 1'b0));
        asid = 8'h77;
        req_va = {19'h02200, 13'h0004}; // VA[14]=0, VA[12]=0
        #1;
        check("16KiB page selects even half", tlb_hit && translation_ok &&
              pa == {20'h52000, 12'h0004});
        req_va = {19'h02200, 13'h1004}; // VA[12]=1, VA[14]=0
        #1;
        check("16KiB offset bit does not change half", tlb_hit && translation_ok &&
              pa == {20'h52001, 12'h1004});
        req_va = {19'h02202, 13'h0004}; // VA[14]=1; masked VPN2 bit changes
        #1;
        check("16KiB page selects odd half", tlb_hit && translation_ok &&
              pa == {20'h52004, 12'h0004});

        req_va = {19'h02202, 13'h1004}; // odd half with VA[12]=1
        #1;
        check("16KiB physical offset preserves VA[13:12]", tlb_hit &&
              translation_ok && pa == {20'h52005, 12'h1004});

        // 64 KiB pair: VA[16] selects the half and VA[15:12] remains offset.
        write_entry_mask(2'd2, 19'h04000, 8'h99, 16'h000f,
                         make_lo(20'h53000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h53010, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h99;
        req_va = {19'h04000, 13'h1004};
        #1;
        check("64KiB even half preserves offset", tlb_hit && translation_ok &&
              pa == {20'h53001, 12'h1004});
        req_va = {19'h04009, 13'h1004}; // VA[16]=1, VA[15:12]=3
        #1;
        check("64KiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h53013, 12'h3004});

        // 1 MiB pair: VA[20] selects the half and VA[19:12] is preserved.
        write_entry_mask(2'd2, 19'h05000, 8'h9a, 16'h00ff,
                         make_lo(20'h54000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h55000, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h9a;
        req_va = {19'h05000, 13'h1004};
        #1;
        check("1MiB even half preserves offset", tlb_hit && translation_ok &&
              pa == {20'h54001, 12'h1004});
        req_va = {19'h05081, 13'h1004}; // VA[20]=1, VA[19:12]=0x3
        #1;
        check("1MiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h55003, 12'h3004});

        // 256 KiB pair: VA[18] selects the half; VA[17:12] is offset.
        write_entry_mask(2'd2, 19'h06000, 8'h9b, 16'h003f,
                         make_lo(20'h56000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h56100, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h9b;
        req_va = {19'h06000, 13'h1004};
        #1;
        check("256KiB even half", tlb_hit && translation_ok &&
              pa == {20'h56001, 12'h1004});
        req_va = {19'h0603f, 13'h1004}; // VA[18]=1, VA[17:12]=0x3f
        #1;
        check("256KiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h5613f, 12'h1004});

        // 4 MiB pair: VA[22] selects the half; VA[21:12] is offset.
        write_entry_mask(2'd2, 19'h07000, 8'h9c, 16'h03ff,
                         make_lo(20'h57000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h58000, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h9c;
        req_va = {19'h07000, 13'h1004};
        #1;
        check("4MiB even half", tlb_hit && translation_ok &&
              pa == {20'h57001, 12'h1004});
        req_va = {19'h073ff, 13'h1004}; // VA[22]=1, VA[21:12]=0x3ff
        #1;
        check("4MiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h583ff, 12'h1004});

        // 16 MiB pair: VA[24] selects the half; VA[23:12] is offset.
        write_entry_mask(2'd2, 19'h08000, 8'h9d, 16'h0fff,
                         make_lo(20'h59000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h5a000, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h9d;
        req_va = {19'h08000, 13'h1004};
        #1;
        check("16MiB even half", tlb_hit && translation_ok &&
              pa == {20'h59001, 12'h1004});
        req_va = {19'h08fff, 13'h1004}; // VA[24]=1, VA[23:12]=0xfff
        #1;
        check("16MiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h5afff, 12'h1004});

        // 64 MiB pair: VA[26] selects the half; VA[25:12] is offset.
        write_entry_mask(2'd2, 19'h08000, 8'h9d, 16'h3fff,
                         make_lo(20'h5c000, 3'b011, 1'b1, 1'b1, 1'b0),
                         make_lo(20'h60000, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h9d;
        req_va = {19'h08000, 13'h1004};
        #1;
        check("64MiB even half", tlb_hit && translation_ok &&
              pa == {20'h5c001, 12'h1004});
        req_va = {19'h0bfff, 13'h1004}; // VA[26]=1, VA[25:12]=0x3fff
        #1;
        check("64MiB odd half and offset", tlb_hit && translation_ok &&
              pa == {20'h63fff, 12'h1004});

        // Repeated identical TLBWR entries are idempotent copies (as can be
        // produced by a refill retry); they must not cause a false MCheck.
        write_entry(2'd0, 19'h02000, 8'h77,
                    make_lo(20'h52000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h52002, 3'b011, 1'b1, 1'b1, 1'b0));
        write_entry(2'd1, 19'h02000, 8'h77,
                    make_lo(20'h52000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h52002, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h77;
        req_va = {19'h02000, 13'h0040};
        #1;
        check("Identical duplicate entries remain idempotent", tlb_hit &&
              translation_ok && !tlb_multi_hit && pa == {20'h52000, 12'h040});

        // Overlapping valid entries are architecturally fatal (MCheck), not a
        // normal priority-encoded hit.
        write_entry(2'd0, 19'h03000, 8'h88,
                    make_lo(20'h60000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h60002, 3'b011, 1'b1, 1'b1, 1'b0));
        write_entry(2'd1, 19'h03000, 8'h88,
                    make_lo(20'h61000, 3'b011, 1'b1, 1'b1, 1'b0),
                    make_lo(20'h61002, 3'b011, 1'b1, 1'b1, 1'b0));
        asid   = 8'h88;
        req_va = {19'h03000, 13'h0020};
        #1;
        check("Overlapping TLB entries raise MCheck", tlb_multi_hit &&
              !translation_ok && fault_type == 3'b110);
        check("TLBP reports overlapping entries", probe_multi_hit && probe_hit);

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
