// =============================================================================
// File Name: reset_agg.v
// Design:    Reset Aggregator (per-domain)
// Author:    Antigravity — Phase E
// Description:
//   Combines POR, soft, watchdog, JTAG reset sources plus PLL lock gate into
//   a single pre-sync reset input. Output feeds reset_sync for that domain.
//   All inputs are active-low; pll_lock is active-high (1 = clock ready).
// =============================================================================

module reset_agg (
    input  wire por_n,
    input  wire soft_rst_n,
    input  wire wdt_rst_n,
    input  wire jtag_rst_n,
    input  wire pll_lock,
    output wire agg_rst_n
);

    assign agg_rst_n = por_n & soft_rst_n & wdt_rst_n & jtag_rst_n & pll_lock;

endmodule
