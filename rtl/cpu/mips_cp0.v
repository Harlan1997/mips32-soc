// =============================================================================
// File Name : mips_cp0.v
// Module    : mips_cp0
// Design    : MIPS32 R2 Coprocessor 0 (Phase B.1 + B.2 baseline)
// Standard  : Verilog-2001 (synthesizable)
// Reset     : posedge clk / negedge rst_n (project convention)
//
// Phase B.1: PRId / EBase / Config[0..3] / HWREna / IntCtl / ErrorEPC storage
// with (regnum, sel) sub-select decoding; ebase_out exposed; $display guarded.
//
// Phase B.2: CP0 Timer
//   - Count (9,0)   : 32-bit free-running counter, prescaled by SOC_CP0_COUNT_DIV,
//                     paused while Cause.DC=1
//   - Compare (11,0): 32-bit software match value; writing it also clears Cause.TI
//   - Cause.TI (30) : latched, set when Count == Compare, cleared on Compare write
//   - Cause.DC (27) : software-writable Count-disable
//   - IntCtl.IPTI[31:29]: selects which Cause.IP bit receives TI (default 7)
//   - Combined IP field  Cause.IP[7:2] = hw_int | (timer_ip << (IPTI-2))
//
// Phase B.3.a (this file): MMU CP0 register storage only
//   - Index (0,0)     : [31]=P (probe fail), [log2(N)-1:0]=index
//   - Random (1,0)    : hardware-decrementing 6-bit counter, wraps N-1 → Wired
//   - EntryLo0 (2,0)  : PFN + Cache attr + D + V + G
//   - EntryLo1 (3,0)  : PFN + Cache attr + D + V + G
//   - Context (4,0)   : PTEBase (SW writable) + BadVPN2 (HW updated in B.3.d)
//   - PageMask (5,0)  : Mask field (variable page-size selector)
//   - Wired (6,0)     : software lower bound of Random; writing it also resets Random
//   - BadVAddr (8,0)  : read-only; hardware update deferred to B.3.d
//   - EntryHi (10,0)  : VPN2 + ASID (both software writable)
//
// Regression preservation for B.3.a:
//   - No TLB data array, no TLB instructions, no lookup path yet: firmware that
//     never touches MMU sees no behavior change. SOC_MMU_ENABLE stays 0.
//
// Deferred to later Phase B sub-steps:
//   - TLB data array + TLBR/TLBWI/TLBWR/TLBP instructions (B.3.b)
//   - micro-TLB (I/D) + kseg0/1/2/3 + useg translation path (B.3.c)
//   - TLB Refill / Invalid / Modified / MCheck exception paths + BadVAddr /
//     Context.BadVPN2 hardware update (B.3.d)
//   - Linux head.S paging-on integration (B.3.e)
//   - RDHWR $2 → Count (needs Phase B.4 user mode + instruction decode)
//   - KSU / User mode enforcement (B.4)
//   - Precise exception refinement + BD-in-pipeline plumbing (B.5)
//   - TLB-refill and cache-error vector selection (B.5).
//     Product-mode ordinary BEV/EBase and IP-based vectored-interrupt selection
//     are implemented by mips_cpu; cache-error policy remains separate.
// =============================================================================

