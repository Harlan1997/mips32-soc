// =============================================================================
// File Name: l2_cache_nb.v
// Design:    L2 Unified Cache — NON-BLOCKING (full MSHR) variant
// Author:    Antigravity — Phase C.2 / non-blocking L2
// Description:
//   128KB 8-way set-associative write-back write-allocate L2, same geometry as
//   l2_cache_caching, but non-blocking: it accepts new upstream requests while
//   prior misses are outstanding, tracks misses in an N-entry MSHR file, merges
//   secondary misses to the same line, and completes responses out of order
//   across AXI IDs (in-order per ID).
//
//   Correctness model (race-free by construction):
//     * ACCEPT stage is the SINGLE serialization point for the data array and
//       is strictly in arrival order. Read-hits copy the line into the order-
//       queue entry's buffer here; write-hits merge into the array here. Thus
//       the array is only mutated/observed in program order.
//     * MISS ENGINE runs concurrently but issues to the downstream master port
//       ONE transaction at a time (honors the single-outstanding fabric
//       contract). On fill it services that MSHR's waiters in arrival order:
//       writes merge into the freshly-filled line, reads copy it out.
//     * RESPOND stage drains ready entries out of order across IDs but in order
//       within an ID; it reads only per-entry buffers, never the array, so
//       eviction/fill races cannot corrupt an already-resolved response.
//     * An MSHR stays allocated until its last waiter is responded, so an
//       incoming access to that line always either hits (line present) or
//       merges (MSHR present) — never falls through to a duplicate refill.
//
//   Downstream single-outstanding: the miss engine is a serial FSM; at most one
//   AR or one AW+W burst is in flight on the master port at any time.
//
//   Snoop port tied off. Arrays are retention memory (cold-boot init, not wiped
//   by warm rst_n) — identical policy to l2_cache_caching.
// =============================================================================

