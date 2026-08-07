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
`define SOC_BOOT_ROM_BASE     32'h1FC0_0000
`define SOC_BOOT_ROM_SIZE     32'h0001_0000
`define SOC_BOOT_ROM_KSEG1    32'hBFC0_0000
`define SOC_FLASH_BASE        32'h1000_0000
`define SOC_APB_BASE          32'h4000_0000
`define SOC_SRAM_ALIAS_BASE   32'hA000_0000
`define SOC_DEBUG_BASE        32'hE000_0000
// DDR4 window: 128MB physical reservation backed by the protocol-level
// vendor-neutral controller (rtl/perips/axi_ddr4_controller.v). A real PHY,
// DFI wrapper, DRAM part and board timing remain product integration inputs.
// NOTE: SOC_DDR_BASE is not 256MB-aligned (it sits at a 128MB boundary), so
// unlike SRAM/APB/FLASH it cannot be decoded with a simple mask-equality
// check against SOC_256MB_REGION_MASK. Sized at 128MB (not the originally
// scoped 256MB) so the window (0x0800_0000-0x0FFF_FFFF) sits entirely below
// FLASH's own 256MB window (0x1000_0000-0x1FFF_FFFF) with no overlap. The
// DDR branch in axi_crossbar's decode_slave() uses an explicit range
// compare against SOC_DDR_BASE/SOC_DDR_SIZE instead of a mask compare.
`define SOC_DDR_BASE          32'h0800_0000
`define SOC_DDR_SIZE          32'h0800_0000

// Product boot remains opt-in until Boot ROM, vector, QSPI, DDR, and firmware
// gates all pass. The prototype default preserves the SRAM-preload regressions.
`ifndef SOC_PRODUCT_BOOT_ENABLE
`define SOC_PRODUCT_BOOT_ENABLE 0
`endif

// Address decode masks
`define SOC_64KB_REGION_MASK  32'hFFFF_0000
`define SOC_256MB_REGION_MASK 32'hF000_0000

// APB peripheral offsets
`define SOC_APB_UART_OFFSET   16'h0000
`define SOC_APB_TIMER_OFFSET  16'h1000
`define SOC_APB_GPIO_OFFSET   16'h2000
`define SOC_APB_DMA_OFFSET    16'h3000
`define SOC_APB_PIC_OFFSET    16'h4000
`define SOC_APB_QSPI_OFFSET   16'h5000
`define SOC_APB_DDRCTRL_OFFSET 16'h6000
`define SOC_APB_WDT_OFFSET    16'h7000
`define SOC_APB_BOOT_STATUS_OFFSET 16'h8000
`define SOC_APB_IPI_OFFSET   16'hA000

// Boot status stage values. The register is retained across watchdog reset;
// firmware may use additional implementation-specific intermediate values.
`define SOC_BOOT_STAGE_RESET       8'h00
`define SOC_BOOT_STAGE_QSPI_PROBE  8'h10
`define SOC_BOOT_STAGE_HEADER      8'h20
`define SOC_BOOT_STAGE_DDR_WAIT    8'h30
`define SOC_BOOT_STAGE_COPY_CRC    8'h40
`define SOC_BOOT_STAGE_TLB_MAP     8'h50
`define SOC_BOOT_STAGE_VECTOR      8'h60
`define SOC_BOOT_STAGE_HANDOFF     8'h70
// Verification-only APB fault slot. Product builds leave the injector disabled.
`define SOC_APB_FAULT_OFFSET   16'hF000
`define SOC_APB_QSPI_BASE      32'h4000_5000
`define SOC_APB_DDRCTRL_BASE   32'h4000_6000
`define SOC_APB_WDT_BASE       32'h4000_7000
`define SOC_APB_BOOT_STATUS_BASE 32'h4000_8000
`define SOC_APB_IPI_BASE      32'h4000_A000

