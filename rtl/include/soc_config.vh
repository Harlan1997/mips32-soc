// =============================================================================
// File Name: soc_config.vh
// Design:    Project-wide SoC configuration contract
// =============================================================================

`ifndef SOC_CONFIG_VH
`define SOC_CONFIG_VH

// ---------------------------------------------------------------------------
// v2 cutover flags — only for pending integrations (v2 core spec-complete
// but downstream UVM/firmware coordination still open). MDU v2 and VIC are
// already the DUT baseline (v1 files deleted after signoff #12).
// ---------------------------------------------------------------------------
`define SOC_USE_L2_CACHE   1   // rtl/cache/l2_cache.v — L2 in DUT.
`define SOC_L2_CACHING     1   // Enable real caching. Default impl is write-through
                                  // (l2_cache_wt.v): 128KB 8-way, caches reads,
                                  // forwards every write to SRAM (no dirty state,
                                  // reset-safe). Define SOC_L2_WRITEBACK to select
                                  // the write-back/write-allocate impl
                                  // (l2_cache_caching.v) instead — also reset-safe
                                  // (retention arrays survive warm rst_n pulses).
`define SOC_USE_UART_16550   1   // rtl/perips/apb_uart_16550.v — v2 in DUT.
                                  // pic_mask_arbitration seq uses VIC INTR_SOFT
                                  // for the UART bit when v2 is active (stable
                                  // level source, matches v1 stub semantics).

// AXI/APB interface contract
`define SOC_AXI_ID_WIDTH      4
`define SOC_AXI_ADDR_WIDTH    32
`define SOC_AXI_DATA_WIDTH    32
`define SOC_AXI_LEN_WIDTH     8
`define SOC_APB_ADDR_WIDTH    12
`define SOC_APB_DATA_WIDTH    32

// Top-level address decode nibbles
`define SOC_ADDR_NIBBLE_SRAM       4'h0
`define SOC_ADDR_NIBBLE_FLASH      4'h1
`define SOC_ADDR_NIBBLE_APB        4'h4
`define SOC_ADDR_NIBBLE_SRAM_ALIAS 4'hA

// AXI response encodings
`define SOC_AXI_RESP_OKAY          2'b00
`define SOC_AXI_RESP_EXOKAY        2'b01
`define SOC_AXI_RESP_SLVERR        2'b10
`define SOC_AXI_RESP_DECERR        2'b11

// Memory map
`define SOC_BOOT_BASE         32'h0000_0000
`define SOC_FLASH_BASE        32'h1000_0000
`define SOC_APB_BASE          32'h4000_0000
`define SOC_SRAM_ALIAS_BASE   32'hA000_0000
`define SOC_DEBUG_BASE        32'hE000_0000
// DDR window (Phase C.4): 128MB physical reservation for a future DDR3
// controller. Today backed only by a behavioral capacity placeholder
// (rtl/perips/axi_ddr_behavioral.v) — no timing/refresh/PHY realism. See
// docs/block_specs/ddr3_spec.md for the real controller scope (deferred,
// gated on procured PHY IP).
// NOTE: SOC_DDR_BASE is not 256MB-aligned (it sits at a 128MB boundary), so
// unlike SRAM/APB/FLASH it cannot be decoded with a simple mask-equality
// check against SOC_256MB_REGION_MASK. Sized at 128MB (not the originally
// scoped 256MB) so the window (0x0800_0000-0x0FFF_FFFF) sits entirely below
// FLASH's own 256MB window (0x1000_0000-0x1FFF_FFFF) with no overlap. The
// DDR branch in axi_crossbar's decode_slave() uses an explicit range
// compare against SOC_DDR_BASE/SOC_DDR_SIZE instead of a mask compare.
`define SOC_DDR_BASE          32'h0800_0000
`define SOC_DDR_SIZE          32'h0800_0000

// Address decode masks
`define SOC_64KB_REGION_MASK  32'hFFFF_0000
`define SOC_256MB_REGION_MASK 32'hF000_0000

