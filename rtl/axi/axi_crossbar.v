// =============================================================================
// File Name: axi_crossbar.v
// Design:    AXI4 Multi-Outstanding M x N Crossbar (Phase C.3)
// Author:    Antigravity — Phase C.3
// Description:
//   True crossbar replacing the legacy single-outstanding arbiter cascade.
//   - N_M master ports, N_S mapped slave ports + 1 internal DECERR slave.
//   - Per-master address decode -> target slave index.
//   - Per-slave arbiter: QoS-priority, round-robin tie-break.
//   - Per-slave outstanding FIFO {master_idx, id} (depth N_OT) for in-order
//     response routing (real slaves respond in order per ID).
//   - Concurrent cross-slave transactions: masters hitting DIFFERENT slaves
//     proceed in parallel (the key win over the old shared trunk).
//   Flat-vector ports so the pure-Verilog soc_fabric wrapper can map easily.
//
//   Realized concurrency note: end-to-end same-slave depth is capped at 1 by
//   today's single-outstanding slaves (L2/APB/flash/DDR placeholder); the
//   crossbar still ACCEPTS up to N_OT at its boundary (ready for a future
//   MSHR L1 / non-blocking L2). Cross-slave concurrency is realized now.
//
//   S3 = DDR: 128MB physical window (SOC_DDR_BASE/SOC_DDR_SIZE) backed today
//   only by a behavioral capacity placeholder (rtl/perips/axi_ddr_behavioral.v).
//   No DDR3 timing/refresh/PHY realism. See docs/block_specs/ddr3_spec.md.
//   Decoded via an explicit range compare (not the 256MB mask used for
//   SRAM/APB/FLASH) since SOC_DDR_BASE is only 128MB-aligned.
// =============================================================================