`include "soc_config.vh"

module l2_cache_nb #(
    parameter SIZE_BYTES = 131072,
    parameter LINE_BYTES = 32,
    parameter WAYS       = 8,
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter N_MSHR     = 8,   // outstanding miss slots
    parameter ORD_DEPTH  = 8,   // in-flight accepted-request slots
    parameter WB_DEPTH   = 4    // buffered dirty victim lines
) (
    input  wire clk,
    input  wire rst_n,

    // Upstream slave interface
    input  wire [ID_WIDTH-1:0]   s_awid,
    input  wire [ADDR_WIDTH-1:0] s_awaddr,
    input  wire [7:0]            s_awlen,
    input  wire [2:0]            s_awsize,
    input  wire [1:0]            s_awburst,
    input  wire                  s_awvalid,
    output reg                   s_awready,
    input  wire [DATA_WIDTH-1:0] s_wdata,
    input  wire [3:0]            s_wstrb,
    input  wire                  s_wlast,
    input  wire                  s_wvalid,
    output reg                   s_wready,
    output reg  [ID_WIDTH-1:0]   s_bid,
    output reg  [1:0]            s_bresp,
    output reg                   s_bvalid,
    input  wire                  s_bready,
    input  wire [ID_WIDTH-1:0]   s_arid,
    input  wire [ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]            s_arlen,
    input  wire [2:0]            s_arsize,
    input  wire [1:0]            s_arburst,
    input  wire                  s_arvalid,
    output reg                   s_arready,
    output reg  [ID_WIDTH-1:0]   s_rid,
    output reg  [DATA_WIDTH-1:0] s_rdata,
    output reg  [1:0]            s_rresp,
    output reg                   s_rlast,
    output reg                   s_rvalid,
    input  wire                  s_rready,

    // Downstream master interface
    output reg  [ID_WIDTH-1:0]   m_awid,
    output reg  [ADDR_WIDTH-1:0] m_awaddr,
    output reg  [7:0]            m_awlen,
    output reg  [2:0]            m_awsize,
    output reg  [1:0]            m_awburst,
    output reg                   m_awvalid,
    input  wire                  m_awready,
    output reg  [DATA_WIDTH-1:0] m_wdata,
    output reg  [3:0]            m_wstrb,
    output reg                   m_wlast,
    output reg                   m_wvalid,
    input  wire                  m_wready,
    input  wire [ID_WIDTH-1:0]   m_bid,
    input  wire [1:0]            m_bresp,
    input  wire                  m_bvalid,
    output reg                   m_bready,
    output reg  [ID_WIDTH-1:0]   m_arid,
    output reg  [ADDR_WIDTH-1:0] m_araddr,
    output reg  [7:0]            m_arlen,
    output reg  [2:0]            m_arsize,
    output reg  [1:0]            m_arburst,
    output reg                   m_arvalid,
    input  wire                  m_arready,
    input  wire [ID_WIDTH-1:0]   m_rid,
    input  wire [DATA_WIDTH-1:0] m_rdata,
    input  wire [1:0]            m_rresp,
    input  wire                  m_rlast,
    input  wire                  m_rvalid,
    output reg                   m_rready,

    // Snoop port. The opt-in NB cache acknowledges every request and
    // invalidates a matching clean resident line. Dirty-line writeback and
    // directory ownership remain a separate coherency contract.
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_valid,
    output wire                  snoop_ack,
    output wire                  snoop_hit
);

    // ---- Geometry (identical to l2_cache_caching) ----
    localparam OFFSET_BITS  = 5;
    localparam WORDS_PER_LN = LINE_BYTES / (DATA_WIDTH / 8);       // 8
    localparam WORD_BITS    = 3;
    localparam NUM_SETS     = SIZE_BYTES / (LINE_BYTES * WAYS);    // 512
    localparam INDEX_BITS   = $clog2(NUM_SETS);                    // 9
    localparam PA_WIDTH     = 29;
    localparam TAG_BITS     = PA_WIDTH - INDEX_BITS - OFFSET_BITS; // 15
    localparam WAY_BITS     = $clog2(WAYS);                        // 3
    localparam MSHR_BITS    = $clog2(N_MSHR);
    localparam ORD_BITS     = $clog2(ORD_DEPTH);
    localparam WB_BITS      = $clog2(WB_DEPTH);
    localparam LINE_W       = DATA_WIDTH * WORDS_PER_LN;           // 256

    // ---- Storage arrays (retention; cold-boot init only) ----
    reg [TAG_BITS-1:0]   tag_ram   [0:NUM_SETS-1][0:WAYS-1];
    reg                  valid_ram [0:NUM_SETS-1][0:WAYS-1];
    reg                  dirty_ram [0:NUM_SETS-1][0:WAYS-1];
    reg [DATA_WIDTH-1:0] data_ram  [0:NUM_SETS-1][0:WAYS-1][0:WORDS_PER_LN-1];
    reg [6:0]            plru_ram  [0:NUM_SETS-1];

    integer cb_s, cb_w;
    initial begin
        for (cb_s = 0; cb_s < NUM_SETS; cb_s = cb_s + 1) begin
            plru_ram[cb_s] = 7'd0;
            for (cb_w = 0; cb_w < WAYS; cb_w = cb_w + 1) begin
                valid_ram[cb_s][cb_w] = 1'b0;
                dirty_ram[cb_s][cb_w] = 1'b0;
            end
        end
    end

    // ---- MSHR file: one entry per distinct outstanding missing line ----
    reg                  mshr_valid  [0:N_MSHR-1];
    reg [23:0]           mshr_line   [0:N_MSHR-1]; // line addr [28:5]
    reg [INDEX_BITS-1:0] mshr_set    [0:N_MSHR-1];
    reg [TAG_BITS-1:0]   mshr_tag    [0:N_MSHR-1];
    reg [WAY_BITS-1:0]   mshr_way    [0:N_MSHR-1]; // reserved victim way
    reg                  mshr_issued [0:N_MSHR-1]; // refill launched
    reg                  mshr_filled [0:N_MSHR-1]; // line now in array
    reg                  mshr_error  [0:N_MSHR-1]; // downstream AXI error; no line install
    reg                  mshr_done   [0:N_MSHR-1]; // full downstream transaction complete
    reg                  mshr_evict  [0:N_MSHR-1]; // needs dirty writeback first
    reg [PA_WIDTH-1:0]   mshr_eaddr  [0:N_MSHR-1]; // evict address
    reg [WB_BITS-1:0]    mshr_wb_idx [0:N_MSHR-1]; // dirty victim buffer slot

    wire [INDEX_BITS-1:0] snoop_set = snoop_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   snoop_tag = snoop_addr[PA_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    reg                   snoop_way_hit;
    reg [WAY_BITS-1:0]    snoop_hitway;
    reg                   snoop_dirty_hit;
    reg                   snoop_mshr_match;
    reg                   snoop_wb_pending;
    reg [WB_BITS-1:0]     snoop_wb_idx;
    integer si, sm;
    always @(*) begin
        snoop_way_hit = 1'b0;
        snoop_hitway = {WAY_BITS{1'b0}};
        snoop_dirty_hit = 1'b0;
        snoop_mshr_match = 1'b0;
        for (si=0; si<WAYS; si=si+1) begin
            if (valid_ram[snoop_set][si] &&
                tag_ram[snoop_set][si] == snoop_tag) begin
                snoop_way_hit = 1'b1;
                snoop_hitway = si[WAY_BITS-1:0];
                if (dirty_ram[snoop_set][si]) snoop_dirty_hit = 1'b1;
            end
        end
        for (sm=0; sm<N_MSHR; sm=sm+1)
            if (mshr_valid[sm] && mshr_line[sm] == snoop_addr[28:5])
                snoop_mshr_match = 1'b1;
    end
    assign snoop_ack = snoop_valid;

    // Dirty victims are snapshotted at miss acceptance so replacement is
    // decoupled from the serial downstream AXI transaction.
    reg                  wb_valid [0:WB_DEPTH-1];
    reg [23:0]           wb_line  [0:WB_DEPTH-1];
    reg [LINE_W-1:0]     wb_data  [0:WB_DEPTH-1];

    // ---- Order queue: accepted requests, resolved out of order ----
    // st: 0=empty 1=wait(miss pending) 2=ready(can respond) 3=responding
    localparam OST_EMPTY=2'd0, OST_WAIT=2'd1, OST_READY=2'd2, OST_RESP=2'd3;
    reg [1:0]            ord_st    [0:ORD_DEPTH-1];
    reg                  ord_write [0:ORD_DEPTH-1];
    reg [ID_WIDTH-1:0]   ord_id    [0:ORD_DEPTH-1];
    reg [7:0]            ord_len   [0:ORD_DEPTH-1];
    reg [WORD_BITS-1:0]  ord_woff  [0:ORD_DEPTH-1]; // starting word offset
    reg [MSHR_BITS-1:0]  ord_mshr  [0:ORD_DEPTH-1]; // waiting MSHR (if OST_WAIT)
    reg [LINE_W-1:0]     ord_rbuf  [0:ORD_DEPTH-1]; // captured read line
    reg [7:0]            ord_age   [0:ORD_DEPTH-1]; // arrival sequence number
    reg [7:0]            ord_beat  [0:ORD_DEPTH-1]; // response beat counter
    reg [1:0]            ord_resp  [0:ORD_DEPTH-1]; // AXI resp code
    reg [7:0]            age_ctr;

    // Per-entry write payload (one line's worth of data + per-word strobes).
    reg [LINE_W-1:0]         ord_wdata  [0:ORD_DEPTH-1];
    reg [WORDS_PER_LN*4-1:0] ord_wstrb  [0:ORD_DEPTH-1];

    // ---- Pseudo-LRU helpers (same 7-bit tree as l2_cache_caching) ----
    function [2:0] get_plru_victim;
        input [6:0] p;
        begin
            if (p[0] == 1'b0) begin
                if (p[2] == 1'b0) get_plru_victim = (p[6]==1'b0)?3'd7:3'd6;
                else              get_plru_victim = (p[5]==1'b0)?3'd5:3'd4;
            end else begin
                if (p[1] == 1'b0) get_plru_victim = (p[4]==1'b0)?3'd3:3'd2;
                else              get_plru_victim = (p[3]==1'b0)?3'd1:3'd0;
            end
        end
    endfunction
    function [6:0] update_plru;
        input [6:0] p; input [2:0] w; reg [6:0] pn;
        begin
            pn = p; pn[0] = (w<4)?1'b1:1'b0;
            if (w<4) begin
                pn[1]=(w<2)?1'b1:1'b0;
                if (w<2) pn[3]=(w==0)?1'b1:1'b0; else pn[4]=(w==2)?1'b1:1'b0;
            end else begin
                pn[2]=(w<6)?1'b1:1'b0;
                if (w<6) pn[5]=(w==4)?1'b1:1'b0; else pn[6]=(w==6)?1'b1:1'b0;
            end
            update_plru = pn;
        end
    endfunction

    // ---- Accept sub-FSM ----
    // ACC_IDLE: look at AW (priority) or AR. On AR-hit/miss allocate an order
    // entry immediately. On AW, latch request + go ACC_WCOLLECT to gather the
    // W burst into a per-entry line buffer, then finalize the entry.
    localparam ACC_IDLE=2'd0, ACC_WCOLLECT=2'd1, ACC_WCOMMIT=2'd2;
    reg [1:0]         acc_state;
    reg [ORD_BITS-1:0] acc_wq;        // order slot being filled by a write
    reg [MSHR_BITS-1:0] acc_wmshr;    // its MSHR (if write miss)
    reg               acc_whit;       // write hit?
    reg [WAY_BITS-1:0] acc_wway;      // hit/alloc way for the write
    reg [INDEX_BITS-1:0] acc_wset;
    reg [2:0]         acc_wbeat;
    wire accepting_aw_w = (acc_state==ACC_WCOLLECT);

    // In ACC_IDLE we look at the incoming AW/AR; in WCOLLECT the lookup lines
    // are unused (address already latched).
    wire want_aw = (acc_state==ACC_IDLE) && s_awvalid;
    wire want_ar = (acc_state==ACC_IDLE) && !s_awvalid && s_arvalid;
    wire accepting_aw = want_aw;
    wire accepting_ar = want_ar;
    wire [PA_WIDTH-1:0]   acc_pa   = (accepting_aw ? s_awaddr[28:0] : s_araddr[28:0]);
    wire [INDEX_BITS-1:0] acc_set  = acc_pa[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   acc_tag  = acc_pa[PA_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    wire [WORD_BITS-1:0]  acc_woff = acc_pa[OFFSET_BITS-1:2];
    wire [23:0]           acc_line = acc_pa[28:5];

    reg [WAYS-1:0] acc_wayhit; reg [WAY_BITS-1:0] acc_hitway; reg acc_hit;
    reg [WAYS-1:0] acc_valids;
    integer hi;
    always @(*) begin
        acc_wayhit = {WAYS{1'b0}}; acc_hitway = {WAY_BITS{1'b0}};
        for (hi=0; hi<WAYS; hi=hi+1) begin
            acc_valids[hi] = valid_ram[acc_set][hi];
            if (valid_ram[acc_set][hi] && tag_ram[acc_set][hi]==acc_tag) begin
                acc_wayhit[hi] = 1'b1; acc_hitway = hi[WAY_BITS-1:0];
            end
        end
        acc_hit = |acc_wayhit;
    end

    // MSHR match for the accept line (secondary-miss merge target)
    reg mshr_match; reg [MSHR_BITS-1:0] mshr_match_idx;
    integer mm;
    always @(*) begin
        mshr_match = 1'b0; mshr_match_idx = {MSHR_BITS{1'b0}};
        for (mm=0; mm<N_MSHR; mm=mm+1)
            // A failed MSHR is terminal and must never accept a new secondary
            // waiter.  It remains allocated only long enough to resolve its
            // original order entries and then is reclaimed by MSHR FREE.
            if (mshr_valid[mm] && !mshr_error[mm] && mshr_line[mm]==acc_line) begin
                mshr_match = 1'b1; mshr_match_idx = mm[MSHR_BITS-1:0];
            end
    end

    // Free order-queue slot (lowest index)
    reg ord_free_v; reg [ORD_BITS-1:0] ord_free_i;
    integer of;
    always @(*) begin
        ord_free_v = 1'b0; ord_free_i = {ORD_BITS{1'b0}};
        for (of=ORD_DEPTH-1; of>=0; of=of-1)
            if (ord_st[of]==OST_EMPTY) begin ord_free_v=1'b1; ord_free_i=of[ORD_BITS-1:0]; end
    end

    // Free MSHR slot
    reg mshr_free_v; reg [MSHR_BITS-1:0] mshr_free_i;
    integer mf;
    always @(*) begin
        mshr_free_v = 1'b0; mshr_free_i = {MSHR_BITS{1'b0}};
        for (mf=N_MSHR-1; mf>=0; mf=mf-1)
            if (!mshr_valid[mf]) begin mshr_free_v=1'b1; mshr_free_i=mf[MSHR_BITS-1:0]; end
    end

    reg wb_free_v; reg [WB_BITS-1:0] wb_free_i;
    integer wf;
    always @(*) begin
        wb_free_v = 1'b0; wb_free_i = {WB_BITS{1'b0}};
        for (wf=WB_DEPTH-1; wf>=0; wf=wf-1)
            if (!wb_valid[wf]) begin wb_free_v=1'b1; wb_free_i=wf[WB_BITS-1:0]; end
    end

    wire snoop_dirty_accept = snoop_valid && snoop_way_hit &&
                               snoop_dirty_hit && !snoop_mshr_match &&
                               !snoop_wb_pending && wb_free_v;
    assign snoop_hit = snoop_valid && snoop_way_hit && !snoop_mshr_match &&
                       (!snoop_dirty_hit || snoop_dirty_accept);
    wire snoop_line_conflict = snoop_valid && snoop_way_hit &&
                                !snoop_mshr_match;

    // Ways already reserved by an in-flight MSHR for acc_set (avoid double-alloc)
    reg [WAYS-1:0] acc_reserved;
    integer rr;
    always @(*) begin
        acc_reserved = {WAYS{1'b0}};
        for (rr=0; rr<N_MSHR; rr=rr+1)
            if (mshr_valid[rr] && mshr_set[rr]==acc_set)
                acc_reserved[mshr_way[rr]] = 1'b1;
    end

    // Victim for a fresh miss: prefer invalid & not-reserved, else PLRU (if the
    // PLRU pick is reserved, linear-scan for any invalid/free way).
    reg [WAY_BITS-1:0] acc_victim; reg acc_victim_ok;
    reg [WAY_BITS-1:0] plru_v; integer vv;
    always @(*) begin
        plru_v = get_plru_victim(plru_ram[acc_set]);
        acc_victim = plru_v; acc_victim_ok = 1'b1;
        if (acc_reserved[plru_v] || (valid_ram[acc_set][plru_v] && 1'b0)) begin
            acc_victim_ok = 1'b0;
            for (vv=WAYS-1; vv>=0; vv=vv-1)
                if (!acc_reserved[vv]) begin acc_victim=vv[WAY_BITS-1:0]; acc_victim_ok=1'b1; end
        end
    end

    // Responder pick (only consulted when no burst is active): oldest (min age)
    // READY entry that has NO older non-empty entry of the SAME id still
    // in-flight. Preserves per-id ordering; allows OoO completion across ids.
    reg resp_v; reg [ORD_BITS-1:0] resp_i; reg [7:0] resp_best_age;
    integer pr, po; reg older_same_id;
    always @(*) begin
        resp_v = 1'b0; resp_i = {ORD_BITS{1'b0}}; resp_best_age = 8'hFF;
        for (pr=0; pr<ORD_DEPTH; pr=pr+1) begin
            if (ord_st[pr]==OST_READY) begin
                older_same_id = 1'b0;
                for (po=0; po<ORD_DEPTH; po=po+1)
                    if (po!=pr && ord_st[po]!=OST_EMPTY &&
                        ord_id[po]==ord_id[pr] && ord_age[po] < ord_age[pr])
                        older_same_id = 1'b1;
                if (!older_same_id && (!resp_v || ord_age[pr] < resp_best_age)) begin
                    resp_v = 1'b1; resp_i = pr[ORD_BITS-1:0]; resp_best_age = ord_age[pr];
                end
            end
        end
    end

    // Active responder (latched for the duration of a burst)
    reg                 rsp_active;
    reg [ORD_BITS-1:0]  rsp_idx;

    // Miss-engine serial FSM state
    localparam ME_IDLE=3'd0, ME_EVICT_AW=3'd1, ME_EVICT_W=3'd2, ME_EVICT_B=3'd3,
               ME_REFILL_AR=3'd4, ME_REFILL_R=3'd5;
    reg [2:0]           me_state;
    reg [MSHR_BITS-1:0] me_idx;      // MSHR being serviced
    reg [2:0]           me_cnt;      // beat counter (evict/refill)
    reg [LINE_W-1:0]    me_linebuf;  // assembled refill line
    reg                 me_is_snoop_wb;

    // Pick an MSHR needing service (valid, not issued, not filled)
    reg me_pick_v; reg [MSHR_BITS-1:0] me_pick_i;
    integer mp;
    always @(*) begin
        me_pick_v = 1'b0; me_pick_i = {MSHR_BITS{1'b0}};
        for (mp=N_MSHR-1; mp>=0; mp=mp-1)
            if (mshr_valid[mp] && !mshr_issued[mp] && !mshr_filled[mp]) begin
                me_pick_v = 1'b1; me_pick_i = mp[MSHR_BITS-1:0];
            end
    end

    // Pick the OLDEST order entry that is waiting on a now-filled/failed MSHR. Resolved
    // one-per-cycle in age order so a write-waiter merges before any younger
    // same-line read-waiter captures (program-order correctness on a line).
    reg fill_v; reg [ORD_BITS-1:0] fill_i; reg [7:0] fill_best_age;
    integer fp;
    always @(*) begin
        fill_v = 1'b0; fill_i = {ORD_BITS{1'b0}}; fill_best_age = 8'hFF;
        for (fp=0; fp<ORD_DEPTH; fp=fp+1)
            if (ord_st[fp]==OST_WAIT && mshr_valid[ord_mshr[fp]] &&
                mshr_done[ord_mshr[fp]])
                if (!fill_v || ord_age[fp] < fill_best_age) begin
                    fill_v = 1'b1; fill_i = fp[ORD_BITS-1:0]; fill_best_age = ord_age[fp];
                end
    end

    // ---- Combinational: can we accept a new upstream request this cycle? ----
    // Need a free order slot; a miss additionally needs (merge target) OR
    // (free MSHR + a non-reserved victim way).
    wire acc_miss_needs_mshr = !acc_hit && !mshr_match;
    wire acc_miss_needs_wb = acc_miss_needs_mshr &&
                             valid_ram[acc_set][acc_victim] &&
                             dirty_ram[acc_set][acc_victim];
    wire acc_can_alloc = ord_free_v &&
                         (acc_hit || mshr_match ||
                          (mshr_free_v && acc_victim_ok &&
                           (!acc_miss_needs_wb || wb_free_v))) &&
                         !snoop_dirty_accept && !snoop_line_conflict;

    // An accept that attaches a NEW waiter to an existing MSHR this cycle (used
    // to veto a same-cycle free of that MSHR). Covers AR-accept and the AW
    // handshake (write waiter is latched at AW). s_arready/s_awready already
    // fold in acc_can_alloc + ACC_IDLE.
    wire acc_merge_now = mshr_match &&
                         ((want_ar && s_arready) || (want_aw && s_awready));
    wire [MSHR_BITS-1:0] acc_merge_idx = mshr_match_idx;

    // ---- Combinational output drives ----
    integer wq;
    always @(*) begin
        // slave defaults
        s_awready = 1'b0; s_wready = 1'b0; s_arready = 1'b0;
        s_bvalid  = 1'b0; s_bid = ord_id[rsp_idx]; s_bresp = ord_resp[rsp_idx];
        s_rvalid  = 1'b0; s_rid = ord_id[rsp_idx]; s_rresp = ord_resp[rsp_idx];
        s_rlast   = 1'b0;
        s_rdata   = ord_rbuf[rsp_idx][ (ord_woff[rsp_idx]+ord_beat[rsp_idx])*DATA_WIDTH +: DATA_WIDTH ];

        // Accept AR/AW only in ACC_IDLE, and only when allocation can succeed
        // (else backpressure). AW has priority over AR (matches blocking impl).
        if (acc_state==ACC_IDLE && acc_can_alloc) begin
            if (want_aw)      s_awready = 1'b1;
            else if (want_ar) s_arready = 1'b1;
        end
        // W beats are consumed while collecting a write burst.
        s_wready = accepting_aw_w;

        // master defaults
        m_awvalid=1'b0; m_awid=4'd0;
        m_awaddr = me_is_snoop_wb ?
                   {3'b000, wb_line[snoop_wb_idx], 5'b00000} :
                   mshr_eaddr[me_idx];
        m_awlen=8'd7;
        m_awsize=3'b010; m_awburst=2'b01;
        m_wvalid=1'b0;
        m_wdata = me_is_snoop_wb ?
                  wb_data[snoop_wb_idx][me_cnt*DATA_WIDTH +: DATA_WIDTH] :
                  mshr_evict[me_idx] ?
                  wb_data[mshr_wb_idx[me_idx]][me_cnt*DATA_WIDTH +: DATA_WIDTH] :
                  data_ram[mshr_set[me_idx]][mshr_way[me_idx]][me_cnt];
        m_wstrb=4'hF; m_wlast=(me_cnt==3'd7);
        m_bready=1'b0;
        m_arvalid=1'b0; m_arid=4'd0;
        m_araddr={3'b000, mshr_line[me_idx], 5'b00000}; m_arlen=8'd7;
        m_arsize=3'b010; m_arburst=2'b01;
        m_rready=1'b0;

        case (me_state)
            ME_EVICT_AW:  m_awvalid = 1'b1;
            ME_EVICT_W:   m_wvalid  = 1'b1;
            ME_EVICT_B:   m_bready  = 1'b1;
            ME_REFILL_AR: m_arvalid = 1'b1;
            ME_REFILL_R:  m_rready  = 1'b1;
            default: ;
        endcase

        // Response burst drive (read only; writes drive s_bvalid)
        if (rsp_active) begin
            if (ord_write[rsp_idx]) s_bvalid = 1'b1;
            else begin
                s_rvalid = 1'b1;
                s_rlast  = (ord_beat[rsp_idx] == ord_len[rsp_idx]);
            end
        end
    end

    // =========================================================================
    // Sequential: accept stage, miss engine, responder (all concurrent)
    // =========================================================================
    integer k, mm2, fk, fj;
    reg     mshr_refd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_state <= ACC_IDLE; acc_wbeat <= 3'd0; age_ctr <= 8'd0;
            me_state <= ME_IDLE; me_idx <= 0; me_cnt <= 3'd0; me_linebuf <= 0;
            me_is_snoop_wb <= 1'b0;
            rsp_active <= 1'b0; rsp_idx <= 0;
            snoop_wb_pending <= 1'b0;
            snoop_wb_idx <= {WB_BITS{1'b0}};
            for (k=0; k<ORD_DEPTH; k=k+1) begin ord_st[k] <= OST_EMPTY; ord_beat[k] <= 8'd0; end
            for (k=0; k<N_MSHR; k=k+1) begin
                mshr_valid[k] <= 1'b0; mshr_issued[k] <= 1'b0;
                mshr_filled[k] <= 1'b0; mshr_error[k] <= 1'b0; mshr_done[k] <= 1'b0;
                mshr_evict[k] <= 1'b0;
                mshr_wb_idx[k] <= {WB_BITS{1'b0}};
            end
            for (k=0; k<WB_DEPTH; k=k+1) wb_valid[k] <= 1'b0;
            // retention arrays: not cleared (see l2_cache_caching rationale)
        end else begin
            // Snapshot a dirty snooped line before invalidating it. The miss
            // engine drains this entry through the same AXI AW/W/B path used
            // by dirty replacement victims.
            if (snoop_dirty_accept) begin
                snoop_wb_pending <= 1'b1;
                snoop_wb_idx <= wb_free_i;
                wb_valid[wb_free_i] <= 1'b1;
                wb_line[wb_free_i] <= {tag_ram[snoop_set][snoop_hitway],
                                        snoop_set};
                for (k=0; k<WORDS_PER_LN; k=k+1)
                    wb_data[wb_free_i][k*DATA_WIDTH +: DATA_WIDTH] <=
                        data_ram[snoop_set][snoop_hitway][k];
                valid_ram[snoop_set][snoop_hitway] <= 1'b0;
                dirty_ram[snoop_set][snoop_hitway] <= 1'b0;
            end
            // A clean snoop can invalidate immediately.
            if (snoop_valid && snoop_way_hit && !snoop_dirty_hit &&
                !snoop_mshr_match) begin
                valid_ram[snoop_set][snoop_hitway] <= 1'b0;
                dirty_ram[snoop_set][snoop_hitway] <= 1'b0;
            end
            // ---------------------------------------------------------------
            // (A) ACCEPT STAGE
            // ---------------------------------------------------------------
            if (acc_state==ACC_IDLE) begin
                if (want_ar && acc_can_alloc && s_arready) begin
                    // allocate read order entry. PRIORITY: an existing MSHR for
                    // this line wins over a plain hit, so the request queues
                    // BEHIND older same-line waiters (program order). Only a true
                    // hit with no owning MSHR captures immediately.
                    ord_st[ord_free_i]    <= (mshr_match || !acc_hit) ? OST_WAIT : OST_READY;
                    ord_write[ord_free_i] <= 1'b0;
                    ord_id[ord_free_i]    <= s_arid;
                    ord_len[ord_free_i]   <= s_arlen;
                    ord_woff[ord_free_i]  <= acc_woff;
                    ord_age[ord_free_i]   <= age_ctr;
                    ord_beat[ord_free_i]  <= 8'd0;
                    ord_resp[ord_free_i]  <= 2'b00;
                    age_ctr <= age_ctr + 1'b1;
                    if (mshr_match) begin
                        ord_mshr[ord_free_i] <= mshr_match_idx;
                    end else if (acc_hit) begin
                        // capture the whole line now (race-free respond)
                        for (k=0; k<WORDS_PER_LN; k=k+1)
                            ord_rbuf[ord_free_i][k*DATA_WIDTH +: DATA_WIDTH] <= data_ram[acc_set][acc_hitway][k];
                        plru_ram[acc_set] <= update_plru(plru_ram[acc_set], acc_hitway);
                    end else begin
                        // new MSHR
                        ord_mshr[ord_free_i]      <= mshr_free_i;
                        mshr_valid[mshr_free_i]   <= 1'b1;
                        mshr_line[mshr_free_i]    <= acc_line;
                        mshr_set[mshr_free_i]     <= acc_set;
                        mshr_tag[mshr_free_i]     <= acc_tag;
                        mshr_way[mshr_free_i]     <= acc_victim;
                        mshr_issued[mshr_free_i]  <= 1'b0;
                        mshr_filled[mshr_free_i]  <= 1'b0;
                        mshr_error[mshr_free_i]   <= 1'b0;
                        mshr_done[mshr_free_i]    <= 1'b0;
                        mshr_evict[mshr_free_i]   <= valid_ram[acc_set][acc_victim] && dirty_ram[acc_set][acc_victim];
                        mshr_eaddr[mshr_free_i]   <= {3'b000, tag_ram[acc_set][acc_victim], acc_set, {OFFSET_BITS{1'b0}}};
                        if (valid_ram[acc_set][acc_victim] && dirty_ram[acc_set][acc_victim]) begin
                            mshr_wb_idx[mshr_free_i] <= wb_free_i;
                            wb_valid[wb_free_i] <= 1'b1;
                            wb_line[wb_free_i] <= {tag_ram[acc_set][acc_victim], acc_set};
                            for (k=0; k<WORDS_PER_LN; k=k+1)
                                wb_data[wb_free_i][k*DATA_WIDTH +: DATA_WIDTH] <=
                                    data_ram[acc_set][acc_victim][k];
                        end
                    end
                end else if (want_aw && acc_can_alloc && s_awready) begin
                    // latch write, go collect W beats. Same priority as reads:
                    // an owning MSHR wins over a plain hit (queue behind older
                    // same-line waiters, merge at fill time).
                    acc_wq    <= ord_free_i;
                    acc_whit  <= acc_hit && !mshr_match;
                    acc_wway  <= (acc_hit && !mshr_match) ? acc_hitway : acc_victim;
                    acc_wset  <= acc_set;
                    acc_wbeat <= 3'd0;
                    ord_st[ord_free_i]    <= OST_WAIT; // finalized at wlast
                    ord_write[ord_free_i] <= 1'b1;
                    ord_id[ord_free_i]    <= s_awid;
                    ord_len[ord_free_i]   <= s_awlen;
                    ord_woff[ord_free_i]  <= acc_woff;
                    ord_age[ord_free_i]   <= age_ctr;
                    ord_resp[ord_free_i]  <= 2'b00;
                    ord_wstrb[ord_free_i] <= {(WORDS_PER_LN*4){1'b0}};
                    age_ctr <= age_ctr + 1'b1;
                    if (mshr_match) begin
                        acc_wmshr <= mshr_match_idx; ord_mshr[ord_free_i] <= mshr_match_idx;
                    end else if (!acc_hit) begin
                        acc_wmshr <= mshr_free_i; ord_mshr[ord_free_i] <= mshr_free_i;
                        mshr_valid[mshr_free_i]  <= 1'b1;
                        mshr_line[mshr_free_i]   <= acc_line;
                        mshr_set[mshr_free_i]    <= acc_set;
                        mshr_tag[mshr_free_i]    <= acc_tag;
                        mshr_way[mshr_free_i]    <= acc_victim;
                        mshr_issued[mshr_free_i] <= 1'b0;
                        mshr_filled[mshr_free_i] <= 1'b0;
                        mshr_error[mshr_free_i]  <= 1'b0;
                        mshr_done[mshr_free_i]   <= 1'b0;
                        mshr_evict[mshr_free_i]  <= valid_ram[acc_set][acc_victim] && dirty_ram[acc_set][acc_victim];
                        mshr_eaddr[mshr_free_i]  <= {3'b000, tag_ram[acc_set][acc_victim], acc_set, {OFFSET_BITS{1'b0}}};
                        if (valid_ram[acc_set][acc_victim] && dirty_ram[acc_set][acc_victim]) begin
                            mshr_wb_idx[mshr_free_i] <= wb_free_i;
                            wb_valid[wb_free_i] <= 1'b1;
                            wb_line[wb_free_i] <= {tag_ram[acc_set][acc_victim], acc_set};
                            for (k=0; k<WORDS_PER_LN; k=k+1)
                                wb_data[wb_free_i][k*DATA_WIDTH +: DATA_WIDTH] <=
                                    data_ram[acc_set][acc_victim][k];
                        end
                    end
                    acc_state <= ACC_WCOLLECT;
                end
            end else if (acc_state==ACC_WCOLLECT) begin
                if (s_wvalid && s_wready) begin
                    // store this beat into the entry's write buffer at woff+beat
                    ord_wdata[acc_wq][ (ord_woff[acc_wq]+acc_wbeat)*DATA_WIDTH +: DATA_WIDTH ] <= s_wdata;
                    ord_wstrb[acc_wq][ (ord_woff[acc_wq]+acc_wbeat)*4 +: 4 ] <= s_wstrb;
                    acc_wbeat <= acc_wbeat + 1'b1;
                    if (s_wlast) begin
                        // W buffer just written this cycle (NBA). Defer the
                        // hit-merge one cycle so the buffer has settled.
                        acc_state <= acc_whit ? ACC_WCOMMIT : ACC_IDLE;
                        // write miss stays OST_WAIT; merged at fill time.
                    end
                end
            end else if (acc_state==ACC_WCOMMIT) begin
                // merge the settled write buffer into the array (in-order
                // serialization point for a write hit).
                for (k=0; k<WORDS_PER_LN; k=k+1) begin
                    if (ord_wstrb[acc_wq][k*4+0]) data_ram[acc_wset][acc_wway][k][7:0]   <= ord_wdata[acc_wq][k*DATA_WIDTH+0  +:8];
                    if (ord_wstrb[acc_wq][k*4+1]) data_ram[acc_wset][acc_wway][k][15:8]  <= ord_wdata[acc_wq][k*DATA_WIDTH+8  +:8];
                    if (ord_wstrb[acc_wq][k*4+2]) data_ram[acc_wset][acc_wway][k][23:16] <= ord_wdata[acc_wq][k*DATA_WIDTH+16 +:8];
                    if (ord_wstrb[acc_wq][k*4+3]) data_ram[acc_wset][acc_wway][k][31:24] <= ord_wdata[acc_wq][k*DATA_WIDTH+24 +:8];
                end
                dirty_ram[acc_wset][acc_wway] <= 1'b1;
                plru_ram[acc_wset] <= update_plru(plru_ram[acc_wset], acc_wway);
                ord_st[acc_wq] <= OST_READY;
                acc_state <= ACC_IDLE;
            end

            // ---------------------------------------------------------------
            // (B) MISS ENGINE — serial; one master transaction at a time
            // ---------------------------------------------------------------
            case (me_state)
                ME_IDLE: begin
                    // A dirty snoop must reach memory before a younger miss can
                    // refill the invalidated line; otherwise the refill could
                    // observe the pre-writeback backing value.
                    if (snoop_wb_pending) begin
                        me_is_snoop_wb <= 1'b1;
                        me_cnt <= 3'd0;
                        me_state <= ME_EVICT_AW;
                    end else if (me_pick_v) begin
                        me_idx <= me_pick_i;
                        me_is_snoop_wb <= 1'b0;
                        mshr_issued[me_pick_i] <= 1'b1;
                        me_cnt <= 3'd0;
                        if (mshr_evict[me_pick_i]) me_state <= ME_EVICT_AW;
                        else                       me_state <= ME_REFILL_AR;
                    end
                end
                ME_EVICT_AW: if (m_awready) begin me_cnt <= 3'd0; me_state <= ME_EVICT_W; end
                ME_EVICT_W:  if (m_wready) begin
                                 if (me_cnt==3'd7) me_state <= ME_EVICT_B;
                                 else me_cnt <= me_cnt + 1'b1;
                             end
                ME_EVICT_B:  if (m_bvalid) begin
                                 if (me_is_snoop_wb) begin
                                     wb_valid[snoop_wb_idx] <= 1'b0;
                                     snoop_wb_pending <= 1'b0;
                                     me_is_snoop_wb <= 1'b0;
                                     me_state <= ME_IDLE;
                                 end else if (m_bresp != 2'b00) begin
                                     // The victim reached the downstream
                                     // fabric but was not accepted.  Do not
                                     // launch a refill whose response would
                                     // otherwise make the failed request look
                                     // successful.
                                     wb_valid[mshr_wb_idx[me_idx]] <= 1'b0;
                                     mshr_error[me_idx] <= 1'b1;
                                     mshr_done[me_idx] <= 1'b1;
                                     me_state <= ME_IDLE;
                                 end else begin
                                     wb_valid[mshr_wb_idx[me_idx]] <= 1'b0;
                                     me_state <= ME_REFILL_AR;
                                 end
                             end
                ME_REFILL_AR: if (m_arready) begin me_cnt <= 3'd0; me_state <= ME_REFILL_R; end
                ME_REFILL_R: if (m_rvalid) begin
                                 // Continue consuming the burst after an error
                                 // so a single-outstanding downstream fabric is
                                 // never left wedged.  Error responses never
                                 // install any part of the line.
                                 if (m_rresp != 2'b00)
                                     mshr_error[me_idx] <= 1'b1;
                                 if (!mshr_error[me_idx] && m_rresp == 2'b00)
                                     data_ram[mshr_set[me_idx]][mshr_way[me_idx]][me_cnt] <= m_rdata;
                                 me_linebuf[me_cnt*DATA_WIDTH +: DATA_WIDTH] <= m_rdata;
                                 if (m_rlast || me_cnt==3'd7) begin
                                     if (mshr_error[me_idx] || m_rresp != 2'b00) begin
                                         // A failed refill must not expose a
                                         // partially updated cache line.
                                         mshr_error[me_idx] <= 1'b1;
                                         mshr_done[me_idx] <= 1'b1;
                                     end else begin
                                         tag_ram[mshr_set[me_idx]][mshr_way[me_idx]]   <= mshr_tag[me_idx];
                                         valid_ram[mshr_set[me_idx]][mshr_way[me_idx]] <= 1'b1;
                                         dirty_ram[mshr_set[me_idx]][mshr_way[me_idx]] <= 1'b0;
                                         plru_ram[mshr_set[me_idx]] <= update_plru(plru_ram[mshr_set[me_idx]], mshr_way[me_idx]);
                                         mshr_filled[me_idx] <= 1'b1;
                                         mshr_done[me_idx] <= 1'b1;
                                     end
                                     me_state <= ME_IDLE;
                                 end else me_cnt <= me_cnt + 1'b1;
                             end
                default: me_state <= ME_IDLE;
            endcase

            // ---------------------------------------------------------------
            // (C) FILL SERVICING — when an MSHR is filled, resolve its waiters
            // in arrival order: write-miss waiters merge into the (now present)
            // line + set dirty; read-miss waiters capture the line. One waiter
            // per cycle keeps array writes single-ported and ordered.
            // ---------------------------------------------------------------
            if (fill_v) begin : FILLSVC
                reg [INDEX_BITS-1:0] fs; reg [WAY_BITS-1:0] fw;
                fs = mshr_set[ord_mshr[fill_i]]; fw = mshr_way[ord_mshr[fill_i]];
                if (mshr_error[ord_mshr[fill_i]]) begin
                    // All primary and secondary waiters observe the same
                    // downstream failure, while preserving normal response
                    // ordering and allowing the MSHR to be reclaimed.
                    ord_resp[fill_i] <= 2'b10; // AXI SLVERR
                    ord_rbuf[fill_i] <= {LINE_W{1'b0}};
                    ord_st[fill_i] <= OST_READY;
                end else if (ord_write[fill_i]) begin
                    // merge write payload into the filled line (byte strobes)
                    for (mm2=0; mm2<WORDS_PER_LN; mm2=mm2+1) begin
                        if (ord_wstrb[fill_i][mm2*4+0]) data_ram[fs][fw][mm2][7:0]   <= ord_wdata[fill_i][mm2*DATA_WIDTH+0 +:8];
                        if (ord_wstrb[fill_i][mm2*4+1]) data_ram[fs][fw][mm2][15:8]  <= ord_wdata[fill_i][mm2*DATA_WIDTH+8 +:8];
                        if (ord_wstrb[fill_i][mm2*4+2]) data_ram[fs][fw][mm2][23:16] <= ord_wdata[fill_i][mm2*DATA_WIDTH+16+:8];
                        if (ord_wstrb[fill_i][mm2*4+3]) data_ram[fs][fw][mm2][31:24] <= ord_wdata[fill_i][mm2*DATA_WIDTH+24+:8];
                    end
                    dirty_ram[fs][fw] <= 1'b1;
                    ord_st[fill_i] <= OST_READY;
                end else begin
                    // read-waiter: capture the (now merged, if any older write ran)
                    // line into the entry buffer.
                    for (mm2=0; mm2<WORDS_PER_LN; mm2=mm2+1)
                        ord_rbuf[fill_i][mm2*DATA_WIDTH +: DATA_WIDTH] <= data_ram[fs][fw][mm2];
                    ord_st[fill_i] <= OST_READY;
                end
            end

            // ---------------------------------------------------------------
            // (D) RESPONDER — OoO across ids, in-order per id. Reads only
            // per-entry buffers (array-race-free).
            // ---------------------------------------------------------------
            if (!rsp_active) begin
                if (resp_v) begin
                    rsp_active <= 1'b1;
                    rsp_idx    <= resp_i;
                    ord_st[resp_i] <= OST_RESP;
                    ord_beat[resp_i] <= 8'd0;
                end
            end else begin
                if (ord_write[rsp_idx]) begin
                    if (s_bready) begin
                        rsp_active <= 1'b0;
                        ord_st[rsp_idx] <= OST_EMPTY;
                    end
                end else begin
                    if (s_rready) begin
                        if (ord_beat[rsp_idx] == ord_len[rsp_idx]) begin
                            rsp_active <= 1'b0;
                            ord_st[rsp_idx] <= OST_EMPTY;
                        end else begin
                            ord_beat[rsp_idx] <= ord_beat[rsp_idx] + 1'b1;
                        end
                    end
                end
            end

            // ---------------------------------------------------------------
            // (E) MSHR FREE — once no order entry still references it and it is
            // filled, release the slot for reuse.
            // ---------------------------------------------------------------
            for (fk=0; fk<N_MSHR; fk=fk+1) begin
                if (mshr_valid[fk] && mshr_done[fk]) begin
                    mshr_refd = 1'b0;
                    for (fj=0; fj<ORD_DEPTH; fj=fj+1)
                        if (ord_st[fj]!=OST_EMPTY && ord_mshr[fj]==fk[MSHR_BITS-1:0] &&
                            (ord_st[fj]==OST_WAIT))
                            mshr_refd = 1'b1;
                    // Also: an accept merging onto this MSHR THIS cycle adds a
                    // waiter that block-A writes via NBA (invisible above); do
                    // not free it, or that waiter would be stranded.
                    if (acc_merge_now && acc_merge_idx==fk[MSHR_BITS-1:0])
                        mshr_refd = 1'b1;
                    if (!mshr_refd) begin
                        mshr_valid[fk]  <= 1'b0;
                        mshr_issued[fk] <= 1'b0;
                        mshr_filled[fk] <= 1'b0;
                        mshr_error[fk]  <= 1'b0;
                        mshr_done[fk]   <= 1'b0;
                        mshr_evict[fk]  <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