// APB peripheral offsets
`define SOC_APB_UART_OFFSET   16'h0000
`define SOC_APB_TIMER_OFFSET  16'h1000
`define SOC_APB_GPIO_OFFSET   16'h2000
`define SOC_APB_DMA_OFFSET    16'h3000
`define SOC_APB_PIC_OFFSET    16'h4000
// Verification-only APB fault slot. Product builds leave the injector disabled.
`define SOC_APB_FAULT_OFFSET   16'hF000

// GPIO register offsets
`define SOC_GPIO_DATA_OFFSET  12'h000
`define SOC_GPIO_DIR_OFFSET   12'h004

// DMA register offsets
`define SOC_DMA_SRC_OFFSET     12'h000
`define SOC_DMA_DST_OFFSET     12'h004
`define SOC_DMA_LEN_OFFSET     12'h008
`define SOC_DMA_CTRL_OFFSET    12'h00C

// UART register offsets
`define SOC_UART_TX_OFFSET     12'h000
`define SOC_UART_STATUS_OFFSET 12'h004
`define SOC_UART_IRQ_STATUS_OFFSET 12'h008
`define SOC_UART_IRQ_CLEAR_OFFSET  12'h00C

// Timer register offsets
`define SOC_TIMER_CTRL_OFFSET  12'h000
`define SOC_TIMER_LOAD_OFFSET  12'h004
`define SOC_TIMER_VAL_OFFSET   12'h008
`define SOC_TIMER_INT_OFFSET   12'h00C

// PIC register offsets
`define SOC_PIC_STATUS_OFFSET  12'h000
`define SOC_PIC_MASK_OFFSET    12'h004
`define SOC_PIC_ACTIVE_OFFSET  12'h008

// -----------------------------------------------------------------------------
// CP0 Configuration (Phase B.1 — static register extension)
// -----------------------------------------------------------------------------
// PRId (reg 15, sel 0)  layout: {CompanyOptions[7:0], CompanyID[7:0], ProcID[7:0], Revision[7:0]}
`define SOC_CP0_PRID_COMPANY_OPTS  8'h00
`define SOC_CP0_PRID_COMPANY_ID    8'h00
`define SOC_CP0_PRID_PROCESSOR_ID  8'h80   // custom "AP-lite"
`define SOC_CP0_PRID_REVISION      8'h10

// EBase (reg 15, sel 1) reset. Full reg = {2'b10, EBase[29:12], 2'b00, CPUNum[9:0]}.
// Bits [31:30] hardware-forced 10. To preserve legacy vector at 0x00000180
// (current firmware exception handler), reset EBase[29:12] = 0.
`define SOC_CP0_EBASE_RESET_HI     18'h00000
`define SOC_CP0_CPUNUM             10'd0

// TLB size (reported in Config1.MMUSize as N-1). Phase B.3 populates real TLB.
`define SOC_CP0_TLB_ENTRIES        64

// Cache geometry as of Phase B.1 (Phase C will update for 4-way L1 + L2).
//   IS = log2(sets/64), IL = log2(line/2)+1, IA = ways-1
// Current I-cache: 8KB / 1-way / 32B line / 256 sets  → IS=2, IL=5, IA=0
// Current D-cache: 8KB / 2-way / 32B line / 128 sets  → DS=1, DL=5, DA=1
`define SOC_CP0_CONFIG1_IS         3'd2
`define SOC_CP0_CONFIG1_IL         3'd5
`define SOC_CP0_CONFIG1_IA         3'd0
`define SOC_CP0_CONFIG1_DS         3'd1
`define SOC_CP0_CONFIG1_DL         3'd5
`define SOC_CP0_CONFIG1_DA         3'd1

// Config (reg 16, sel 0) bit K0 (kseg0 cache attr): 011 = cacheable write-back
`define SOC_CP0_CONFIG_K0_RESET    3'b011

// Status.BEV reset. Strict MIPS spec = 1'b1 (vector base 0xBFC00380 at reset).
// Deviation: current test firmware installs handler at .except_vector linked to
// 0x00000180 and does not clear BEV; keep BEV=0 at reset until Phase F introduces
// a real 0xBFC00000 boot ROM. Documented in cp0_spec.md v1 pending update.
`define SOC_CP0_STATUS_BEV_RESET   1'b0