// DDR controller APB register offsets. The block is not instantiated yet;
// these definitions freeze the software/RTL address contract before PHY IP
// integration. See docs/block_specs/ddr3_spec.md.
`define SOC_DDRCTRL_CTRL_OFFSET          12'h000
`define SOC_DDRCTRL_STATUS_OFFSET        12'h004
`define SOC_DDRCTRL_TIMING0_OFFSET       12'h008
`define SOC_DDRCTRL_TIMING1_OFFSET       12'h00C
`define SOC_DDRCTRL_TIMING2_OFFSET       12'h010
`define SOC_DDRCTRL_REFRESH_CTRL_OFFSET  12'h014
`define SOC_DDRCTRL_MR0_INIT_OFFSET      12'h018
`define SOC_DDRCTRL_MR1_INIT_OFFSET      12'h01C
`define SOC_DDRCTRL_MR2_INIT_OFFSET      12'h020
`define SOC_DDRCTRL_MR3_INIT_OFFSET      12'h024
`define SOC_DDRCTRL_ADDR_MAP_OFFSET      12'h028
`define SOC_DDRCTRL_ODT_CTRL_OFFSET      12'h02C
`define SOC_DDRCTRL_ERROR_STATUS_OFFSET  12'h030
`define SOC_DDRCTRL_ERROR_CLEAR_OFFSET   12'h034
`define SOC_DDRCTRL_VERSION_OFFSET       12'h038
`define SOC_DDRCTRL_PHY_CTRL_OFFSET      12'h040
`define SOC_DDRCTRL_PHY_STATUS_OFFSET    12'h044
`define SOC_DDRCTRL_IRQ_EN_OFFSET        12'h080
`define SOC_DDRCTRL_IRQ_STATUS_OFFSET    12'h084
`define SOC_DDRCTRL_ECC_CTRL_OFFSET      12'h100
`define SOC_DDRCTRL_ECC_STATUS_OFFSET    12'h104
`define SOC_DDRCTRL_ECC_ADDR_OFFSET      12'h108
`define SOC_DDRCTRL_PERF_R_CNT_OFFSET    12'h200
`define SOC_DDRCTRL_PERF_W_CNT_OFFSET    12'h204
`define SOC_DDRCTRL_PERF_REF_CNT_OFFSET  12'h208
`define SOC_DDRCTRL_VERSION              32'h4444_0301
`define SOC_DDRCTRL_STATUS_INIT_DONE_BIT 0
`define SOC_DDRCTRL_STATUS_CALIB_DONE_BIT 1
`define SOC_DDRCTRL_STATUS_BUSY_BIT      2
`define SOC_DDRCTRL_STATUS_REFRESH_BIT   3
`define SOC_DDRCTRL_STATUS_SELF_REFRESH_BIT 4
`define SOC_DDRCTRL_STATUS_ERROR_BIT     5
`define SOC_DDRCTRL_STATUS_AXI_REJECT_BIT 6
`define SOC_DDRCTRL_STATUS_DFI_INIT_BIT  7
`define SOC_DDRCTRL_STATUS_PHY_READY_BIT 8
`define SOC_DDRCTRL_ERR_PHY_INIT_TIMEOUT 16'h0001
`define SOC_DDRCTRL_ERR_CALIBRATION      16'h0002
`define SOC_DDRCTRL_ERR_REFRESH_DEADLINE 16'h0003
`define SOC_DDRCTRL_ERR_AXI              16'h0004
`define SOC_DDRCTRL_ERR_GEOMETRY         16'h0005
`define SOC_DDRCTRL_ERR_RESET_CDC        16'h0006

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

// Status.BEV reset for the prototype configuration. Product boot overrides this
// to 1 (and ERL to 1) inside mips_cp0, selecting the Boot ROM exception vector.
// Prototype firmware remains linked at 0x00000180 and therefore retains BEV=0.
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
// note -- prototype MMU firmware must use the kseg0 bootstrap linker contract
// (reset 0x80000000, general vector 0x80000180); the legacy useg image remains
// valid only when MMU translation is disabled.
`ifndef SOC_MMU_ENABLE
`define SOC_MMU_ENABLE             0
`endif

// Explicit opt-in for the prototype kseg0 reset/vector firmware contract.
// MMU unit tests and other synthetic CPU users retain their normal reset PC
// unless they also request a preload image linked for kseg0.
`ifndef SOC_MMU_BOOTSTRAP_ENABLE
`define SOC_MMU_BOOTSTRAP_ENABLE   0
`endif

// -----------------------------------------------------------------------------
// Branch Predictor (Phase B.6 series). See docs/block_specs/bpu_spec.md.
// -----------------------------------------------------------------------------
`ifndef SOC_BPU_ENABLE
`define SOC_BPU_ENABLE             0            // 1 = drive IF next_pc from BPU
`endif
`define SOC_BTB_ENTRIES            256
`define SOC_BTB_INDEX_BITS         8            // log2(256)
`define SOC_BHT_ENTRIES            256
`define SOC_BHT_INDEX_BITS         8
`define SOC_RAS_DEPTH              8
`define SOC_RAS_DEPTH_BITS         3            // log2(8)

`endif
