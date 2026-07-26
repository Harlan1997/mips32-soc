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
// Phase B.2 (this file): CP0 Timer
//   - Count (9,0)   : 32-bit free-running counter, prescaled by SOC_CP0_COUNT_DIV,
//                     paused while Cause.DC=1
//   - Compare (11,0): 32-bit software match value; writing it also clears Cause.TI
//   - Cause.TI (30) : latched, set when Count == Compare, cleared on Compare write
//   - Cause.DC (27) : software-writable Count-disable
//   - Cause.IV (23) : software-writable (already available since B.1)
//   - IntCtl.IPTI[31:29]: selects which Cause.IP bit receives TI (default 7)
//   - Combined IP field  Cause.IP[7:2] = hw_int | (timer_ip << IPTI)
//
// Regression preservation: Compare resets to SOC_CP0_COMPARE_RESET (all-1s) so
// TI is not asserted when firmware boots at Count=0 without ever touching Compare.
//
// Deferred to later Phase B sub-steps:
//   - RDHWR $2 → Count (needs Phase B.4 user mode + instruction decode)
//   - KSU / User mode enforcement (B.4)
//   - MMU/TLB registers (B.3, see mmu_tlb_spec.md)
//   - Precise exception refinement + BD-in-pipeline plumbing (B.5)
//   - EBase-driven exception vector (B.5)
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

    // Exception Interface (from WB stage)
    input  wire        except_req,
    input  wire [4:0]  except_code,
    input  wire [31:0] except_pc,
    input  wire        except_bd,
    input  wire        eret,

    // Outputs to CPU pipeline
    output wire [31:0] epc_out,      // EPC register value (used by ERET)
    output wire [31:0] ebase_out,    // Full EBase register value (for vector gen)
    output wire        intr_req      // Interrupt request to CPU (if enabled)
);

    // -------------------------------------------------------------------------
    // Register storage
    // -------------------------------------------------------------------------
    //   Reg  Sel  Name       Notes
    //   ---  ---  ---------  --------------------------------------------------
    //   7    0    HWREna     User RDHWR enable mask
    //   9    0    Count      Free-running counter (Phase B.2)
    //   11   0    Compare    Timer match value (Phase B.2)
    //   12   0    Status     [22]=BEV, [15:8]=IM, [1]=EXL, [0]=IE  (extended)
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
    reg [17:0] cp0_ebase_hi;      // EBase[29:12] (bits [31:30]=10 forced; [11:10]=0; [9:0]=CPUNum)
    reg [31:0] cp0_hwrena;
    reg [2:0]  cp0_config_k0;
    reg [2:0]  cp0_intctl_ipti;
    reg [4:0]  cp0_intctl_vs;

    // Phase B.2 timer storage
    reg [31:0] cp0_count;
    reg [31:0] cp0_compare;
    reg [3:0]  cp0_count_prescale; // Supports SOC_CP0_COUNT_DIV up to 16

    // -------------------------------------------------------------------------
    // Static reads (hardcoded constants from soc_config.vh)
    // -------------------------------------------------------------------------
    wire [31:0] prid_val = { `SOC_CP0_PRID_COMPANY_OPTS,
                             `SOC_CP0_PRID_COMPANY_ID,
                             `SOC_CP0_PRID_PROCESSOR_ID,
                             `SOC_CP0_PRID_REVISION };

    wire [31:0] ebase_val = { 2'b10, cp0_ebase_hi, 2'b00, `SOC_CP0_CPUNUM };
    assign ebase_out = ebase_val;

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
                                1'b0,   // ULRI (UserLocal not implemented yet)
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

    // Status (12,0) read-back: assemble writable+reserved bits.
    // Layout: [31:23]=9b (CU/RP/FR/RE/MX/PX), [22]=BEV, [21:16]=6b (TS/SR/NMI/impl),
    //         [15:8]=IM, [7:5]=3b, [4:3]=KSU, [2]=ERL, [1]=EXL, [0]=IE.
    // Only IM/EXL/IE/BEV are writable in Phase B.1; the rest read 0.
    wire [31:0] status_val = { 9'b0,                  // [31:23]
                               cp0_status[22],        // [22] BEV
                               6'b0,                  // [21:16]
                               cp0_status[15:8],      // [15:8]  IM
                               3'b0,                  // [7:5]
                               2'b0,                  // [4:3]   KSU (Phase B.4)
                               1'b0,                  // [2]     ERL (Phase B.5)
                               cp0_status[1],         // [1]     EXL
                               cp0_status[0] };       // [0]     IE

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
    // Same policy as v0: IE && !EXL && any (IM & IP) hardware bit set.
    // IP field in cp0_cause is refreshed each cycle with combined_ip_hw below.
    assign intr_req = cp0_status[0] && !cp0_status[1] && (|(cp0_cause[15:8] & cp0_status[15:8]));

    assign epc_out = cp0_epc;

    // -------------------------------------------------------------------------
    // CP0 Read Mux (MFC0)
    // Address = {raddr, rsel}. Unknown slot returns 0.
    // -------------------------------------------------------------------------
    always @(*) begin
        rdata = 32'd0;
        case ({raddr, rsel})
            {5'd7,  3'd0}: rdata = cp0_hwrena;
            {5'd9,  3'd0}: rdata = cp0_count;
            {5'd11, 3'd0}: rdata = cp0_compare;
            {5'd12, 3'd0}: rdata = status_val;
            {5'd12, 3'd1}: rdata = intctl_val;
            {5'd13, 3'd0}: rdata = cp0_cause;
            {5'd14, 3'd0}: rdata = cp0_epc;
            {5'd15, 3'd0}: rdata = prid_val;
            {5'd15, 3'd1}: rdata = ebase_val;
            {5'd16, 3'd0}: rdata = config0_val;
            {5'd16, 3'd1}: rdata = config1_val;
            {5'd16, 3'd2}: rdata = config2_val;
            {5'd16, 3'd3}: rdata = config3_val;
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
                                 `SOC_CP0_STATUS_BEV_RESET,   // [22] BEV
                                 6'b0,                        // [21:16]
                                 8'b0,                        // [15:8] IM
                                 3'b0,                        // [7:5]
                                 2'b0,                        // [4:3] KSU
                                 1'b0,                        // [2] ERL
                                 1'b0,                        // [1] EXL
                                 1'b0 };                      // [0] IE
            cp0_cause       <= 32'd0;
            cp0_epc         <= 32'd0;
            cp0_errorepc    <= 32'd0;
            cp0_ebase_hi    <= `SOC_CP0_EBASE_RESET_HI;
            cp0_hwrena      <= 32'd0;
            cp0_config_k0   <= `SOC_CP0_CONFIG_K0_RESET;
            cp0_intctl_ipti <= 3'd7;                       // Timer int mapped to IP7 by default
            cp0_intctl_vs   <= 5'd0;                       // Non-vectored default
            cp0_count           <= 32'd0;
            cp0_compare         <= `SOC_CP0_COMPARE_RESET; // All-1s avoids boot-time TI
            cp0_count_prescale  <= 4'd0;
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

            if (except_req && !cp0_status[1]) begin
                // Take exception (only if not already in exception level)
                // synopsys translate_off
`ifdef SIMULATION
                $display("[%0t] EXCEPTION TAKEN! cause=%h epc=%h intr_req=%b hw_int=%b",
                         $time, except_code, except_pc, intr_req, hw_int);
`endif
                // synopsys translate_on
                cp0_status[1]  <= 1'b1;         // Set EXL
                cp0_cause[6:2] <= except_code;
                cp0_cause[31]  <= except_bd;

                // synopsys translate_off
                if (except_bd)
                    cp0_epc <= except_pc - 32'd4;   // Point to branch instruction
                else
                // synopsys translate_on
                    cp0_epc <= except_pc;           // Point to faulting instruction

            end else if (eret) begin
                // ERET: clear EXL (ErrorEPC path via ERL comes in Phase B.5)
                cp0_status[1] <= 1'b0;

            end else if (we) begin
                case ({waddr, wsel})
                    {5'd7, 3'd0}: begin
                        // HWREna: only bits [3:0] (CPUNum/SYNCI_Step/CC/CCRes)
                        // and [29] (ULR) are defined in R2; keep others 0.
                        cp0_hwrena       <= { 2'b0, wdata[29], 25'b0, wdata[3:0] };
                    end
                    {5'd12, 3'd0}: begin
                        cp0_status[22]   <= wdata[22];    // BEV
                        cp0_status[15:8] <= wdata[15:8];  // IM
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
                    {5'd30, 3'd0}: begin
                        cp0_errorepc     <= wdata;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