// -----------------------------------------------------------------------------
// CP0 Timer (Phase B.2 — Count/Compare)
// -----------------------------------------------------------------------------
// Count prescaler: Count increments once every SOC_CP0_COUNT_DIV cpu cycles.
// Traditional MIPS 24Kc runs Count at pipeline_clk/2 → COUNT_DIV=2. Value must
// be a positive integer; 1 = every cycle.
`define SOC_CP0_COUNT_DIV          2

// Compare reset value. Spec leaves this UNDEFINED at reset. Reset to all-1s so
// that TI (Cause[30]) is NOT asserted immediately after Count=0 boot; existing
// firmware that never writes Compare must not see a spurious timer IRQ latched.
`define SOC_CP0_COMPARE_RESET      32'hFFFF_FFFF

// -----------------------------------------------------------------------------
// AXI crossbar (Phase C.3)
// -----------------------------------------------------------------------------
// Per-slave outstanding depth accepted at the crossbar boundary. Realized
// end-to-end depth is capped at 1 by today's single-outstanding slaves; the
// crossbar still accepts up to this many ARs/AWs per slave (ready for a future
// MSHR L1 / non-blocking L2). Cross-slave concurrency is realized now.
`define SOC_XBAR_N_OT              4
// Static per-master QoS class (4-bit). Higher wins per-slave arbitration; ties
// break round-robin. Rationale: latency-critical CPU load/store first, fetch
// next, bulk DMA lower, debug/ext lowest. Dynamic per-transaction QoS deferred
// until masters emit AxQOS (they drive these constants today).
`define SOC_XBAR_QOS_DCACHE        4'd12   // m1 D$
`define SOC_XBAR_QOS_ICACHE        4'd8    // m0 I$
`define SOC_XBAR_QOS_DMA           4'd4    // m2 DMA
`define SOC_XBAR_QOS_JTAG          4'd2    // jtag
`define SOC_XBAR_QOS_EXT           4'd1    // ext (verification)

// -----------------------------------------------------------------------------
// MMU / TLB (Phase B.3 series)
// -----------------------------------------------------------------------------
// log2(TLB_ENTRIES). Config1.MMUSize is TLB_ENTRIES-1, sized to fit.
`define SOC_CP0_TLB_INDEX_BITS     6                  // log2(64)
`define SOC_CP0_TLB_INDEX_MAX      6'd63              // TLB_ENTRIES-1

// Address translation enable. Phase B.3.a introduces only CP0 register storage;
// leave translation path off so kseg0/1 direct-map + useg-untranslated flow of
// existing firmware is preserved. Phase B.3.c will bring the actual lookup path
// online (see mmu_tlb_spec.md §8).
// Guarded with ifndef so a test can opt into SOC_MMU_ENABLE=1 via
// +define+SOC_MMU_ENABLE=1 on the vcs command line without changing this
// project-wide default (which every other firmware/test still compiles
// against). KNOWN BLOCKED: see docs/block_specs/mmu_tlb_spec.md Phase B.3.2
// note -- flipping this on breaks boot today (useg vector placement).
`ifndef SOC_MMU_ENABLE
`define SOC_MMU_ENABLE             0
`endif

// -----------------------------------------------------------------------------
// Branch Predictor (Phase B.6 series). See docs/block_specs/bpu_spec.md.
// -----------------------------------------------------------------------------
`define SOC_BPU_ENABLE             0            // 1 = drive IF next_pc from BPU
`define SOC_BTB_ENTRIES            256
`define SOC_BTB_INDEX_BITS         8            // log2(256)
`define SOC_BHT_ENTRIES            256
`define SOC_BHT_INDEX_BITS         8
`define SOC_RAS_DEPTH              8
`define SOC_RAS_DEPTH_BITS         3            // log2(8)

`endif
