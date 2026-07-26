// =============================================================================
// File Name : mips_mmu.v
// Module    : mips_mmu
// Design    : MIPS32 R2 address-translation combinational core (Phase B.3.c)
// Standard  : Verilog-2001 (synthesizable)
//
// One instance per translation port (I-fetch / D-load/store). Combinational,
// no state; TLB lookup port is provided by the caller (mips_cp0/mips_tlb).
//
// Address-space decode (single-VA):
//   0x0000_0000-0x7FFF_FFFF  useg    : identity when SOC_MMU_ENABLE=0, else TLB
//   0x8000_0000-0x9FFF_FFFF  kseg0   : PA[28:0]=VA[28:0], cache attr = Config.K0
//   0xA000_0000-0xBFFF_FFFF  kseg1   : PA[28:0]=VA[28:0], uncached (3'b010)
//   0xC000_0000-0xDFFF_FFFF  sseg    : identity when SOC_MMU_ENABLE=0, else TLB
//   0xE000_0000-0xFFFF_FFFF  kseg3   : identity when SOC_MMU_ENABLE=0, else TLB
//
// Fault reporting is exposed but not yet consumed by the pipeline; Phase B.3.d
// wires it to the exception path (TLBL / TLBS / Mod / AdEL / AdES).
// =============================================================================

`include "soc_config.vh"

module mips_mmu (
    // Request from CPU pipeline (IF or MEM stage)
    input  wire        req_valid,
    input  wire [31:0] req_va,
    input  wire        req_is_store,  // 1 = D-side store (drives TLB Modified fault check)
    input  wire        req_is_fetch,  // 1 = I-side fetch (cache attr defaults to Config.K0 for kseg0)

    // CP0 state
    input  wire [7:0]  asid,
    input  wire [2:0]  config_k0,
    input  wire        is_kernel,   // Phase B.4: 1 = current effective mode is kernel

    // TLB lookup port (from mips_cp0 pass-through to mips_tlb)
    output wire [31:0] tlb_lookup_va,
    output wire [7:0]  tlb_lookup_asid,
    input  wire        tlb_lookup_hit,
    input  wire        tlb_lookup_v,
    input  wire        tlb_lookup_d,
    input  wire [2:0]  tlb_lookup_c,
    input  wire [19:0] tlb_lookup_pfn,

    // Translated output
    output wire [31:0] pa,
    output wire [2:0]  cache_attr,
    output wire        translation_ok,
    // Fault classification (only meaningful when !translation_ok && req_valid):
    //   000 = no fault
    //   001 = TLBL (load / instruction TLB miss OR invalid)
    //   010 = TLBS (store TLB miss OR invalid)
    //   011 = Mod  (TLB modified: store to non-dirty page)
    //   100 = AdEL (address error on fetch or load — reserved for B.3.d/B.4)
    //   101 = AdES (address error on store — reserved for B.3.d/B.4)
    output wire [2:0]  fault_type
);

    // -------------------------------------------------------------------------
    // Address-space classification (VA[31:29])
    // -------------------------------------------------------------------------
    wire        is_kseg0    = (req_va[31:29] == 3'b100);  // 0x80000000-0x9FFFFFFF
    wire        is_kseg1    = (req_va[31:29] == 3'b101);  // 0xA0000000-0xBFFFFFFF
    wire        is_kseg_dir = is_kseg0 | is_kseg1;
    // Translated segments (useg, sseg, kseg3): TLB miss or identity per MMU_ENABLE
    wire        is_tlb_seg  = !is_kseg_dir;

    // -------------------------------------------------------------------------
    // TLB lookup driver (only for translated segments; kseg0/1 skip it)
    // -------------------------------------------------------------------------
    assign tlb_lookup_va   = req_va;
    assign tlb_lookup_asid = asid;

    // -------------------------------------------------------------------------
    // Physical-address computation
    // -------------------------------------------------------------------------
    // kseg0/1: strip top 3 bits, keep lower 29 bits
    wire [31:0] pa_kseg_dir = { 3'b000, req_va[28:0] };
    // TLB lookup path: {PFN, VA[11:0]}
    wire [31:0] pa_tlb      = { tlb_lookup_pfn, req_va[11:0] };
    // Identity fallback when MMU disabled: VA passes through untranslated
    wire [31:0] pa_identity = req_va;

    // Cache attribute
    wire [2:0]  attr_kseg0    = config_k0;         // software-configurable
    wire [2:0]  attr_kseg1    = 3'b010;            // uncached (spec §4)
    wire [2:0]  attr_tlb      = tlb_lookup_c;
    wire [2:0]  attr_identity = 3'b011;            // cacheable WB default

    // Route
`ifdef DUMMY_UNUSED_SIGNAL_KEEP_SILENT
    // (keeps lint quiet — no functional effect)
`endif

    reg [31:0] pa_r;
    reg [2:0]  attr_r;
    reg        ok_r;
    reg [2:0]  fault_r;
    always @(*) begin
        // Default: identity + no fault. This is what SOC_MMU_ENABLE=0 produces
        // for every segment, keeping the current SoC fabric layout intact — in
        // particular the 0xA000_0000 SRAM-alias slave, which the fabric routes
        // as a distinct target rather than as a cache-attribute variant of the
        // 0x0000_0000 boot SRAM. Once the fabric is refactored to fold aliased
        // slaves into a single physical target (Phase C), SOC_MMU_ENABLE can
        // flip and kseg0/1 direct-mapping activates as spec requires.
        pa_r    = pa_identity;
        attr_r  = attr_identity;
        ok_r    = 1'b1;
        fault_r = 3'b000;

        if (!req_valid) begin
            // Idle: leave defaults
        end else if (!is_kernel && req_va[31]) begin
            // Phase B.4: user-mode access to any kernel segment (kseg0/1/2/3)
            // is unconditional AdEL/AdES per MIPS Vol III §4. Independent of
            // SOC_MMU_ENABLE — the segmentation rule is architectural.
            ok_r    = 1'b0;
            fault_r = req_is_store ? 3'b101 : 3'b100;    // AdES / AdEL
        end else if (`SOC_MMU_ENABLE == 0) begin
            // Compatibility mode: identity map for every segment. See comment
            // above for the fabric-alias rationale.
            pa_r   = pa_identity;
            attr_r = attr_identity;
        end else if (is_kseg0) begin
            pa_r   = pa_kseg_dir;
            attr_r = attr_kseg0;
        end else if (is_kseg1) begin
            pa_r   = pa_kseg_dir;
            attr_r = attr_kseg1;
        end else begin
            // TLB-translated path (MMU active). PageMask=0 (4KB) assumption.
            if (!tlb_lookup_hit) begin
                ok_r    = 1'b0;
                fault_r = req_is_store ? 3'b010 : 3'b001;   // TLBS or TLBL
            end else if (!tlb_lookup_v) begin
                ok_r    = 1'b0;
                fault_r = req_is_store ? 3'b010 : 3'b001;   // Invalid → same ExcCode, different vector (B.3.d)
            end else if (req_is_store && !tlb_lookup_d) begin
                ok_r    = 1'b0;
                fault_r = 3'b011;                             // Mod
            end else begin
                pa_r   = pa_tlb;
                attr_r = attr_tlb;
            end
        end
    end

    assign pa             = pa_r;
    assign cache_attr     = attr_r;
    assign translation_ok = ok_r;
    assign fault_type     = fault_r;

    // Suppress "unused" lint on req_is_fetch — reserved for Phase B.4 CU/PROT
    // routing when user mode gating lands.
    wire _unused_ok = &{1'b0, req_is_fetch};

endmodule
