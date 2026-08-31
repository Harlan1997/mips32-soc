// =============================================================================
// File Name : tb_cp0_timer.sv
// Module    : tb_cp0_timer
// Purpose   : Block-level sanity test for Phase B.2 CP0 timer (Count/Compare/
//             Cause.TI/DC + IntCtl.IPTI routing). Not a full UVM env; intended
//             as a fast pre-commit sanity check for future CP0 timer changes.
//             See docs/block_specs/cp0_spec.md §9 for register semantics.
// Standard  : SystemVerilog-2012 (task/module only, synthesizable subset avoided)
// Run       : ./run.sh (in this directory)
// =============================================================================

`timescale 1ns/1ps

module tb_cp0_timer;
    reg         clk = 0;
    reg         rst_n = 0;
    reg  [5:0]  hw_int = 0;
    reg         we = 0;
    reg  [4:0]  waddr = 0;
    reg  [2:0]  wsel  = 0;
    reg  [31:0] wdata = 0;
    reg  [4:0]  raddr = 0;
    reg  [2:0]  rsel  = 0;
    wire [31:0] rdata;
    reg  [2:0]  tlb_op = 3'b000;
    reg         except_req = 0;
    reg  [4:0]  except_code = 0;
    reg  [1:0]  except_ce = 0;
    reg  [31:0] except_pc = 0;
    reg         except_bd = 0;
    reg         eret = 0;
    reg         di = 0;
    reg         ei = 0;
    reg  [31:0] bad_vaddr = 0;
    reg  [31:0] lladdr_in = 0;

    // Phase B.4 CP0 privilege exports (unused checks in this timer/TLB tb but
    // required for `.*` wildcard connectivity).
    wire        kernel_mode;
    wire        cu0_enable;
    wire        cu1_enable;
    wire        exl_out;
    wire [31:0]  hwrena_out;
    wire [3:0]   srs_current_set_out;
    wire [3:0]   srs_previous_set_out;

    // Phase B.3.c MMU pass-through signals (unused inside this timer/TLB tb but
    // required for `.*` wildcard connectivity to mips_cp0's post-B.3.c ports).
    wire [7:0]  cp0_asid_out;
    wire [31:0] cp0_ptebase_out;
    wire [2:0]  cp0_config_k0_out;
    reg  [31:0] mmu_ilookup_va = 0;
    wire        mmu_ilookup_hit;
    wire        mmu_ilookup_multi_hit;
    wire        mmu_ilookup_v;
    wire        mmu_ilookup_d;
    wire [2:0]  mmu_ilookup_c;
    wire [19:0] mmu_ilookup_pfn;
    reg  [31:0] mmu_dlookup_va = 0;
    wire        mmu_dlookup_hit;
    wire        mmu_dlookup_multi_hit;
    wire        mmu_dlookup_v;
    wire        mmu_dlookup_d;
    wire [2:0]  mmu_dlookup_c;
    wire [19:0] mmu_dlookup_pfn;
    wire [31:0] epc_out;
    wire [31:0] ebase_out;
    wire        bev_out;
    wire        intr_req;
    wire        vint_enabled_out;
    wire [31:0] vint_offset_out;
    wire [3:0]   vint_srs_set_out;
    wire [31:0] taglo_out;
    wire [31:0] taghi_out;
    reg         tlb_inv_en = 1'b0;
    reg  [18:0] tlb_inv_vpn2 = 19'd0;
    reg  [7:0]  tlb_inv_asid = 8'd0;
    reg  [1:0]  tlb_inv_scope = 2'd0;
    reg  [5:0]  tlb_inv_wired_floor = 6'd0;
    reg         cache_op_done = 1'b0;
    reg  [4:0]  cache_op = 5'd0;
    reg  [31:0] cache_tag_rdata = 32'd0;
    reg         ctx_save_req = 1'b0;
    wire        ctx_save_done;
    wire [31:0] ctx_save_status;
    wire [7:0]  ctx_save_asid;
    wire [31:0] ctx_save_srsctl;
    reg         ctx_restore_req = 1'b0;
    reg  [31:0] ctx_restore_status = 32'd0;
    reg  [7:0]  ctx_restore_asid = 8'd0;
    reg  [31:0] ctx_restore_srsctl = 32'd0;
    wire        ctx_restore_done;
    reg  [3:0]  interrupt_srs_set = 4'd0;
    reg         interrupt_accept_in = 1'b0;
    reg         hw_tlb_wr_en = 1'b0;
    reg  [5:0]  hw_tlb_wr_index = 6'd0;
    reg  [18:0] hw_tlb_wr_vpn2 = 19'd0;
    reg  [7:0]  hw_tlb_wr_asid = 8'd0;
    reg  [15:0] hw_tlb_wr_mask = 16'd0;
    reg  [31:0] hw_tlb_wr_entrylo0 = 32'd0;
    reg  [31:0] hw_tlb_wr_entrylo1 = 32'd0;
    wire        hw_tlb_wr_ready;

    integer errors = 0;

    mips_cp0 dut (.*);

    always #5 clk = ~clk;

    task automatic mtc0(input [4:0] a, input [2:0] s, input [31:0] d);
        begin
            @(posedge clk);
            we <= 1; waddr <= a; wsel <= s; wdata <= d;
            @(posedge clk);
            we <= 0;
        end
    endtask

    task automatic mfc0(input [4:0] a, input [2:0] s, output [31:0] d);
        begin
            @(negedge clk);
            raddr = a; rsel = s;
            @(negedge clk);
            d = rdata;
        end
    endtask

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

    reg [31:0] rd;
    initial begin
        // Reset window
        #12 rst_n = 1;
        @(posedge clk);

        // 1) Count starts small (< 10) after reset release + a few sampling
        // cycles. Spec says reset = 0; we allow a small window because the
        // test bench inserts a couple of cycles for sync/access before sampling.
        mfc0(5'd9, 3'd0, rd);
        check("Count small (<10) shortly after reset", rd < 32'd10);

        // 2) Count advances at COUNT_DIV rate (=2 cpu cycles per tick)
        begin : rate_check
            reg [31:0] c1; reg [31:0] c2;
            mfc0(5'd9, 3'd0, c1);
            repeat (20) @(posedge clk);
            mfc0(5'd9, 3'd0, c2);
            check("Count increments ~10 in 20 cpu cycles", (c2 - c1) inside {[9:11]});
        end

        // 3) Compare reset value = all-1s → no boot-time TI
        mfc0(5'd11, 3'd0, rd);
        check("Compare reset = 0xFFFFFFFF", rd == 32'hFFFF_FFFF);
        mfc0(5'd13, 3'd0, rd);
        check("Cause.TI=0 at boot", rd[30] == 1'b0);

        // 4) Set Compare = Count + 20 → wait → TI latches on match
        mfc0(5'd9, 3'd0, rd);
        mtc0(5'd11, 3'd0, rd + 32'd20);
        repeat (80) @(posedge clk);
        mfc0(5'd13, 3'd0, rd);
        check("Cause.TI=1 after Count reaches Compare", rd[30] == 1'b1);

        // 5) IPTI default 7 → TI routes to Cause.IP7 (bit 15)
        check("Cause.IP7 asserted from timer (IPTI=7)", rd[15] == 1'b1);

        // 6) Writing Compare clears TI latch
        mtc0(5'd11, 3'd0, 32'hFFFF_FFFF);
        @(posedge clk);
        mfc0(5'd13, 3'd0, rd);
        check("Cause.TI=0 after writing Compare", rd[30] == 1'b0);

        // 7) Cause.DC=1 pauses Count
        mtc0(5'd13, 3'd0, 32'h0800_0000); // DC bit 27
        begin : dc_check
            reg [31:0] c1; reg [31:0] c2;
            mfc0(5'd9, 3'd0, c1);
            repeat (20) @(posedge clk);
            mfc0(5'd9, 3'd0, c2);
            check("Count paused with DC=1", c1 == c2);
        end

        // 8) Change IPTI to 2 → TI routes to Cause.IP2 (bit 10)
        mtc0(5'd13, 3'd0, 32'h0000_0000); // clear DC
        mtc0(5'd12, 3'd1, 32'h4000_0000); // IntCtl.IPTI = 3'b010 (2)
        mtc0(5'd9,  3'd0, 32'd0);          // reset Count
        mtc0(5'd11, 3'd0, 32'd10);         // Compare = 10
        repeat (40) @(posedge clk);
        mfc0(5'd13, 3'd0, rd);
        check("With IPTI=2, TI routes to Cause.IP2", rd[10] == 1'b1);
        check("With IPTI=2, Cause.IP7 not driven by timer", rd[15] == 1'b0);

        // 9) External hw_int and timer OR into same IP field when overlapping.
        hw_int = 6'b100000; // hw_int[5] → Cause.IP7
        mtc0(5'd12, 3'd1, 32'hE000_0000); // IPTI back to 7
        mtc0(5'd11, 3'd0, 32'd0);          // Compare = 0 (TI still cleared)
        mtc0(5'd11, 3'd0, 32'h0000_0020);  // Compare = 32
        repeat (80) @(posedge clk);
        mfc0(5'd13, 3'd0, rd);
        check("hw_int[5] OR timer TI both drive Cause.IP7",
              rd[15] == 1'b1 && rd[30] == 1'b1);
        hw_int = 6'b000000;

        // 10) Vectored interrupt exports use the highest enabled pending IP.
        // VEIC is not implemented, so CPU vector selection is IP-based.
        mtc0(5'd11, 3'd0, 32'hFFFF_FFFF); // Clear the timer contribution.
        mtc0(5'd13, 3'd0, 32'h0080_0000); // Cause.IV = 1
        mtc0(5'd12, 3'd1, 32'h0000_0020); // IntCtl.VS = 1 -> 32-byte spacing
        mtc0(5'd12, 3'd0, 32'h0000_A001); // IE, IM7 and IM5
        hw_int = 6'b101000;                // hw[5]->IP7, hw[3]->IP5
        @(posedge clk);
        mfc0(5'd13, 3'd0, rd);
        check("Cause.IV write/readback", rd[23] == 1'b1);
        mfc0(5'd12, 3'd1, rd);
        check("IntCtl.VS write/readback", rd[9:5] == 5'd1);
        check("interrupt request asserts for enabled pending IPs", intr_req == 1'b1);
        check("vector enable follows Cause.IV", vint_enabled_out == 1'b1);
        check("IP7 wins and VS=1 yields offset 0x2E0", vint_offset_out == 32'h0000_02E0);
        mtc0(5'd12, 3'd1, 32'h0000_03E0); // VS = 31, maximum spacing
        @(negedge clk);
        check("IP7 with VS=31 yields full-width offset 0x1D20",
              vint_offset_out == 32'h0000_1D20);
        hw_int = 6'b000000;

        // -----------------------------------------------------------------
        // Phase B.3.a MMU register sanity: read reset values, write/readback,
        // Random downcounter, Wired reset side-effect.
        // -----------------------------------------------------------------
        mfc0(5'd0,  3'd0, rd); check("Index reset = 0",           rd == 32'd0);
        mfc0(5'd6,  3'd0, rd); check("Wired reset = 0",           rd == 32'd0);
        mfc0(5'd2,  3'd0, rd); check("EntryLo0 reset = 0",        rd == 32'd0);
        mfc0(5'd3,  3'd0, rd); check("EntryLo1 reset = 0",        rd == 32'd0);
        mfc0(5'd10, 3'd0, rd); check("EntryHi reset = 0",         rd == 32'd0);
        mfc0(5'd5,  3'd0, rd); check("PageMask reset = 0",        rd == 32'd0);
        mfc0(5'd4,  3'd0, rd); check("Context reset = 0",         rd == 32'd0);
        mfc0(5'd8,  3'd0, rd); check("BadVAddr reset = 0",        rd == 32'd0);

        // Random is a running downcounter starting at TLB_INDEX_MAX (63)
        mfc0(5'd1, 3'd0, rd);  check("Random <= 63",              rd[5:0] <= 6'd63);
        // After many cycles it wraps back to 63 whenever it hits Wired (=0)
        repeat (200) @(posedge clk);
        mfc0(5'd1, 3'd0, rd);  check("Random still in [0,63]",    rd[5:0] <= 6'd63);

        // Write/readback Index, EntryLo0/1, EntryHi, PageMask
        mtc0(5'd0,  3'd0, 32'h8000_0003);            // P=1, index=3
        mfc0(5'd0,  3'd0, rd); check("Index P=1 index=3",         rd == {1'b1, 25'b0, 6'd3});
        mtc0(5'd2,  3'd0, 32'hDEAD_BEEF);
        mfc0(5'd2,  3'd0, rd); check("EntryLo0 writeback",        rd == 32'hDEAD_BEEF);
        mtc0(5'd3,  3'd0, 32'hCAFE_F00D);
        mfc0(5'd3,  3'd0, rd); check("EntryLo1 writeback",        rd == 32'hCAFE_F00D);
        mtc0(5'd10, 3'd0, 32'hABCD_00FF);            // VPN2=0xABCD_0, ASID=0xFF
        mfc0(5'd10, 3'd0, rd); check("EntryHi VPN2+ASID readback",
                                     rd == {19'h55E68, 5'b0, 8'hFF});
        mtc0(5'd5,  3'd0, 32'h001F_E000);            // Mask[28:13]=0x00FF (16KB)
        mfc0(5'd5,  3'd0, rd); check("PageMask Mask readback",    rd == 32'h001F_E000);

        // Wired write → Random resets to TLB_INDEX_MAX; the following read
        // happens a handful of cycles later so Random will have decremented
        // some. The critical invariant is that it stayed high (well above the
        // new lower bound), not that it's exactly max.
        mtc0(5'd6,  3'd0, 32'd8);
        mfc0(5'd1,  3'd0, rd); check("Random near top after Wired write",
                                     rd[5:0] >= 6'd50);
        // Wired lower bound now 8 → Random must not go below 8 long term
        repeat (300) @(posedge clk);
        mfc0(5'd1,  3'd0, rd); check("Random floor >= Wired(8)", rd[5:0] >= 6'd8);

        // Context PTEBase write, BadVPN2 stays 0 (HW update deferred to B.3.d)
        mtc0(5'd4,  3'd0, 32'hFF80_0000);            // PTEBase = 0x1FF
        mfc0(5'd4,  3'd0, rd); check("Context PTEBase readback",
                                     rd == {9'h1FF, 23'b0});
        check("Context PTEBase drives walker root",
              cp0_ptebase_out == 32'hFF80_0000);

        // -----------------------------------------------------------------
        // Phase B.3.b TLB instruction round-trip
        //  1) Load EntryHi/Lo0/Lo1/PageMask/Index → TLBWI → clear working set
        //     → TLBR → readback must equal original values.
        //  2) TLBP with matching EntryHi should return the written index.
        //  3) TLBP with mismatched EntryHi should set Index.P=1.
        // -----------------------------------------------------------------
        // 1) Write TLB[5] with a 4KB entry
        mtc0(5'd10, 3'd0, 32'h0002_A007);            // VPN2=0x00015, ASID=0x07
        mtc0(5'd2,  3'd0, 32'h0000_0007);            // Lo0: PFN=0, C=001, D=0, V=1, G=1
        mtc0(5'd3,  3'd0, 32'h0000_0107);            // Lo1: PFN=1, C=001, D=0, V=1, G=1
        mtc0(5'd5,  3'd0, 32'h0000_0000);            // PageMask = 0 (4KB)
        mtc0(5'd0,  3'd0, 32'h0000_0005);            // Index = 5, P=0
        // TLBWI: opcode 010000 rs=10000 func=000010 → 0x42000002
        @(posedge clk);
        tlb_op <= 3'b010;
        @(posedge clk);
        tlb_op <= 3'b000;
        @(posedge clk);

        // Corrupt working set so TLBR must actually pull from TLB[5]
        mtc0(5'd10, 3'd0, 32'hDEAD_BEEF);
        mtc0(5'd2,  3'd0, 32'hAAAA_5555);
        mtc0(5'd3,  3'd0, 32'h5555_AAAA);
        mtc0(5'd5,  3'd0, 32'h001F_E000);
        // Re-arm Index=5 for TLBR
        mtc0(5'd0,  3'd0, 32'h0000_0005);
        // Issue TLBR
        @(posedge clk);
        tlb_op <= 3'b001;
        @(posedge clk);
        tlb_op <= 3'b000;
        @(posedge clk);
        // Verify readback matches originally-written values
        mfc0(5'd10, 3'd0, rd); check("TLBR EntryHi readback",
                                     rd == {19'h00015, 5'b0, 8'h07});
        mfc0(5'd2,  3'd0, rd); check("TLBR EntryLo0 readback (G reconstructed)",
                                     rd == 32'h0000_0007);
        mfc0(5'd3,  3'd0, rd); check("TLBR EntryLo1 readback",
                                     rd == 32'h0000_0107);
        mfc0(5'd5,  3'd0, rd); check("TLBR PageMask readback = 0",
                                     rd == 32'd0);

        // 2) TLBP with matching EntryHi
        mtc0(5'd10, 3'd0, 32'h0002_A007);            // Same VPN2/ASID as written
        @(posedge clk);
        tlb_op <= 3'b100;
        @(posedge clk);
        tlb_op <= 3'b000;
        @(posedge clk);
        mfc0(5'd0, 3'd0, rd); check("TLBP hit returns Index=5, P=0",
                                     rd == 32'h0000_0005);

        // 3) TLBP with mismatched ASID and non-global entry
        //    First write a non-global TLB[6] with distinctive VPN2/ASID
        mtc0(5'd10, 3'd0, 32'h0004_A008);            // VPN2=0x00025, ASID=0x08
        mtc0(5'd2,  3'd0, 32'h0000_0006);            // Lo0: V=1, G=0
        mtc0(5'd3,  3'd0, 32'h0000_0106);            // Lo1: V=1, G=0
        mtc0(5'd5,  3'd0, 32'h0000_0000);
        mtc0(5'd0,  3'd0, 32'h0000_0006);
        @(posedge clk);
        tlb_op <= 3'b010;
        @(posedge clk);
        tlb_op <= 3'b000;
        @(posedge clk);
        // Now probe with SAME VPN2 but different ASID
        mtc0(5'd10, 3'd0, 32'h0004_A099);            // Same VPN2, ASID=0x99
        @(posedge clk);
        tlb_op <= 3'b100;
        @(posedge clk);
        tlb_op <= 3'b000;
        @(posedge clk);
        mfc0(5'd0, 3'd0, rd); check("TLBP miss (ASID mismatch, G=0) sets P=1",
                                     rd[31] == 1'b1);

        // -----------------------------------------------------------------
        // Phase B.3.d: BadVAddr + Context.BadVPN2 hardware update on
        // address-related exceptions (Mod=1, TLBL=2, TLBS=3, AdEL=4, AdES=5).
        // -----------------------------------------------------------------
        // Fire an AdES (5) exception with bad_vaddr = 0xCAFEBABE
        @(posedge clk);
        except_req  <= 1'b1;
        except_code <= 5'h05;
        except_pc   <= 32'h1000_0000;
        bad_vaddr   <= 32'hCAFE_BABE;
        @(posedge clk);
        except_req  <= 1'b0;
        @(posedge clk);
        mfc0(5'd8,  3'd0, rd); check("BadVAddr latched on AdES",  rd == 32'hCAFE_BABE);
        mfc0(5'd4,  3'd0, rd);
        // Context = { PTEBase (from earlier write 0x1FF), BadVPN2 = 0xCAFEBABE[31:13] = 0x65F5D, 4'b0 }
        check("Context.BadVPN2 updated on AdES", rd[22:4] == 32'hCAFE_BABE >> 13);

        // Reset EXL for next scenario
        mtc0(5'd12, 3'd0, 32'd0);

        // Fire a TLBL (2) exception with bad_vaddr = 0x00081000 → BadVPN2=0x40
        @(posedge clk);
        except_req  <= 1'b1;
        except_code <= 5'h02;
        bad_vaddr   <= 32'h0008_1000;
        @(posedge clk);
        except_req  <= 1'b0;
        @(posedge clk);
        mfc0(5'd8, 3'd0, rd); check("BadVAddr latched on TLBL", rd == 32'h0008_1000);
        mfc0(5'd4, 3'd0, rd); check("Context.BadVPN2 updated on TLBL",
                                     rd[22:4] == 32'h0008_1000 >> 13);

        // Reset EXL, then fire a NON-address exception (SYSCALL=8): BadVAddr must NOT change
        mtc0(5'd12, 3'd0, 32'd0);
        @(posedge clk);
        except_req  <= 1'b1;
        except_code <= 5'h08;
        bad_vaddr   <= 32'hDEAD_DEAD;
        @(posedge clk);
        except_req  <= 1'b0;
        @(posedge clk);
        mfc0(5'd8, 3'd0, rd);
        check("BadVAddr NOT touched by SYSCALL", rd == 32'h0008_1000);  // Prior TLBL value

        // -----------------------------------------------------------------
        // Phase B.5: BD-bit in Cause, EPC adjustment, ERL/ErrorEPC semantics.
        // -----------------------------------------------------------------
        // Clear EXL for fresh state
        mtc0(5'd12, 3'd0, 32'd0);
        // Fire exception with except_bd=1 → Cause.BD should be 1 and
        //   EPC = except_pc - 4 (branch instruction, not the delay slot).
        @(posedge clk);
        except_req  <= 1'b1;
        except_code <= 5'h0A;                  // RI (non-address, safe)
        except_pc   <= 32'h0000_1004;          // delay-slot PC (branch was at 0x1000)
        except_bd   <= 1'b1;
        @(posedge clk);
        except_req  <= 1'b0;
        except_bd   <= 1'b0;
        @(posedge clk);
        mfc0(5'd13, 3'd0, rd); check("Cause.BD=1 latched",       rd[31] == 1'b1);
        mfc0(5'd14, 3'd0, rd); check("EPC = delay-slot PC - 4",  rd == 32'h0000_1000);

        // Non-BD exception: EPC = exact fault PC
        mtc0(5'd12, 3'd0, 32'd0);              // clear EXL
        @(posedge clk);
        except_req  <= 1'b1;
        except_code <= 5'h0A;
        except_pc   <= 32'h2000_0000;
        except_bd   <= 1'b0;
        @(posedge clk);
        except_req  <= 1'b0;
        @(posedge clk);
        mfc0(5'd13, 3'd0, rd); check("Cause.BD=0 when except_bd=0",  rd[31] == 1'b0);
        mfc0(5'd14, 3'd0, rd); check("EPC = fault PC (no BD adjust)", rd == 32'h2000_0000);

        // ErrorEPC + ERL semantics: set ERL=1, write ErrorEPC, ERET must return
        //   via ErrorEPC and clear ERL (not EXL).
        mtc0(5'd12, 3'd0, 32'h0000_0004);      // Status.ERL=1
        mtc0(5'd30, 3'd0, 32'hABCD_0000);      // ErrorEPC
        mfc0(5'd12, 3'd0, rd); check("Status.ERL latches to 1",   rd[2] == 1'b1);
        mfc0(5'd30, 3'd0, rd); check("ErrorEPC readback",          rd == 32'hABCD_0000);
        // Fire ERET
        @(posedge clk);
        eret <= 1'b1;
        @(posedge clk);
        eret <= 1'b0;
        @(posedge clk);
        mfc0(5'd12, 3'd0, rd);
        check("ERET with ERL=1 clears ERL",    rd[2] == 1'b0);
        check("ERET with ERL=1 leaves EXL=0",  rd[1] == 1'b0);

        // Standard ERET path (ERL=0, EXL=1): must clear EXL
        mtc0(5'd12, 3'd0, 32'h0000_0002);      // EXL=1, ERL=0
        @(posedge clk);
        eret <= 1'b1;
        @(posedge clk);
        eret <= 1'b0;
        @(posedge clk);
        mfc0(5'd12, 3'd0, rd);
        check("ERET with EXL=1 clears EXL",    rd[1] == 1'b0);

        // -----------------------------------------------------------------
        // Phase B.4: KSU + CU0 writability, kernel_mode / cu0_enable outputs.
        // -----------------------------------------------------------------
        // Start: default reset → KSU=0, CU0=0, EXL/ERL=0 → kernel_mode=1
        mtc0(5'd12, 3'd0, 32'd0);
        @(posedge clk);
        check("Default mode: kernel_mode=1", kernel_mode == 1'b1);
        check("Default mode: cu0_enable=0",  cu0_enable  == 1'b0);

        // Write KSU=10 (user), CU0=0, EXL=0, ERL=0 → user mode
        mtc0(5'd12, 3'd0, 32'h0000_0010);   // bit 4 = 1 (KSU=10)
        @(posedge clk);
        mfc0(5'd12, 3'd0, rd);
        check("KSU=10 readback",             rd[4:3] == 2'b10);
        check("User mode: kernel_mode=0",    kernel_mode == 1'b0);

        // EXL=1 forces kernel mode regardless of KSU
        mtc0(5'd12, 3'd0, 32'h0000_0012);   // EXL=1 + KSU=10
        @(posedge clk);
        check("EXL=1 forces kernel_mode=1",  kernel_mode == 1'b1);

        // ERL=1 forces kernel mode regardless of KSU
        mtc0(5'd12, 3'd0, 32'h0000_0014);   // ERL=1 + KSU=10, EXL=0
        @(posedge clk);
        check("ERL=1 forces kernel_mode=1",  kernel_mode == 1'b1);

        // Set CU0=1 (allow user-mode CP0 access), user mode active
        mtc0(5'd12, 3'd0, 32'h1000_0010);   // CU0=1, KSU=10, EXL=ERL=0
        @(posedge clk);
        check("CU0 readback = 1",            cu0_enable  == 1'b1);
        check("User mode with CU0=1",        kernel_mode == 1'b0);

        // UserLocal (CP0 4,2) is the kernel-managed TLS pointer.  It must
        // reset to zero, retain a software-written value, and be independent
        // of the Context (4,0) BadVPN2/PTEBase state.
        mfc0(5'd4, 3'd2, rd);
        check("UserLocal reset",             rd == 32'd0);
        mtc0(5'd4, 3'd2, 32'h8123_4567);
        @(posedge clk);
        mfc0(5'd4, 3'd2, rd);
        check("UserLocal write/read",         rd == 32'h8123_4567);
        mfc0(5'd4, 3'd0, rd);
        check("Context remains independent",  rd[31:23] == 9'h1FF);
        mfc0(5'd16, 3'd3, rd);
        check("Config3 advertises UserLocal", rd[13] == 1'b1);

        // Restore kernel mode for subsequent state
        mtc0(5'd12, 3'd0, 32'd0);

        // MCheck/TLB-shutdown contract: CP0 Status.TS is hardware-sticky.
        // A software Status write may change ordinary writable bits but must
        // not clear TS once a multi-hit exception has been taken.
        except_pc = 32'h8000_0100;
        except_code = 5'h18;
        except_req = 1'b1;
        @(posedge clk);
        except_req = 1'b0;
        @(posedge clk);
        mfc0(5'd12, 3'd0, rd);
        check("MCheck sets sticky Status.TS", rd[21] == 1'b1);

        // LLAddr is read-only CP0 observability of the CPU reservation.
        lladdr_in = 32'h8123_4560;
        mfc0(5'd17, 3'd0, rd);
        check("LLAddr reports reservation address", rd == 32'h8123_4560);
`ifdef SRS_MAP_TEST
        // SRSMap is an opt-in CP0 state register. All eight IP mappings are
        // writable; the selected Cause.IP level drives the exported set.
        mfc0(5'd12, 3'd3, rd);
        check("SRSMap reset = 0", rd == 32'd0);
        mtc0(5'd12, 3'd3, 32'h8765_4321);
        mfc0(5'd12, 3'd3, rd);
        check("SRSMap keeps eight mapping nibbles", rd == 32'h8765_4321);
        hw_int = 6'b000001; // external hw_int[0] is Cause.IP2
        mtc0(5'd12, 3'd0, 32'h0000_0401); // IE + IM2
        @(posedge clk);
        check("SRSMap selects IP2 shadow set", vint_srs_set_out == 4'd3);
        interrupt_srs_set = vint_srs_set_out;
        hw_int = 6'b000000;
        mtc0(5'd12, 3'd0, 32'h0000_0001); // clear EXL and leave IE enabled
        except_code = 5'd0;
        except_pc = 32'h8000_0200;
        except_req = 1'b1;
        interrupt_accept_in = 1'b1;
        @(posedge clk);
        except_req = 1'b0;
        interrupt_accept_in = 1'b0;
        check("interrupt entry selects mapped shadow set",
              dut.cp0_srs_css == 4'd3 && dut.cp0_srs_pss == 4'd0);
        eret = 1'b1;
        @(posedge clk);
        eret = 1'b0;
        check("ERET restores pre-interrupt shadow set", dut.cp0_srs_css == 4'd0);
`endif
        mtc0(5'd12, 3'd0, 32'd0);
        mfc0(5'd12, 3'd0, rd);
        check("Status write cannot clear TS", rd[21] == 1'b1);
        rst_n = 1'b0;
        #2;
        rst_n = 1'b1;
        @(posedge clk);
        mfc0(5'd12, 3'd0, rd);
        check("Reset clears sticky Status.TS", rd[21] == 1'b0);

        // Summary
        if (errors == 0)
            $display("TB PASS (0 errors)");
        else
            $display("TB FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("TB TIMEOUT");
        $finish;
    end
endmodule
