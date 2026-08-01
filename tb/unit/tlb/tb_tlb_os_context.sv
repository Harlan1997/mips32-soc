// Software-managed TLB page-table/context-switch contract.
// This is deliberately a focused hardware boundary gate: the page-table walk
// is modeled by the testbench, while mips_tlb/mips_mmu perform the real lookup
// and translation. It does not claim Linux or a hardware page-table walker.
`timescale 1ns/1ps

module tb_tlb_os_context;
    localparam integer TLB_ENTRIES = 8;
    localparam integer INDEX_BITS  = 3;
    localparam integer VPN_A       = 19'h00120;
    localparam integer VPN_B       = 19'h00121;

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

    // Two-level software page-table fixture: each ASID has two VPN pairs.
    reg [19:0] pte_even [0:1023];
    reg [19:0] pte_odd  [0:1023];
    reg        pte_v    [0:1023];
    reg        pte_d    [0:1023];
    reg        pte_g    [0:1023];
    integer    pte_slot;
    integer    i;
    integer    errors = 0;
    reg [2:0]  replacement_index = 3'd1;

    function integer slot_for;
        input [7:0] ctx;
        input [18:0] vpn2;
        begin
            slot_for = (ctx * 4) + vpn2[1:0];
        end
    endfunction

    function [31:0] make_lo;
        input [19:0] pfn;
        input        dirty;
        input        valid;
        input        global;
        begin
            make_lo = {6'b0, pfn, 3'b011, dirty, valid, global};
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

    task automatic write_tlb;
        input [2:0]  index;
        input [18:0] vpn2;
        input [7:0]  entry_asid;
        input [31:0] lo0;
        input [31:0] lo1;
        begin
            @(negedge clk);
            wr_index    = index;
            wr_vpn2     = vpn2;
            wr_asid     = entry_asid;
            wr_mask     = 16'b0;
            wr_entrylo0 = lo0;
            wr_entrylo1 = lo1;
            wr_en       = 1'b1;
            @(posedge clk);
            #1;
            wr_en       = 1'b0;
        end
    endtask

    task automatic flush_dynamic;
        integer fi;
        begin
            // A software ASID allocator must invalidate all non-wired slots
            // before reusing an ASID. Keep slot 0 (wired/global) intact.
            for (fi = 1; fi < TLB_ENTRIES; fi = fi + 1)
                write_tlb(fi[2:0], 19'd0, 8'd0,
                          make_lo(20'd0, 1'b0, 1'b0, 1'b0),
                          make_lo(20'd0, 1'b0, 1'b0, 1'b0));
            replacement_index = 3'd1;
        end
    endtask

    task automatic page_walk_fill;
        input [7:0]  walk_asid;
        input [18:0] walk_vpn2;
        integer walk_slot;
        begin
            walk_slot = slot_for(walk_asid, walk_vpn2);
            check("page-table walk finds valid PTE", pte_v[walk_slot]);
            write_tlb(replacement_index, walk_vpn2, walk_asid,
                      make_lo(pte_even[walk_slot], pte_d[walk_slot],
                              pte_v[walk_slot], pte_g[walk_slot]),
                      make_lo(pte_odd[walk_slot], pte_d[walk_slot],
                              pte_v[walk_slot], pte_g[walk_slot]));
            if (replacement_index == TLB_ENTRIES-1)
                replacement_index = 3'd1;
            else
                replacement_index = replacement_index + 3'd1;
        end
    endtask

    task automatic access_page;
        input [7:0]  access_asid;
        input [18:0] access_vpn2;
        input [12:0] page_offset;
        input [31:0] expected_pa;
        begin
            asid      = access_asid;
            req_va    = {access_vpn2, page_offset};
            req_valid = 1'b1;
            req_is_store = 1'b0;
            #1;
            if (!translation_ok)
                page_walk_fill(access_asid, access_vpn2);
            #1;
            check("context access translates after walk", translation_ok &&
                  tlb_hit && tlb_v && pa == expected_pa);
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
        .rd_vpn2      (),
        .rd_asid      (),
        .rd_mask      (),
        .rd_entrylo0  (),
        .rd_entrylo1  (),
        .probe_vpn2   (wr_vpn2),
        .probe_asid   (wr_asid),
        .probe_hit    (),
        .probe_index  (),
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
        rst_n = 1'b0;
        for (i = 0; i < 1024; i = i + 1) begin
            pte_even[i] = 20'd0;
            pte_odd[i]  = 20'd0;
            pte_v[i]    = 1'b0;
            pte_d[i]    = 1'b0;
            pte_g[i]    = 1'b0;
        end
        #2;
        rst_n = 1'b1;

        // Wired kernel mapping: it must survive every process switch and
        // every ASID rollover flush.
        write_tlb(3'd0, 19'h00010, 8'h00,
                  make_lo(20'h00080, 1'b1, 1'b1, 1'b1),
                  make_lo(20'h00081, 1'b1, 1'b1, 1'b1));

        pte_slot = slot_for(8'h01, VPN_A);
        pte_even[pte_slot] = 20'h10101;
        pte_odd[pte_slot]  = 20'h10102;
        pte_v[pte_slot]    = 1'b1;
        pte_d[pte_slot]    = 1'b1;

        pte_slot = slot_for(8'h02, VPN_A);
        pte_even[pte_slot] = 20'h20201;
        pte_odd[pte_slot]  = 20'h20202;
        pte_v[pte_slot]    = 1'b1;
        pte_d[pte_slot]    = 1'b1;

        pte_slot = slot_for(8'h01, VPN_B);
        pte_even[pte_slot] = 20'h30301;
        pte_odd[pte_slot]  = 20'h30302;
        pte_v[pte_slot]    = 1'b1;
        pte_d[pte_slot]    = 1'b1;

        // First process gets a page-table miss, fills an entry, and exercises
        // both halves of one VPN pair.
        access_page(8'h01, VPN_A, 13'h024, {20'h10101, 12'h024});
        access_page(8'h01, VPN_A, 13'h1020, {20'h10102, 12'h020});

        // Context switch to a second process with the same VA must select a
        // different PTE/PFN, never process 1's cached TLB entry.
        access_page(8'h02, VPN_A, 13'h024, {20'h20201, 12'h024});
        check("ASID context switch preserves process 1 mapping", tlb_hit &&
              translation_ok && pa == {20'h20201, 12'h024});
        asid = 8'h01;
        req_va = {VPN_A, 13'h024};
        #1;
        check("switch back restores process 1 mapping", tlb_hit &&
              translation_ok && pa == {20'h10101, 12'h024});

        // A second page for process 1 proves the walk uses the VPN key, not
        // only the current ASID.
        access_page(8'h01, VPN_B, 13'h088, {20'h30301, 12'h088});

        // Exhaust the software ASID namespace, then rollover. The flush must
        // remove process 255's mapping while retaining the wired global slot.
        for (i = 3; i < 256; i = i + 1) begin
            pte_slot = slot_for(i[7:0], VPN_A);
            pte_even[pte_slot] = 20'h40000 + i;
            pte_odd[pte_slot]  = 20'h41000 + i;
            pte_v[pte_slot]    = 1'b1;
            pte_d[pte_slot]    = 1'b1;
            access_page(i[7:0], VPN_A, 13'h010, {20'h40000 + i, 12'h010});
        end

        // ASID 0xff is the last allocated context; wrap to 1 and flush.
        asid = 8'hFF;
        req_va = {VPN_A, 13'h010};
        #1;
        check("last ASID mapping is resident before rollover", tlb_hit &&
              translation_ok && pa == {20'h40000 + 255, 12'h010});
        flush_dynamic();
        asid = 8'h01;
        req_va = {VPN_A, 13'h010};
        #1;
        // On a miss the lookup data payload is don't-care; the hit bit is the
        // architectural evidence that no stale non-wired mapping survived.
        check("rollover flush removes stale non-wired mapping", !translation_ok &&
              !tlb_hit && fault_type == 3'b001);
        // The wired global entry remains reachable by a different ASID.
        asid = 8'hA5;
        req_va = {19'h00010, 13'h014};
        #1;
        check("rollover preserves wired global mapping", tlb_hit && tlb_v &&
              translation_ok && pa == {20'h00080, 12'h014});
        access_page(8'h01, VPN_A, 13'h010, {20'h10101, 12'h010});

        req_valid = 1'b0;
        if (errors == 0)
            $display("REGRESSION_TEST_SUCCESS tlb_os_context");
        else
            $display("REGRESSION_TEST_FAILED tlb_os_context errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("REGRESSION_TEST_FAILED tlb_os_context timeout");
        $finish;
    end
endmodule