`include "soc_config.vh"

module mips_cp0 (
    input  wire        clk,
    input  wire        rst_n,

    // Hardware Interrupts (from PIC / timer / external)
    input  wire [5:0]  hw_int,

    // MTC0/MFC0 Interface (from WB stage)
    input  wire        we,           // Write enable (MTC0)
    input  wire [4:0]  waddr,        // CP0 regnum for write
    input  wire [2:0]  wsel,         // CP0 sub-select for write
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr,        // CP0 regnum for read (MFC0)
    input  wire [2:0]  rsel,         // CP0 sub-select for read
    output reg  [31:0] rdata,

    // TLB instruction op (Phase B.3.b, see mips_control.v encoding):
    //   000 = none, 001 = TLBR, 010 = TLBWI, 011 = TLBWR, 100 = TLBP
    input  wire [2:0]  tlb_op,

    // I/D-cache TagLo/TagHi maintenance contract. The cache operation code
    // selects which cache supplied the merged tag read data in mips_core.
    input  wire        cache_op_done,
    input  wire [4:0]  cache_op,
    input  wire [31:0] cache_tag_rdata,

    // Exception Interface (from WB stage)
    input  wire        except_req,
    input  wire [4:0]  except_code,
    input  wire [31:0] except_pc,
    input  wire        except_bd,
    input  wire        eret,
    // Phase B.3.d: faulting virtual address for BadVAddr / Context.BadVPN2
    // Latched only when except_code is address-related (1/2/3/4/5).
    input  wire [31:0] bad_vaddr,
    // Single-core LL/SC reservation address (CP0 LLAddr, reg 17 sel 0).
    // The reservation itself remains owned by mips_cpu; this is read-only
    // observability for software diagnostics.
    input  wire [31:0] lladdr_in,

    // Outputs to CPU pipeline
    output wire [31:0] epc_out,      // EPC register value (used by ERET)
    output wire [31:0] ebase_out,    // Full EBase register value (for vector gen)
    output wire        bev_out,      // Status.BEV (for CPU exception-vector selection)
    output wire        intr_req,     // Interrupt request to CPU (if enabled)
    output wire        vint_enabled_out, // Cause.IV permits BEV=0 vector selection
    output wire [31:0] vint_offset_out,  // 0x200 + highest enabled IP * (VS * 32)
    // Phase B.4: effective privilege exports
    output wire        kernel_mode,  // 1 = current instruction executes in kernel mode
    output wire        cu0_enable,   // Status.CU0 (allows user-mode CP0 access)

    // Phase B.3.c: MMU translation pass-through. Two TLB lookup ports (I / D)
    // and CP0-owned globals the MMU needs (ASID, Config.K0). These are pure
    // combinational fanout; mips_cp0 does not consume them.
    output wire [7:0]  cp0_asid_out,
    output wire [2:0]  cp0_config_k0_out,
    output wire [31:0] hwrena_out,
    output wire [31:0] taglo_out,
    output wire [31:0] taghi_out,

    input  wire [31:0] mmu_ilookup_va,
    output wire        mmu_ilookup_hit,
    output wire        mmu_ilookup_multi_hit,
    output wire        mmu_ilookup_v,
    output wire        mmu_ilookup_d,
    output wire [2:0]  mmu_ilookup_c,
    output wire [19:0] mmu_ilookup_pfn,

    input  wire [31:0] mmu_dlookup_va,
    output wire        mmu_dlookup_hit,
    output wire        mmu_dlookup_multi_hit,
    output wire        mmu_dlookup_v,
    output wire        mmu_dlookup_d,
    output wire [2:0]  mmu_dlookup_c,
    output wire [19:0] mmu_dlookup_pfn,
    input wire        tlb_inv_en,
    input wire [18:0] tlb_inv_vpn2,
    input wire [7:0]  tlb_inv_asid,
    input wire [1:0]  tlb_inv_scope,
    input wire [5:0]  tlb_inv_wired_floor
);

    // -------------------------------------------------------------------------
    // Register storage
    // -------------------------------------------------------------------------
    //   Reg  Sel  Name       Notes
    //   ---  ---  ---------  --------------------------------------------------
    //   0    0    Index      [31]=P, [5:0]=index (log2 TLB_ENTRIES)  (Phase B.3.a)
    //   1    0    Random     [5:0] hardware counter, wraps N-1→Wired (Phase B.3.a)
    //   2    0    EntryLo0   [25:6]=PFN, [5:3]=C, [2]=D, [1]=V, [0]=G (Phase B.3.a)
    //   3    0    EntryLo1   same layout as EntryLo0                   (Phase B.3.a)
    //   4    0    Context    [31:23]=PTEBase (SW), [22:4]=BadVPN2 (HW, B.3.d)
    //   5    0    PageMask   [28:13]=Mask                              (Phase B.3.a)
    //   6    0    Wired      [5:0] software lower bound on Random      (Phase B.3.a)
    //   7    0    HWREna     User RDHWR enable mask
    //   8    0    BadVAddr   read-only; HW update deferred to B.3.d
    //   9    0    Count      Free-running counter (Phase B.2)
    //   10   0    EntryHi    [31:13]=VPN2, [7:0]=ASID                 (Phase B.3.a)
    //   11   0    Compare    Timer match value (Phase B.2)
    //   12   0    Status     [22]=BEV, [21]=TS, [15:8]=IM, [1]=EXL, [0]=IE
    //   12   1    IntCtl     [31:29]=IPTI, [9:5]=VS
    //   13   0    Cause      [31]=BD, [30]=TI, [27]=DC, [23]=IV, [15:8]=IP, [6:2]=ExcCode
    //   14   0    EPC
    //   15   0    PRId       Read-only, hardcoded via soc_config.vh
    //   15   1    EBase      [31:30]=10 (hw), [29:12]=writable, [9:0]=CPUNum
    //   16   0    Config     [31]=M=1 (Config1 follows), [2:0]=K0
    //   16   1    Config1    Read-only, geometry-derived
    //   16   2    Config2    M=1 (Config3 follows), rest 0
    //   16   3    Config3    Feature bits read-only
    //   30   0    ErrorEPC
    // -------------------------------------------------------------------------

    reg [31:0] cp0_status;
    reg [31:0] cp0_cause;
    reg [31:0] cp0_epc;
    reg [31:0] cp0_errorepc;
    // Tracks whether ErrorEPC contains an active CacheErr/ERL return point.
    // Product reset starts with ERL=1, so the first startup CacheErr must still
    // capture a precise PC even though ERL is already asserted.
    reg        cp0_errorepc_valid;
    reg [17:0] cp0_ebase_hi;      // EBase[29:12] (bits [31:30]=10 forced; [11:10]=0; [9:0]=CPUNum)
    reg [31:0] cp0_hwrena;
    // UserLocal is the software-managed per-thread pointer exposed by CP0
    // (4,2).  RDHWR integration remains a separate decode slice; MFC0/MTC0
    // provides the kernel context-switch ABI in this step.
    reg [31:0] cp0_userlocal;
    reg [2:0]  cp0_config_k0;
    reg [2:0]  cp0_intctl_ipti;
    reg [4:0]  cp0_intctl_vs;

    // Phase B.2 timer storage
    reg [31:0] cp0_count;
    reg [31:0] cp0_compare;
    reg [3:0]  cp0_count_prescale; // Supports SOC_CP0_COUNT_DIV up to 16

    // Phase B.3.a MMU register storage. Lookup / TLB array / exception plumbing
    // are added in later B.3 substeps; here we only hold values so software can
    // MFC0/MTC0 the standard MIPS32 privileged register set without spurious RI.
    localparam TLB_IDX_BITS = `SOC_CP0_TLB_INDEX_BITS;

    // Phase B.3.b: forward-declared TLB combinational read/probe outputs so the
    // main always block can consume them for TLBR / TLBP register updates. The
    // producing mips_tlb instantiation lives at module bottom.
    wire [18:0]              tlb_rd_vpn2;
    wire [7:0]               tlb_rd_asid;
    wire [15:0]              tlb_rd_mask;
    wire [31:0]              tlb_rd_entrylo0;
    wire [31:0]              tlb_rd_entrylo1;
    wire                     tlb_probe_hit;
    wire [TLB_IDX_BITS-1:0]  tlb_probe_index;
    wire                     tlb_probe_multi_hit;
    reg                       cp0_index_p;              // Index[31] probe-fail
    reg [TLB_IDX_BITS-1:0]    cp0_index;                // Index[log2(N)-1:0]
    reg [TLB_IDX_BITS-1:0]    cp0_random;               // free-running downcounter
    reg [TLB_IDX_BITS-1:0]    cp0_wired;                // lower bound for Random
    reg [31:0]                cp0_entrylo0;
    reg [31:0]                cp0_entrylo1;
    reg [8:0]                 cp0_context_ptebase;      // Context[31:23]
    reg [18:0]                cp0_context_badvpn2;      // Context[22:4] (Phase B.3.d, hw-updated)
    reg [15:0]                cp0_pagemask_mask;        // PageMask[28:13]
    reg [31:0]                cp0_badvaddr;             // updated by HW in B.3.d
    reg [18:0]                cp0_entryhi_vpn2;         // EntryHi[31:13]
    reg [7:0]                 cp0_entryhi_asid;         // EntryHi[7:0]
    reg [31:0]                cp0_taglo;
    reg [31:0]                cp0_taghi;

    // -------------------------------------------------------------------------
    // Static reads (hardcoded constants from soc_config.vh)
    // -------------------------------------------------------------------------
    wire [31:0] prid_val = { `SOC_CP0_PRID_COMPANY_OPTS,
                             `SOC_CP0_PRID_COMPANY_ID,
                             `SOC_CP0_PRID_PROCESSOR_ID,
                             `SOC_CP0_PRID_REVISION };

    wire [31:0] ebase_val = { 2'b10, cp0_ebase_hi, 2'b00, `SOC_CP0_CPUNUM };
    assign ebase_out = ebase_val;
    assign bev_out   = cp0_status[22];
    // Forward a same-cycle MTC0 write so an immediately following CACHE
    // Index_Store_Tag_D observes the architectural value at the D-cache port.
    assign taglo_out = (we && (waddr == 5'd28) && (wsel == 3'd0)) ? wdata : cp0_taglo;
    assign taghi_out = (we && (waddr == 5'd29) && (wsel == 3'd0)) ? wdata : cp0_taghi;

    // Config (16,0): M=1, BE=0 (LE), AT=00 (MIPS32), AR=001 (R2), MT=010 (TLB),
    //                VI=0, K0 writable
    wire [31:0] config0_val = { 1'b1,          // M -> Config1 follows
                                15'b0,         // reserved (impl)
                                1'b0,          // BE
                                2'b00,         // AT = MIPS32
                                3'b001,        // AR = R2
                                3'b010,        // MT = standard TLB
                                3'b0,          // reserved
                                1'b0,          // VI
                                cp0_config_k0  // K0
                              };

    // Config1 (16,1): M=1 (Config2 follows), MMUSize = TLB_ENTRIES - 1,
    //                 IS/IL/IA/DS/DL/DA from geometry macros,
    //                 C2=0, MD=0, PC=0 (perf ctr deferred),
    //                 WR=0, CA=0, EP=0, FP=0
    wire [5:0]  mmu_size = `SOC_CP0_TLB_ENTRIES - 1;
    wire [31:0] config1_val = { 1'b1,                      // M
                                mmu_size,                  // MMUSize
                                `SOC_CP0_CONFIG1_IS,       // IS
                                `SOC_CP0_CONFIG1_IL,       // IL
                                `SOC_CP0_CONFIG1_IA,       // IA
                                `SOC_CP0_CONFIG1_DS,       // DS
                                `SOC_CP0_CONFIG1_DL,       // DL
                                `SOC_CP0_CONFIG1_DA,       // DA
                                1'b0,                      // C2
                                1'b0,                      // MD
                                1'b0,                      // PC
                                1'b0,                      // WR (watch)
                                1'b0,                      // CA (code compression)
                                1'b0,                      // EP (EJTAG)
                                1'b0                       // FP
                              };

    // Config2 (16,2): M=1 (Config3 follows), everything else 0 (no L2/L3 yet)
    wire [31:0] config2_val = { 1'b1, 31'b0 };

    // Config3 (16,3): M=0, VInt=1 (vectored int supported via IntCtl.VS),
    //                 rest 0 (no MT/SP/CDMM/TL/ULRI in Phase B.1)
    // Layout: [31]=M, [30:14]=17b rsv, [13]=ULRI, [12:6]=7b rsv, [5]=VEIC,
    //         [4]=rsv, [3]=VInt, [2]=SP, [1]=CDMM, [0]=TL
    wire [31:0] config3_val = { 1'b0,   // M
                                17'b0,
                                1'b1,   // ULRI: UserLocal (4,2) implemented
                                7'b0,
                                1'b0,   // VEIC
                                1'b0,
                                1'b1,   // VInt
                                1'b0,   // SP
                                1'b0,   // CDMM
                                1'b0    // TL
                              };

    // IntCtl (12,1)
    wire [31:0] intctl_val = { cp0_intctl_ipti, 3'b000,    // IPTI, IPPCI
                               16'b0,
                               cp0_intctl_vs, 5'b0 };

    // MMU register read-back assembly (Phase B.3.a)
    wire [31:0] index_val    = { cp0_index_p, {(31-TLB_IDX_BITS){1'b0}}, cp0_index };
    wire [31:0] random_val   = { {(32-TLB_IDX_BITS){1'b0}}, cp0_random };
    wire [31:0] wired_val    = { {(32-TLB_IDX_BITS){1'b0}}, cp0_wired };
    // Context: [31:23]=PTEBase (SW), [22:4]=BadVPN2 (HW updated by B.3.d), [3:0]=rsv
    wire [31:0] context_val  = { cp0_context_ptebase, cp0_context_badvpn2, 4'b0 };
    // PageMask: [28:13]=Mask, everything else 0
    wire [31:0] pagemask_val = { 3'b0, cp0_pagemask_mask, 13'b0 };
    wire [31:0] entryhi_val  = { cp0_entryhi_vpn2, 5'b0, cp0_entryhi_asid };

    // Status (12,0) read-back: assemble writable+reserved bits.
    // Layout: [31:23]=9b (CU3/CU2/CU1/CU0/RP/FR/RE/MX/PX), [22]=BEV,
    //         [21]=TS (MCheck sticky), [20:16]=5b (SR/NMI/impl), [15:8]=IM,
    //         [7:5]=3b, [4:3]=KSU,
    //         [2]=ERL, [1]=EXL, [0]=IE.
    // Phase B.4: KSU[4:3] and CU0[28] added to the writable set. Other CU bits
    // (CU1/CU2/CU3) stay tied 0 until FPU / CP2 land.
    wire [31:0] status_val = { 3'b0,                  // [31:29] CU3..CU1
                               cp0_status[28],        // [28] CU0
                               5'b0,                  // [27:23]
                               cp0_status[22],        // [22] BEV
                               cp0_status[21],        // [21] TS (sticky MCheck)
                               5'b0,                  // [20:16]
                               cp0_status[15:8],      // [15:8]  IM
                               3'b0,                  // [7:5]
                               cp0_status[4:3],       // [4:3]   KSU (Phase B.4)
                               cp0_status[2],         // [2]     ERL  (Phase B.5)
                               cp0_status[1],         // [1]     EXL
                               cp0_status[0] };       // [0]     IE

    // Phase B.4: effective privilege mode. Kernel iff ERL, EXL, or KSU != 2'b10
    // (10 = user). Supervisor (01) currently folds into kernel per B.1 note.
    assign kernel_mode = cp0_status[2] | cp0_status[1] | (cp0_status[4:3] != 2'b10);
    assign cu0_enable  = cp0_status[28];

    // -------------------------------------------------------------------------
    // Timer Interrupt Routing (Phase B.2)
    // -------------------------------------------------------------------------
    // TI held in cp0_cause[30]; suppressed while DC=1 or when TI is not latched.
    // IPTI selects which Cause.IP bit receives the timer request. Combined IP
    // OR-merges hw_int (external sources) with the timer bit so both channels
    // remain observable when they collide on the same IP index.
    wire        timer_ip_active = cp0_cause[30] && !cp0_cause[27];
    wire [7:0]  ip_from_timer   = timer_ip_active ? (8'd1 << cp0_intctl_ipti) : 8'd0;
    wire [5:0]  combined_ip_hw  = hw_int | ip_from_timer[7:2];
    wire        cnt_eq_cmp      = (cp0_count == cp0_compare);

    // -------------------------------------------------------------------------
    // Interrupt Request
    // -------------------------------------------------------------------------
    // Spec: IE && !EXL && !ERL && any (IM & IP) hardware bit set.
    // IP field in cp0_cause is refreshed each cycle with combined_ip_hw below.
    assign intr_req = cp0_status[0] && !cp0_status[1] && !cp0_status[2]
                      && (|(cp0_cause[15:8] & cp0_status[15:8]));

    // Vectored interrupt policy uses the highest numbered enabled pending IP.
    // Config3.VEIC stays zero, so this is an IP-based CPU vector rather than a
    // VIC-provided external vector number.
    function [2:0] highest_enabled_pending_ip;
        input [7:0] pending;
        begin
            if      (pending[7]) highest_enabled_pending_ip = 3'd7;
            else if (pending[6]) highest_enabled_pending_ip = 3'd6;
            else if (pending[5]) highest_enabled_pending_ip = 3'd5;
            else if (pending[4]) highest_enabled_pending_ip = 3'd4;
            else if (pending[3]) highest_enabled_pending_ip = 3'd3;
            else if (pending[2]) highest_enabled_pending_ip = 3'd2;
            else if (pending[1]) highest_enabled_pending_ip = 3'd1;
            else                 highest_enabled_pending_ip = 3'd0;
        end
    endfunction

    wire [7:0]  enabled_pending_ip = cp0_cause[15:8] & cp0_status[15:8];
    wire [2:0]  vint_ip_number = highest_enabled_pending_ip(enabled_pending_ip);
    wire [9:0]  vint_spacing = {cp0_intctl_vs, 5'b0};
    // Extend both operands before multiplication; Verilog otherwise sizes the
    // product to the widest operand and truncates VN*VS for large VS values.
    wire [12:0] vint_ip_number_ext = {10'd0, vint_ip_number};
    wire [12:0] vint_spacing_ext   = {3'd0, vint_spacing};
    wire [12:0] vint_offset = 13'h200 + (vint_ip_number_ext * vint_spacing_ext);

    assign vint_enabled_out = cp0_cause[23];
    assign vint_offset_out  = {19'd0, vint_offset};

    // Phase B.5: ERET target selection — ERL=1 → ErrorEPC (Reset/NMI/CacheErr
    // return path); else EPC (ordinary exception return).
    assign epc_out = cp0_status[2] ? cp0_errorepc : cp0_epc;

    // -------------------------------------------------------------------------
    // CP0 Read Mux (MFC0)
    // Address = {raddr, rsel}. Unknown slot returns 0.
    // -------------------------------------------------------------------------
    always @(*) begin
        rdata = 32'd0;
        case ({raddr, rsel})
            {5'd0,  3'd0}: rdata = index_val;
            {5'd1,  3'd0}: rdata = random_val;
            {5'd2,  3'd0}: rdata = cp0_entrylo0;
            {5'd3,  3'd0}: rdata = cp0_entrylo1;
            {5'd4,  3'd0}: rdata = context_val;
            {5'd5,  3'd0}: rdata = pagemask_val;
            {5'd6,  3'd0}: rdata = wired_val;
            {5'd7,  3'd0}: rdata = cp0_hwrena;
            {5'd4,  3'd2}: rdata = cp0_userlocal;
            {5'd8,  3'd0}: rdata = cp0_badvaddr;
            {5'd9,  3'd0}: rdata = cp0_count;
            {5'd10, 3'd0}: rdata = entryhi_val;
            {5'd11, 3'd0}: rdata = cp0_compare;
            {5'd12, 3'd0}: rdata = status_val;
            {5'd12, 3'd1}: rdata = intctl_val;
            {5'd13, 3'd0}: rdata = cp0_cause;
            {5'd14, 3'd0}: rdata = cp0_epc;
            {5'd15, 3'd0}: rdata = prid_val;
            {5'd15, 3'd1}: rdata = ebase_val;
            {5'd15, 3'd2}: rdata = 32'd0; // RDHWR CPUNum (single-core)
            {5'd7,  3'd1}: rdata = 32'd32; // RDHWR SYNCI_Step (32-byte I-cache line)
            {5'd9,  3'd1}: rdata = 32'd2; // RDHWR CCRes (Count increments every 2 cycles)
            {5'd17, 3'd0}: rdata = lladdr_in;
            {5'd16, 3'd0}: rdata = config0_val;
            {5'd16, 3'd1}: rdata = config1_val;
            {5'd16, 3'd2}: rdata = config2_val;
            {5'd16, 3'd3}: rdata = config3_val;
            {5'd28, 3'd0}: rdata = cp0_taglo;
            {5'd29, 3'd0}: rdata = cp0_taghi;
            {5'd30, 3'd0}: rdata = cp0_errorepc;
            default:       rdata = 32'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // CP0 State Update
    // Exception takes priority over ERET and MTC0 (unchanged from v0).
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cp0_status      <= { 9'b0,                        // [31:23]
                                 ((`SOC_PRODUCT_BOOT_ENABLE != 0) ? 1'b1 : `SOC_CP0_STATUS_BEV_RESET), // [22] BEV
                                 6'b0,                        // [21:16]
                                 8'b0,                        // [15:8] IM
                                 3'b0,                        // [7:5]
                                 2'b0,                        // [4:3] KSU
                                 ((`SOC_PRODUCT_BOOT_ENABLE != 0) ? 1'b1 : 1'b0), // [2] ERL
                                 1'b0,                        // [1] EXL
                                 1'b0 };                      // [0] IE
            cp0_cause       <= 32'd0;
            cp0_epc         <= 32'd0;
            cp0_errorepc    <= 32'd0;
            cp0_errorepc_valid <= 1'b0;
            cp0_ebase_hi    <= `SOC_CP0_EBASE_RESET_HI;
            cp0_hwrena      <= 32'd0;
            cp0_userlocal   <= 32'd0;
            cp0_config_k0   <= `SOC_CP0_CONFIG_K0_RESET;
            cp0_intctl_ipti <= 3'd7;                       // Timer int mapped to IP7 by default
            cp0_intctl_vs   <= 5'd0;                       // Non-vectored default
            cp0_count           <= 32'd0;
            cp0_compare         <= `SOC_CP0_COMPARE_RESET; // All-1s avoids boot-time TI
            cp0_count_prescale  <= 4'd0;

            // Phase B.3.a MMU register reset
            cp0_index_p         <= 1'b0;
            cp0_index           <= {TLB_IDX_BITS{1'b0}};
            cp0_random          <= `SOC_CP0_TLB_INDEX_MAX;
            cp0_wired           <= {TLB_IDX_BITS{1'b0}};
            cp0_entrylo0        <= 32'd0;
            cp0_entrylo1        <= 32'd0;
            cp0_context_ptebase <= 9'd0;
            cp0_context_badvpn2 <= 19'd0;
            cp0_pagemask_mask   <= 16'd0;
            cp0_badvaddr        <= 32'd0;
            cp0_entryhi_vpn2    <= 19'd0;
            cp0_entryhi_asid    <= 8'd0;
            cp0_taglo           <= 32'd0;
            cp0_taghi           <= 32'd0;
        end else begin
            // -----------------------------------------------------------------
            // Cause.IP[7:2] update every cycle: mirror hw_int OR timer routing.
            // -----------------------------------------------------------------
            cp0_cause[15:10] <= combined_ip_hw;

            // -----------------------------------------------------------------
            // TI (Cause[30]) latch: software writing Compare clears; matching
            // Count sets. Software write wins in the same cycle.
            // -----------------------------------------------------------------
            if (we && ({waddr, wsel} == {5'd11, 3'd0}))
                cp0_cause[30] <= 1'b0;
            else if (cnt_eq_cmp)
                cp0_cause[30] <= 1'b1;

            // -----------------------------------------------------------------
            // Count prescaler and increment (paused while Cause.DC=1).
            // Software writes to Count reset the prescaler for deterministic
            // step alignment.
            // -----------------------------------------------------------------
            if (we && ({waddr, wsel} == {5'd9, 3'd0})) begin
                cp0_count           <= wdata;
                cp0_count_prescale  <= 4'd0;
            end else if (!cp0_cause[27]) begin
                if (cp0_count_prescale == (`SOC_CP0_COUNT_DIV - 1)) begin
                    cp0_count_prescale <= 4'd0;
                    cp0_count          <= cp0_count + 32'd1;
                end else begin
                    cp0_count_prescale <= cp0_count_prescale + 4'd1;
                end
            end

            // -----------------------------------------------------------------
            // Random hardware downcounter (Phase B.3.a). Runs every cycle; wraps
            // to TLB_INDEX_MAX whenever it hits Wired or Wired is written.
            // -----------------------------------------------------------------
            if (we && ({waddr, wsel} == {5'd6, 3'd0}))
                cp0_random <= `SOC_CP0_TLB_INDEX_MAX;
            else if (cp0_random <= cp0_wired)
                cp0_random <= `SOC_CP0_TLB_INDEX_MAX;
            else
                cp0_random <= cp0_random - {{(TLB_IDX_BITS-1){1'b0}}, 1'b1};

            if (cache_op_done && ((cache_op == 5'b00101) ||
                                  (cache_op == 5'b00100)))
                cp0_taglo <= cache_tag_rdata;

            if (except_req && !cp0_status[1]) begin
                // Take exception (only if not already in exception level)
                // synopsys translate_off
`ifdef SIMULATION
                $display("[%0t] EXCEPTION TAKEN! cause=%h epc=%h intr_req=%b hw_int=%b",
                         $time, except_code, except_pc, intr_req, hw_int);
`endif
                // synopsys translate_on
                // MIPS CacheErr is an Error exception: use ERL/ErrorEPC and
                // leave EXL clear so ERET returns through the error path.
                // All other synchronous exceptions retain the ordinary EPC/
                // EXL contract used by the existing CPU pipeline.
                if (except_code == 5'h1E) begin
                    cp0_status[2] <= 1'b1;       // Set ERL
                    if (!cp0_errorepc_valid) begin
                        cp0_errorepc <= except_bd ? (except_pc - 32'd4) : except_pc;
                        cp0_errorepc_valid <= 1'b1;
                    end
                end else begin
                    cp0_status[1] <= 1'b1;        // Set EXL
                    cp0_epc       <= except_pc;
                end
                cp0_cause[6:2] <= except_code;
                cp0_cause[31]  <= except_bd;
                if (except_code == 5'h18)
                    cp0_status[21] <= 1'b1;             // TLB multi-hit shutdown

                // Branch-delay EPC applies to both ordinary and cache-error
                // entries, but ErrorEPC is the architectural return register
                // for CacheErr.
                if (except_bd) begin
                    if (except_code == 5'h1E) begin
                        if (!cp0_errorepc_valid) begin
                            cp0_errorepc <= except_pc - 32'd4;
                            cp0_errorepc_valid <= 1'b1;
                        end
                    end else begin
                        cp0_epc <= except_pc - 32'd4;
                    end
                end

                // Phase B.3.d: address-related exceptions (Mod=1, TLBL=2, TLBS=3,
                // AdEL=4, AdES=5) also latch BadVAddr and Context.BadVPN2 per
                // MIPS Vol III §6.6 / §6.8.
                if (except_code == 5'h01 || except_code == 5'h02 ||
                    except_code == 5'h03 || except_code == 5'h04 ||
                    except_code == 5'h05) begin
                    cp0_badvaddr        <= bad_vaddr;
                    cp0_context_badvpn2 <= bad_vaddr[31:13];
                end

            end else if (eret) begin
                // Phase B.5: ERL priority per MIPS spec — if ERL=1, clear it
                // (returned from Reset/NMI/CacheErr via ErrorEPC); else clear
                // EXL (returned from ordinary exception via EPC).
                if (cp0_status[2])
                    begin
                        cp0_status[2] <= 1'b0;
                        cp0_errorepc_valid <= 1'b0;
                    end
                else
                    cp0_status[1] <= 1'b0;

            end else if (|tlb_op) begin
                case (tlb_op)
                    3'b001: begin // TLBR: TLB[Index] → EntryHi / EntryLo0 / EntryLo1 / PageMask
                        cp0_entryhi_vpn2  <= tlb_rd_vpn2;
                        cp0_entryhi_asid  <= tlb_rd_asid;
                        cp0_pagemask_mask <= tlb_rd_mask;
                        cp0_entrylo0      <= tlb_rd_entrylo0;
                        cp0_entrylo1      <= tlb_rd_entrylo1;
                    end
                    3'b100: begin // TLBP: probe → Index[31]=~hit, Index[low]=hit_index or 0
                        cp0_index_p <= ~tlb_probe_hit;
                        cp0_index   <= tlb_probe_hit ? tlb_probe_index : {TLB_IDX_BITS{1'b0}};
                        if (tlb_probe_multi_hit)
                            cp0_status[21] <= 1'b1; // duplicate probe is MCheck/TS
                    end
                    // TLBWI (010) and TLBWR (011) write TLB array via mips_tlb
                    // instantiation below; they do not modify CP0 register state.
                    default: ;
                endcase
            end else if (we) begin
                case ({waddr, wsel})
                    {5'd0, 3'd0}: begin
                        // Index: writable bits are P (31) and index[log2(N)-1:0].
                        // Software rarely writes P (usually cleared by TLBP hw),
                        // but spec allows it.
                        cp0_index_p      <= wdata[31];
                        cp0_index        <= wdata[TLB_IDX_BITS-1:0];
                    end
                    {5'd2, 3'd0}: begin
                        // EntryLo0: all 32 bits software-writable (spec leaves
                        // high bits reserved; keep as-written for MTC0/MFC0
                        // symmetry, later TLBWI will only pick meaningful bits).
                        cp0_entrylo0     <= wdata;
                    end
                    {5'd3, 3'd0}: begin
                        cp0_entrylo1     <= wdata;
                    end
                    {5'd4, 3'd0}: begin
                        // Context: only PTEBase[31:23] is software-writable;
                        // BadVPN2[22:4] is HW-updated (deferred to B.3.d).
                        cp0_context_ptebase <= wdata[31:23];
                    end
                    {5'd5, 3'd0}: begin
                        // PageMask: [28:13] is Mask; other bits reserved.
                        cp0_pagemask_mask <= wdata[28:13];
                    end
                    {5'd6, 3'd0}: begin
                        // Wired: only low log2(N) bits meaningful.
                        cp0_wired        <= wdata[TLB_IDX_BITS-1:0];
                        // Random reset side-effect is handled outside this
                        // chain to remain uniform across exception/eret cycles.
                    end
                    {5'd7, 3'd0}: begin
                        // HWREna: only bits [3:0] (CPUNum/SYNCI_Step/CC/CCRes)
                        // and [29] (ULR) are defined in R2; keep others 0.
                        cp0_hwrena       <= { 2'b0, wdata[29], 25'b0, wdata[3:0] };
                    end
                    {5'd4, 3'd2}: begin
                        cp0_userlocal    <= wdata;
                    end
                    {5'd10, 3'd0}: begin
                        // EntryHi: [31:13]=VPN2, [7:0]=ASID; middle 5 bits rsv.
                        cp0_entryhi_vpn2 <= wdata[31:13];
                        cp0_entryhi_asid <= wdata[7:0];
                    end
                    {5'd12, 3'd0}: begin
                        cp0_status[28]   <= wdata[28];    // CU0 (Phase B.4)
                        cp0_status[22]   <= wdata[22];    // BEV
                        cp0_status[15:8] <= wdata[15:8];  // IM
                        cp0_status[4:3]  <= wdata[4:3];   // KSU (Phase B.4)
                        cp0_status[2]    <= wdata[2];     // ERL (Phase B.5)
                        cp0_status[1]    <= wdata[1];     // EXL
                        cp0_status[0]    <= wdata[0];     // IE
                    end
                    {5'd12, 3'd1}: begin
                        cp0_intctl_ipti  <= wdata[31:29];
                        cp0_intctl_vs    <= wdata[9:5];
                    end
                    {5'd11, 3'd0}: begin
                        // Compare: sets timer match value; TI clear handled
                        // above (outside the mutually-exclusive if-chain).
                        cp0_compare      <= wdata;
                    end
                    {5'd13, 3'd0}: begin
                        cp0_cause[27]    <= wdata[27];    // DC (Count disable)
                        cp0_cause[23]    <= wdata[23];    // IV
                        cp0_cause[9:8]   <= wdata[9:8];   // SW interrupts
                    end
                    {5'd14, 3'd0}: begin
                        cp0_epc          <= wdata;
                    end
                    {5'd15, 3'd1}: begin
                        // EBase: only [29:12] are writable, bits [31:30] hw-forced to 10,
                        // [11:10] reserved, [9:0] CPUNum read-only.
                        // Additionally per MIPS spec only writable when Status.EXL=0 && Status.BEV=0.
                        if (cp0_status[1] == 1'b0 && cp0_status[22] == 1'b0)
                            cp0_ebase_hi <= wdata[29:12];
                    end
                    {5'd16, 3'd0}: begin
                        // Config: only K0 is software-writable
                        cp0_config_k0    <= wdata[2:0];
                    end
                    {5'd28, 3'd0}: begin
                        cp0_taglo        <= wdata;
                    end
                    {5'd29, 3'd0}: begin
                        cp0_taghi        <= wdata;
                    end
                    {5'd30, 3'd0}: begin
                        cp0_errorepc     <= wdata;
                    end
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // TLB data array (Phase B.3.b)
    // -------------------------------------------------------------------------
    // TLBR / TLBP outputs are combinational; consumed by the always-block above
    // to schedule CP0 register updates. TLBWI / TLBWR drive wr_en synchronously.
    wire        tlb_wr_en_raw = (tlb_op == 3'b010) || (tlb_op == 3'b011);
    // Gate TLB writes with the same conditions that inhibit MTC0: exception on
    // the same instruction (not taken here because tlb_op traps to RI in user
    // mode when B.4 lands) or ERET must not commit a partial TLB write.
    wire        tlb_wr_gate   = !(except_req && !cp0_status[1]) && !eret;
    wire        tlb_wr_en     = tlb_wr_en_raw && tlb_wr_gate;
    wire [TLB_IDX_BITS-1:0] tlb_wr_index = (tlb_op == 3'b010) ? cp0_index
                                                              : cp0_random;

    mips_tlb #(
        .TLB_ENTRIES (`SOC_CP0_TLB_ENTRIES),
        .INDEX_BITS  (TLB_IDX_BITS)
    ) u_mips_tlb (
        .clk         (clk),
        .rst_n       (rst_n),

        .wr_en       (tlb_wr_en),
        .wr_index    (tlb_wr_index),
        .wr_vpn2     (cp0_entryhi_vpn2),
        .wr_asid     (cp0_entryhi_asid),
        .wr_mask     (cp0_pagemask_mask),
        .wr_entrylo0 (cp0_entrylo0),
        .wr_entrylo1 (cp0_entrylo1),
        .inv_en      (tlb_inv_en),
        .inv_vpn2    (tlb_inv_vpn2),
        .inv_asid    (tlb_inv_asid),
        .inv_scope   (tlb_inv_scope),
        .inv_wired_floor(tlb_inv_wired_floor),

        .rd_index    (cp0_index),
        .rd_vpn2     (tlb_rd_vpn2),
        .rd_asid     (tlb_rd_asid),
        .rd_mask     (tlb_rd_mask),
        .rd_entrylo0 (tlb_rd_entrylo0),
        .rd_entrylo1 (tlb_rd_entrylo1),

        .probe_vpn2  (cp0_entryhi_vpn2),
        .probe_asid  (cp0_entryhi_asid),
        .probe_hit   (tlb_probe_hit),
        .probe_index (tlb_probe_index),
        .probe_multi_hit (tlb_probe_multi_hit),

        // Phase B.3.c dual lookup ports (fanned to MMU I / D)
        .lookup0_va  (mmu_ilookup_va),
        .lookup0_asid(cp0_entryhi_asid),
        .lookup0_hit (mmu_ilookup_hit),
        .lookup0_multi_hit (mmu_ilookup_multi_hit),
        .lookup0_v   (mmu_ilookup_v),
        .lookup0_d   (mmu_ilookup_d),
        .lookup0_c   (mmu_ilookup_c),
        .lookup0_pfn (mmu_ilookup_pfn),

        .lookup1_va  (mmu_dlookup_va),
        .lookup1_asid(cp0_entryhi_asid),
        .lookup1_hit (mmu_dlookup_hit),
        .lookup1_multi_hit (mmu_dlookup_multi_hit),
        .lookup1_v   (mmu_dlookup_v),
        .lookup1_d   (mmu_dlookup_d),
        .lookup1_c   (mmu_dlookup_c),
        .lookup1_pfn (mmu_dlookup_pfn)
    );

    assign cp0_asid_out      = cp0_entryhi_asid;
    assign cp0_config_k0_out = cp0_config_k0;
    assign hwrena_out        = cp0_hwrena;

endmodule