`include "soc_config.vh"

module axi_crossbar #(
    parameter integer N_M   = 5,   // masters: 0=I$,1=D$,2=DMA,3=jtag,4=ext
    parameter integer N_S   = 5,   // mapped slaves: 0=SRAM,1=APB,2=FLASH,3=DDR,4=Boot ROM
    parameter integer N_OT  = 4,   // per-slave outstanding depth
    parameter integer IDW   = 4,
    parameter integer AW    = 32,
    parameter integer DW    = 32,
    parameter integer QW    = 4
) (
    input  wire clk,
    input  wire rst_n,

    // Per-master enable mask (drive 0 to tie a master off, e.g. ext disabled)
    input  wire [N_M-1:0]        m_enable,

    // ---- Master-side AXI (flattened: index i occupies [i*W +: W]) ----
    // Write address
    input  wire [N_M*IDW-1:0]    m_awid,
    input  wire [N_M*AW-1:0]     m_awaddr,
    input  wire [N_M*8-1:0]      m_awlen,
    input  wire [N_M*3-1:0]      m_awsize,
    input  wire [N_M*2-1:0]      m_awburst,
    input  wire [N_M*2-1:0]      m_awlock,
    input  wire [N_M*4-1:0]      m_awcache,
    input  wire [N_M*3-1:0]      m_awprot,
    input  wire [N_M*QW-1:0]     m_awqos,
    input  wire [N_M-1:0]        m_awvalid,
    output wire [N_M-1:0]        m_awready,
    // Write data
    input  wire [N_M*DW-1:0]     m_wdata,
    input  wire [N_M*4-1:0]      m_wstrb,
    input  wire [N_M-1:0]        m_wlast,
    input  wire [N_M-1:0]        m_wvalid,
    output wire [N_M-1:0]        m_wready,
    // Write response
    output wire [N_M*IDW-1:0]    m_bid,
    output wire [N_M*2-1:0]      m_bresp,
    output wire [N_M-1:0]        m_bvalid,
    input  wire [N_M-1:0]        m_bready,
    // Read address
    input  wire [N_M*IDW-1:0]    m_arid,
    input  wire [N_M*AW-1:0]     m_araddr,
    input  wire [N_M*8-1:0]      m_arlen,
    input  wire [N_M*3-1:0]      m_arsize,
    input  wire [N_M*2-1:0]      m_arburst,
    input  wire [N_M*2-1:0]      m_arlock,
    input  wire [N_M*4-1:0]      m_arcache,
    input  wire [N_M*3-1:0]      m_arprot,
    input  wire [N_M*QW-1:0]     m_arqos,
    input  wire [N_M-1:0]        m_arvalid,
    output wire [N_M-1:0]        m_arready,
    // Read data
    output wire [N_M*IDW-1:0]    m_rid,
    output wire [N_M*DW-1:0]     m_rdata,
    output wire [N_M*2-1:0]      m_rresp,
    output wire [N_M-1:0]        m_rlast,
    output wire [N_M-1:0]        m_rvalid,
    input  wire [N_M-1:0]        m_rready,

    // ---- Slave-side AXI (flattened over N_S mapped slaves) ----
    output wire [N_S*IDW-1:0]    s_awid,
    output wire [N_S*AW-1:0]     s_awaddr,
    output wire [N_S*8-1:0]      s_awlen,
    output wire [N_S*3-1:0]      s_awsize,
    output wire [N_S*2-1:0]      s_awburst,
    output wire [N_S*2-1:0]      s_awlock,
    output wire [N_S*4-1:0]      s_awcache,
    output wire [N_S*3-1:0]      s_awprot,
    output wire [N_S-1:0]        s_awvalid,
    input  wire [N_S-1:0]        s_awready,
    output wire [N_S*DW-1:0]     s_wdata,
    output wire [N_S*4-1:0]      s_wstrb,
    output wire [N_S-1:0]        s_wlast,
    output wire [N_S-1:0]        s_wvalid,
    input  wire [N_S-1:0]        s_wready,
    input  wire [N_S*IDW-1:0]    s_bid,
    input  wire [N_S*2-1:0]      s_bresp,
    input  wire [N_S-1:0]        s_bvalid,
    output wire [N_S-1:0]        s_bready,
    output wire [N_S*IDW-1:0]    s_arid,
    output wire [N_S*AW-1:0]     s_araddr,
    output wire [N_S*8-1:0]      s_arlen,
    output wire [N_S*3-1:0]      s_arsize,
    output wire [N_S*2-1:0]      s_arburst,
    output wire [N_S*2-1:0]      s_arlock,
    output wire [N_S*4-1:0]      s_arcache,
    output wire [N_S*3-1:0]      s_arprot,
    output wire [N_S-1:0]        s_arvalid,
    input  wire [N_S-1:0]        s_arready,
    input  wire [N_S*IDW-1:0]    s_rid,
    input  wire [N_S*DW-1:0]     s_rdata,
    input  wire [N_S*2-1:0]      s_rresp,
    input  wire [N_S-1:0]        s_rlast,
    input  wire [N_S-1:0]        s_rvalid,
    output wire [N_S-1:0]        s_rready
);

    // ------------------------------------------------------------------
    // Local constants
    // ------------------------------------------------------------------
    localparam integer S_ALL   = N_S + 1;      // + DECERR virtual slave
    localparam integer DEC      = N_S;          // DECERR slave index
    localparam integer MIDW    = (N_M <= 1) ? 1 : $clog2(N_M);

    genvar gm, gs;
    integer i;

    // ------------------------------------------------------------------
    // Un-flatten master request fields into arrays
    // ------------------------------------------------------------------
    wire [IDW-1:0] aw_id  [0:N_M-1];
    wire [AW-1:0]  aw_addr[0:N_M-1];
    wire [7:0]     aw_len [0:N_M-1];
    wire [2:0]     aw_size[0:N_M-1];
    wire [1:0]     aw_bst [0:N_M-1];
    wire [1:0]     aw_lk  [0:N_M-1];
    wire [3:0]     aw_ca  [0:N_M-1];
    wire [2:0]     aw_pr  [0:N_M-1];
    wire [QW-1:0]  aw_qos [0:N_M-1];
    wire [IDW-1:0] ar_id  [0:N_M-1];
    wire [AW-1:0]  ar_addr[0:N_M-1];
    wire [7:0]     ar_len [0:N_M-1];
    wire [2:0]     ar_size[0:N_M-1];
    wire [1:0]     ar_bst [0:N_M-1];
    wire [1:0]     ar_lk  [0:N_M-1];
    wire [3:0]     ar_ca  [0:N_M-1];
    wire [2:0]     ar_pr  [0:N_M-1];
    wire [QW-1:0]  ar_qos [0:N_M-1];

    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_unflat
        assign aw_id[gm]   = m_awid  [gm*IDW +: IDW];
        assign aw_addr[gm] = m_awaddr[gm*AW  +: AW];
        assign aw_len[gm]  = m_awlen [gm*8   +: 8];
        assign aw_size[gm] = m_awsize[gm*3   +: 3];
        assign aw_bst[gm]  = m_awburst[gm*2  +: 2];
        assign aw_lk[gm]   = m_awlock[gm*2   +: 2];
        assign aw_ca[gm]   = m_awcache[gm*4  +: 4];
        assign aw_pr[gm]   = m_awprot[gm*3   +: 3];
        assign aw_qos[gm]  = m_awqos [gm*QW  +: QW];
        assign ar_id[gm]   = m_arid  [gm*IDW +: IDW];
        assign ar_addr[gm] = m_araddr[gm*AW  +: AW];
        assign ar_len[gm]  = m_arlen [gm*8   +: 8];
        assign ar_size[gm] = m_arsize[gm*3   +: 3];
        assign ar_bst[gm]  = m_arburst[gm*2  +: 2];
        assign ar_lk[gm]   = m_arlock[gm*2   +: 2];
        assign ar_ca[gm]   = m_arcache[gm*4  +: 4];
        assign ar_pr[gm]   = m_arprot[gm*3   +: 3];
        assign ar_qos[gm]  = m_arqos [gm*QW  +: QW];
    end endgenerate

    // ------------------------------------------------------------------
    // Per-master address decode -> target slave index (0..N_S, N_S=DECERR)
    // Mirrors legacy axi_decoder_1x3 exactly.
    // ------------------------------------------------------------------
    function [3:0] decode_slave;
        input [AW-1:0] a;
        begin
            if (((a & `SOC_64KB_REGION_MASK) == `SOC_BOOT_BASE) ||
                ((a & `SOC_64KB_REGION_MASK) == `SOC_SRAM_ALIAS_BASE))
                decode_slave = 4'd0;                 // S0 SRAM
            else if ((a & `SOC_64KB_REGION_MASK) == `SOC_APB_BASE)
                decode_slave = 4'd1;                 // S1 APB
            // Boot ROM is embedded in the broad legacy FLASH mask window;
            // retain it as an independent read-only target by testing its
            // exact physical range before the coarse Flash decode.
            else if ((a >= `SOC_BOOT_ROM_BASE) && (a < (`SOC_BOOT_ROM_BASE + `SOC_BOOT_ROM_SIZE)))
                decode_slave = 4'd4;                 // S4 Boot ROM
            else if ((a & `SOC_256MB_REGION_MASK) == `SOC_FLASH_BASE)
                decode_slave = 4'd2;                 // S2 FLASH
            else if ((a >= `SOC_DDR_BASE) && (a < (`SOC_DDR_BASE + `SOC_DDR_SIZE)))
                decode_slave = 4'd3;                 // S3 DDR (behavioral placeholder)
            else
                decode_slave = DEC[3:0];             // DECERR
        end
    endfunction

    wire [3:0] ar_tgt [0:N_M-1];
    wire [3:0] aw_tgt [0:N_M-1];
    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_decode
        assign ar_tgt[gm] = decode_slave(ar_addr[gm]);
        assign aw_tgt[gm] = decode_slave(aw_addr[gm]);
    end endgenerate

    // ==================================================================
    // READ PATH
    // ==================================================================
    // Per-slave outstanding FIFO of {master_idx, id, len}, in issue order.
    reg  [MIDW-1:0] rd_mid [0:S_ALL-1][0:N_OT-1];
    reg  [IDW-1:0]  rd_rid [0:S_ALL-1][0:N_OT-1];
    reg  [7:0]      rd_len [0:S_ALL-1][0:N_OT-1];
    integer         rd_head[0:S_ALL-1];
    integer         rd_tail[0:S_ALL-1];
    integer         rd_cnt [0:S_ALL-1];
    reg  [7:0]      rd_beat[0:S_ALL-1];   // DECERR beat counter (head entry)

    // Per-slave read grant (combinational QoS+RR arbiter)
    reg  [MIDW-1:0] rd_grant   [0:S_ALL-1];
    reg             rd_grant_v [0:S_ALL-1];
    reg  [MIDW-1:0] rd_rr      [0:S_ALL-1];   // round-robin pointer
    // AR grant lock: once an AR is presented to a slave but not yet accepted,
    // the grant is held so the AR payload stays stable (AXI requires payload
    // stability while ARVALID && !ARREADY). Set when arvalid asserted & !accept.
    reg             rd_lock    [0:S_ALL-1];
    reg  [MIDW-1:0] rd_lock_m  [0:S_ALL-1];

    // slave->master read response contribution
    reg             rvalid_s2m [0:S_ALL-1][0:N_M-1];
    reg  [IDW-1:0]  rid_s2m    [0:S_ALL-1][0:N_M-1];
    reg  [DW-1:0]   rdata_s2m  [0:S_ALL-1][0:N_M-1];
    reg  [1:0]      rresp_s2m  [0:S_ALL-1][0:N_M-1];
    reg             rlast_s2m  [0:S_ALL-1][0:N_M-1];

    // Read arbiter: pick highest-QoS eligible master for each slave; RR tie-break.
    integer am, mi, best_q, sc;
    reg     elig;
    always @(*) begin
        for (i=0;i<S_ALL;i=i+1) begin
            rd_grant[i]   = {MIDW{1'b0}};
            rd_grant_v[i] = 1'b0;
            if (rd_lock[i]) begin
                // Hold the locked master's grant until AR is accepted.
                rd_grant[i]   = rd_lock_m[i];
                rd_grant_v[i] = m_enable[rd_lock_m[i]] && m_arvalid[rd_lock_m[i]]
                                && (rd_cnt[i] < N_OT);
            end else begin
                best_q = -1;
                // pass 1: find highest QoS among eligible masters targeting slave i
                for (am=0; am<N_M; am=am+1) begin
                    elig = m_enable[am] && m_arvalid[am] && (ar_tgt[am]==i[3:0])
                           && (rd_cnt[i] < N_OT);
                    if (elig && ($signed({1'b0,ar_qos[am]}) > best_q))
                        best_q = {1'b0,ar_qos[am]};
                end
                // pass 2: among eligible masters at best_q, pick first in RR order
                for (sc=0; sc<N_M; sc=sc+1) begin
                    mi = (rd_rr[i] + sc) % N_M;
                    elig = m_enable[mi] && m_arvalid[mi] && (ar_tgt[mi]==i[3:0])
                           && (rd_cnt[i] < N_OT) && ({1'b0,ar_qos[mi]}==best_q);
                    if (elig && !rd_grant_v[i]) begin
                        rd_grant[i]   = mi[MIDW-1:0];
                        rd_grant_v[i] = 1'b1;
                    end
                end
            end
        end
    end

    // AR drive to real slaves (mux granted master's fields)
    wire [MIDW-1:0] rg [0:S_ALL-1];
    generate for (gs=0; gs<S_ALL; gs=gs+1) begin: g_rg
        assign rg[gs] = rd_grant[gs];
    end endgenerate

    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_ar_drive
        assign s_arid   [gs*IDW +: IDW] = ar_id  [rg[gs]];
        assign s_araddr [gs*AW  +: AW ] = ar_addr[rg[gs]];
        assign s_arlen  [gs*8   +: 8  ] = ar_len [rg[gs]];
        assign s_arsize [gs*3   +: 3  ] = ar_size[rg[gs]];
        assign s_arburst[gs*2   +: 2  ] = ar_bst [rg[gs]];
        assign s_arlock [gs*2   +: 2  ] = ar_lk  [rg[gs]];
        assign s_arcache[gs*4   +: 4  ] = ar_ca  [rg[gs]];
        assign s_arprot [gs*3   +: 3  ] = ar_pr  [rg[gs]];
        assign s_arvalid[gs]            = rd_grant_v[gs];
    end endgenerate

    // Per-slave AR accept: real slave handshakes; DECERR accepts immediately.
    wire ar_accept [0:S_ALL-1];
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_ar_acc
        assign ar_accept[gs] = s_arvalid[gs] && s_arready[gs];
    end endgenerate
    assign ar_accept[DEC] = rd_grant_v[DEC];

    // m_arready: granted master at its target slave sees that slave's accept
    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_arready
        assign m_arready[gm] = m_enable[gm] && m_arvalid[gm] &&
                               rd_grant_v[ar_tgt[gm]] &&
                               (rg[ar_tgt[gm]]==gm[MIDW-1:0]) &&
                               ar_accept[ar_tgt[gm]];
    end endgenerate

    // Read response routing: FIFO head of each slave identifies target master.
    // Real slaves supply rvalid/rdata/rresp/rlast; DECERR is synthesized.
    wire [MIDW-1:0] rd_head_mid [0:S_ALL-1];
    wire [IDW-1:0]  rd_head_id  [0:S_ALL-1];
    wire [7:0]      rd_head_len [0:S_ALL-1];
    wire            rd_occ      [0:S_ALL-1];
    generate for (gs=0; gs<S_ALL; gs=gs+1) begin: g_rhead
        assign rd_occ[gs]      = (rd_cnt[gs] != 0);
        assign rd_head_mid[gs] = rd_mid[gs][rd_head[gs]];
        assign rd_head_id[gs]  = rd_rid[gs][rd_head[gs]];
        assign rd_head_len[gs] = rd_len[gs][rd_head[gs]];
    end endgenerate

    // DECERR read beat valid/last (head entry of DECERR slave)
    wire dec_rvalid = rd_occ[DEC];
    wire dec_rlast  = rd_occ[DEC] && (rd_beat[DEC] == rd_head_len[DEC]);

    always @(*) begin
        for (i=0;i<S_ALL;i=i+1) begin
            for (am=0; am<N_M; am=am+1) begin
                rvalid_s2m[i][am] = 1'b0;
                rid_s2m[i][am]    = {IDW{1'b0}};
                rdata_s2m[i][am]  = {DW{1'b0}};
                rresp_s2m[i][am]  = 2'b00;
                rlast_s2m[i][am]  = 1'b0;
            end
        end
        // real slaves
        for (i=0;i<N_S;i=i+1) begin
            if (rd_occ[i]) begin
                rvalid_s2m[i][rd_head_mid[i]] = s_rvalid[i];
                rid_s2m[i][rd_head_mid[i]]    = s_rid[i*IDW +: IDW];
                rdata_s2m[i][rd_head_mid[i]]  = s_rdata[i*DW +: DW];
                rresp_s2m[i][rd_head_mid[i]]  = s_rresp[i*2 +: 2];
                rlast_s2m[i][rd_head_mid[i]]  = s_rlast[i];
            end
        end
        // DECERR synthesized
        if (rd_occ[DEC]) begin
            rvalid_s2m[DEC][rd_head_mid[DEC]] = dec_rvalid;
            rid_s2m[DEC][rd_head_mid[DEC]]    = rd_head_id[DEC];
            rdata_s2m[DEC][rd_head_mid[DEC]]  = {DW{1'b0}};
            rresp_s2m[DEC][rd_head_mid[DEC]]  = `SOC_AXI_RESP_DECERR;
            rlast_s2m[DEC][rd_head_mid[DEC]]  = dec_rlast;
        end
    end

    // Combine per-slave contributions into master R outputs.
    // A master has at most one outstanding read (to one slave) at a time, so
    // at most one slave contributes; OR/mux is safe.
    reg             m_rvalid_c [0:N_M-1];
    reg  [IDW-1:0]  m_rid_c    [0:N_M-1];
    reg  [DW-1:0]   m_rdata_c  [0:N_M-1];
    reg  [1:0]      m_rresp_c  [0:N_M-1];
    reg             m_rlast_c  [0:N_M-1];
    always @(*) begin
        for (am=0; am<N_M; am=am+1) begin
            m_rvalid_c[am] = 1'b0; m_rid_c[am] = {IDW{1'b0}};
            m_rdata_c[am]  = {DW{1'b0}}; m_rresp_c[am] = 2'b00;
            m_rlast_c[am]  = 1'b0;
            for (i=0;i<S_ALL;i=i+1) begin
                if (rvalid_s2m[i][am]) begin
                    m_rvalid_c[am] = 1'b1;
                    m_rid_c[am]    = rid_s2m[i][am];
                    m_rdata_c[am]  = rdata_s2m[i][am];
                    m_rresp_c[am]  = rresp_s2m[i][am];
                    m_rlast_c[am]  = rlast_s2m[i][am];
                end
            end
        end
    end
    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_rout
        assign m_rvalid[gm]          = m_rvalid_c[gm];
        assign m_rid  [gm*IDW +: IDW]= m_rid_c[gm];
        assign m_rdata[gm*DW  +: DW ]= m_rdata_c[gm];
        assign m_rresp[gm*2   +: 2  ]= m_rresp_c[gm];
        assign m_rlast[gm]           = m_rlast_c[gm];
    end endgenerate

    // s_rready to real slaves: head master's rready
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_srready
        assign s_rready[gs] = rd_occ[gs] && m_rready[rd_head_mid[gs]];
    end endgenerate

    // per-slave read-beat fire (for pop + DECERR beat count)
    wire rd_fire [0:S_ALL-1];
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_rfire
        assign rd_fire[gs] = rd_occ[gs] && s_rvalid[gs] &&
                             m_rready[rd_head_mid[gs]] && s_rlast[gs];
    end endgenerate
    assign rd_fire[DEC] = rd_occ[DEC] && dec_rvalid &&
                          m_rready[rd_head_mid[DEC]] && dec_rlast;

    // Read FIFO sequential update
    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s=0;s<S_ALL;s=s+1) begin
                rd_head[s] <= 0; rd_tail[s] <= 0; rd_cnt[s] <= 0;
                rd_beat[s] <= 8'd0; rd_rr[s] <= {MIDW{1'b0}};
                rd_lock[s] <= 1'b0; rd_lock_m[s] <= {MIDW{1'b0}};
            end
        end else begin
            for (s=0;s<S_ALL;s=s+1) begin
                // AR grant lock: assert when a grant is presented but not yet
                // accepted; clear on accept. Holds AR payload stable.
                if (rd_grant_v[s] && !ar_accept[s]) begin
                    rd_lock[s]   <= 1'b1;
                    rd_lock_m[s] <= rd_grant[s];
                end else if (ar_accept[s]) begin
                    rd_lock[s]   <= 1'b0;
                end
                // push on AR accept
                if (ar_accept[s]) begin
                    rd_mid[s][rd_tail[s]] <= rd_grant[s];
                    rd_rid[s][rd_tail[s]] <= ar_id [rd_grant[s]];
                    rd_len[s][rd_tail[s]] <= ar_len[rd_grant[s]];
                    rd_tail[s] <= (rd_tail[s]+1) % N_OT;
                    rd_rr[s]   <= (rd_grant[s]+1) % N_M;
                end
                // DECERR beat progression (non-last beats)
                if (s==DEC && rd_occ[DEC] && dec_rvalid &&
                    m_rready[rd_head_mid[DEC]] && !dec_rlast)
                    rd_beat[DEC] <= rd_beat[DEC] + 8'd1;
                // pop on final beat fire
                if (rd_fire[s]) begin
                    rd_head[s] <= (rd_head[s]+1) % N_OT;
                    if (s==DEC) rd_beat[DEC] <= 8'd0;
                end
                // net count update
                case ({ar_accept[s], rd_fire[s]})
                    2'b10: rd_cnt[s] <= rd_cnt[s] + 1;
                    2'b01: rd_cnt[s] <= rd_cnt[s] - 1;
                    default: rd_cnt[s] <= rd_cnt[s];
                endcase
            end
        end
    end

    // ==================================================================
    // WRITE PATH
    // ==================================================================
    reg  [MIDW-1:0] wr_mid [0:S_ALL-1][0:N_OT-1];
    reg  [IDW-1:0]  wr_bid [0:S_ALL-1][0:N_OT-1];
    integer         wr_head[0:S_ALL-1];   // B pointer
    integer         wr_wptr[0:S_ALL-1];   // W-data pointer
    integer         wr_tail[0:S_ALL-1];
    integer         wr_cnt [0:S_ALL-1];   // AW outstanding count
    integer         wr_wpend[0:S_ALL-1];  // AW accepted but W not yet drained

    reg  [MIDW-1:0] wr_grant   [0:S_ALL-1];
    reg             wr_grant_v [0:S_ALL-1];
    reg  [MIDW-1:0] wr_rr      [0:S_ALL-1];
    reg             wr_lock    [0:S_ALL-1];   // AW grant lock (payload stability)
    reg  [MIDW-1:0] wr_lock_m  [0:S_ALL-1];

    reg             bvalid_s2m [0:S_ALL-1][0:N_M-1];
    reg  [IDW-1:0]  bid_s2m    [0:S_ALL-1][0:N_M-1];
    reg  [1:0]      bresp_s2m  [0:S_ALL-1][0:N_M-1];

    integer aw, wmi, wbest, wsc;
    reg     welig;
    always @(*) begin
        for (i=0;i<S_ALL;i=i+1) begin
            wr_grant[i]   = {MIDW{1'b0}};
            wr_grant_v[i] = 1'b0;
            if (wr_lock[i]) begin
                wr_grant[i]   = wr_lock_m[i];
                wr_grant_v[i] = m_enable[wr_lock_m[i]] && m_awvalid[wr_lock_m[i]]
                                && (wr_cnt[i] < N_OT);
            end else begin
            wbest         = -1;
            for (aw=0; aw<N_M; aw=aw+1) begin
                welig = m_enable[aw] && m_awvalid[aw] && (aw_tgt[aw]==i[3:0])
                        && (wr_cnt[i] < N_OT);
                if (welig && ($signed({1'b0,aw_qos[aw]}) > wbest))
                    wbest = {1'b0,aw_qos[aw]};
            end
            for (wsc=0; wsc<N_M; wsc=wsc+1) begin
                wmi = (wr_rr[i] + wsc) % N_M;
                welig = m_enable[wmi] && m_awvalid[wmi] && (aw_tgt[wmi]==i[3:0])
                        && (wr_cnt[i] < N_OT) && ({1'b0,aw_qos[wmi]}==wbest);
                if (welig && !wr_grant_v[i]) begin
                    wr_grant[i]   = wmi[MIDW-1:0];
                    wr_grant_v[i] = 1'b1;
                end
            end
            end
        end
    end

    wire [MIDW-1:0] wg [0:S_ALL-1];
    generate for (gs=0; gs<S_ALL; gs=gs+1) begin: g_wg
        assign wg[gs] = wr_grant[gs];
    end endgenerate

    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_aw_drive
        assign s_awid   [gs*IDW +: IDW] = aw_id  [wg[gs]];
        assign s_awaddr [gs*AW  +: AW ] = aw_addr[wg[gs]];
        assign s_awlen  [gs*8   +: 8  ] = aw_len [wg[gs]];
        assign s_awsize [gs*3   +: 3  ] = aw_size[wg[gs]];
        assign s_awburst[gs*2   +: 2  ] = aw_bst [wg[gs]];
        assign s_awlock [gs*2   +: 2  ] = aw_lk  [wg[gs]];
        assign s_awcache[gs*4   +: 4  ] = aw_ca  [wg[gs]];
        assign s_awprot [gs*3   +: 3  ] = aw_pr  [wg[gs]];
        assign s_awvalid[gs]            = wr_grant_v[gs];
    end endgenerate

    wire aw_accept [0:S_ALL-1];
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_aw_acc
        assign aw_accept[gs] = s_awvalid[gs] && s_awready[gs];
    end endgenerate
    assign aw_accept[DEC] = wr_grant_v[DEC];

    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_awready
        assign m_awready[gm] = m_enable[gm] && m_awvalid[gm] &&
                               wr_grant_v[aw_tgt[gm]] &&
                               (wg[aw_tgt[gm]]==gm[MIDW-1:0]) &&
                               aw_accept[aw_tgt[gm]];
    end endgenerate

    // W routing: follows W-pointer entry per slave (AW-accept order).
    wire [MIDW-1:0] w_head_mid [0:S_ALL-1];
    wire            w_occ      [0:S_ALL-1];   // AW accepted, W not yet drained
    generate for (gs=0; gs<S_ALL; gs=gs+1) begin: g_whead
        assign w_head_mid[gs] = wr_mid[gs][wr_wptr[gs]];
        assign w_occ[gs]      = (wr_wpend[gs] != 0);
    end endgenerate

    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_w_drive
        assign s_wdata [gs*DW +: DW] = m_wdata[w_head_mid[gs]*DW +: DW];
        assign s_wstrb [gs*4  +: 4 ] = m_wstrb[w_head_mid[gs]*4  +: 4];
        assign s_wlast [gs]          = m_wlast[w_head_mid[gs]];
        assign s_wvalid[gs]          = w_occ[gs] && m_wvalid[w_head_mid[gs]];
    end endgenerate

    // m_wready: the master at each slave's W-head sees that slave's wready.
    // DECERR slave sinks W immediately (ready when it owns the W-head).
    reg m_wready_c [0:N_M-1];
    always @(*) begin
        for (am=0; am<N_M; am=am+1) m_wready_c[am] = 1'b0;
        for (i=0;i<N_S;i=i+1)
            if (w_occ[i]) m_wready_c[w_head_mid[i]] = s_wready[i];
        if (w_occ[DEC]) m_wready_c[w_head_mid[DEC]] = 1'b1;
    end
    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_wready
        assign m_wready[gm] = m_wready_c[gm];
    end endgenerate

    // W-beat fire (last beat) per slave
    wire w_fire [0:S_ALL-1];
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_wfire
        assign w_fire[gs] = w_occ[gs] && s_wvalid[gs] && s_wready[gs] && s_wlast[gs];
    end endgenerate
    assign w_fire[DEC] = w_occ[DEC] && m_wvalid[w_head_mid[DEC]] &&
                         m_wlast[w_head_mid[DEC]];

    // B routing: B-pointer (wr_head) entry per slave.
    wire [MIDW-1:0] b_head_mid [0:S_ALL-1];
    wire [IDW-1:0]  b_head_id  [0:S_ALL-1];
    wire            b_occ      [0:S_ALL-1];   // entries with W drained, B pending
    generate for (gs=0; gs<S_ALL; gs=gs+1) begin: g_bhead
        assign b_head_mid[gs] = wr_mid[gs][wr_head[gs]];
        assign b_head_id[gs]  = wr_bid[gs][wr_head[gs]];
        // B pending if there is an AW entry whose W has drained (wptr moved past head)
        assign b_occ[gs]      = (wr_cnt[gs] != 0) && (wr_wpend[gs] < wr_cnt[gs]);
    end endgenerate

    wire dec_bvalid = b_occ[DEC];

    always @(*) begin
        for (i=0;i<S_ALL;i=i+1)
            for (am=0; am<N_M; am=am+1) begin
                bvalid_s2m[i][am] = 1'b0;
                bid_s2m[i][am]    = {IDW{1'b0}};
                bresp_s2m[i][am]  = 2'b00;
            end
        for (i=0;i<N_S;i=i+1)
            if (b_occ[i]) begin
                bvalid_s2m[i][b_head_mid[i]] = s_bvalid[i];
                bid_s2m[i][b_head_mid[i]]    = s_bid[i*IDW +: IDW];
                bresp_s2m[i][b_head_mid[i]]  = s_bresp[i*2 +: 2];
            end
        if (b_occ[DEC]) begin
            bvalid_s2m[DEC][b_head_mid[DEC]] = dec_bvalid;
            bid_s2m[DEC][b_head_mid[DEC]]    = b_head_id[DEC];
            bresp_s2m[DEC][b_head_mid[DEC]]  = `SOC_AXI_RESP_DECERR;
        end
    end

    reg            m_bvalid_c [0:N_M-1];
    reg [IDW-1:0]  m_bid_c    [0:N_M-1];
    reg [1:0]      m_bresp_c  [0:N_M-1];
    always @(*) begin
        for (am=0; am<N_M; am=am+1) begin
            m_bvalid_c[am]=1'b0; m_bid_c[am]={IDW{1'b0}}; m_bresp_c[am]=2'b00;
            for (i=0;i<S_ALL;i=i+1)
                if (bvalid_s2m[i][am]) begin
                    m_bvalid_c[am]=1'b1; m_bid_c[am]=bid_s2m[i][am];
                    m_bresp_c[am]=bresp_s2m[i][am];
                end
        end
    end
    generate for (gm=0; gm<N_M; gm=gm+1) begin: g_bout
        assign m_bvalid[gm]           = m_bvalid_c[gm];
        assign m_bid  [gm*IDW +: IDW] = m_bid_c[gm];
        assign m_bresp[gm*2   +: 2  ] = m_bresp_c[gm];
    end endgenerate

    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_sbready
        assign s_bready[gs] = b_occ[gs] && m_bready[b_head_mid[gs]];
    end endgenerate

    wire b_fire [0:S_ALL-1];
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_bfire
        assign b_fire[gs] = b_occ[gs] && s_bvalid[gs] && m_bready[b_head_mid[gs]];
    end endgenerate
    assign b_fire[DEC] = b_occ[DEC] && dec_bvalid && m_bready[b_head_mid[DEC]];

    // Write FIFO sequential update
    integer ws;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ws=0;ws<S_ALL;ws=ws+1) begin
                wr_head[ws]<=0; wr_wptr[ws]<=0; wr_tail[ws]<=0;
                wr_cnt[ws]<=0; wr_wpend[ws]<=0; wr_rr[ws]<={MIDW{1'b0}};
                wr_lock[ws]<=1'b0; wr_lock_m[ws]<={MIDW{1'b0}};
            end
        end else begin
            for (ws=0;ws<S_ALL;ws=ws+1) begin
                // AW grant lock for payload stability
                if (wr_grant_v[ws] && !aw_accept[ws]) begin
                    wr_lock[ws]   <= 1'b1;
                    wr_lock_m[ws] <= wr_grant[ws];
                end else if (aw_accept[ws]) begin
                    wr_lock[ws]   <= 1'b0;
                end
                if (aw_accept[ws]) begin
                    wr_mid[ws][wr_tail[ws]] <= wr_grant[ws];
                    wr_bid[ws][wr_tail[ws]] <= aw_id[wr_grant[ws]];
                    wr_tail[ws] <= (wr_tail[ws]+1) % N_OT;
                    wr_rr[ws]   <= (wr_grant[ws]+1) % N_M;
                end
                if (w_fire[ws]) wr_wptr[ws] <= (wr_wptr[ws]+1) % N_OT;
                if (b_fire[ws]) wr_head[ws] <= (wr_head[ws]+1) % N_OT;
                // wr_cnt: AW outstanding (until B)
                case ({aw_accept[ws], b_fire[ws]})
                    2'b10: wr_cnt[ws] <= wr_cnt[ws] + 1;
                    2'b01: wr_cnt[ws] <= wr_cnt[ws] - 1;
                    default: wr_cnt[ws] <= wr_cnt[ws];
                endcase
                // wr_wpend: AW accepted but W not yet drained
                case ({aw_accept[ws], w_fire[ws]})
                    2'b10: wr_wpend[ws] <= wr_wpend[ws] + 1;
                    2'b01: wr_wpend[ws] <= wr_wpend[ws] - 1;
                    default: wr_wpend[ws] <= wr_wpend[ws];
                endcase
            end
        end
    end

endmodule
