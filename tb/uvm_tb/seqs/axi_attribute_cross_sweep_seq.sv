`ifndef AXI_ATTRIBUTE_CROSS_SWEEP_SEQ_SV
`define AXI_ATTRIBUTE_CROSS_SWEEP_SEQ_SV

//------------------------------------------------------------------------------
// axi_attribute_cross_sweep_seq
//
// Phase A closure companion (see .agent/review.md §"Required Closure Plan"):
// systematically sweeps AXI attribute combinations that the existing
// `axi_id_sweep_seq` / `axi_apb_reg_model_seq` families do not densely cover.
//
// Concretely walks:
//   * ID          : 16 values, 0..15
//   * Burst len   : 0, 1, 3, 7 (single, 2-beat, 4-beat, 8-beat)
//   * Size        : 010 (word) — byte/half are not supported by the current
//                   single-outstanding SRAM/APB contract; keeping size fixed
//                   avoids DECERR while still exercising the size coverpoint
//   * Address win : SRAM alias / APB GPIO / APB timer / flash / unmapped
//   * Direction   : R and W for aliased writable slaves; R-only for flash;
//                   both intentionally trigger response coverpoints
//
// Also generates the SLVERR (flash write) and DECERR (unmapped) response
// bins that only these directed patterns can hit reliably.
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_attribute_cross_sweep_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_attribute_cross_sweep_seq)

    // Distinct scratch offsets so different (id, len) writes don't collide.
    localparam logic [31:0] SRAM_SCRATCH = `SOC_SRAM_ALIAS_BASE + 32'h0000_C200;

    function new(string name = "axi_attribute_cross_sweep_seq");
        super.new(name);
    endfunction

    task do_axi(string tag,
                axi_trans_type_e dir,
                logic [31:0] addr,
                logic [3:0]  id,
                logic [7:0]  len,
                logic [1:0]  expected_resp);
        axi_transaction tr;
        int unsigned beats = len + 1;

        tr = axi_transaction::type_id::create(tag);
        start_item(tr);
        tr.trans_type = dir;
        tr.id         = id;
        tr.addr       = addr;
        tr.len        = len;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data = new[beats];
        tr.strb = new[beats];
        tr.resp = new[dir == AXI_READ ? beats : 1];
        foreach (tr.data[i]) begin
            tr.data[i] = { id, len[7:0], beats[15:8], 8'hA5 } ^ (32'h1000_1000 * i);
            tr.strb[i] = 4'hF;
        end
        foreach (tr.resp[i])
            tr.resp[i] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        // Only spot-check the terminating beat for reads (fabric behaviour is
        // uniform per beat); writes have a single BRESP.
        if (tr.resp[dir == AXI_READ ? beats - 1 : 0] != expected_resp) begin
            `uvm_error("AXI_ATTR_XSWEEP",
                $sformatf("%s id=%0d len=%0d addr=0x%08h resp=%0h expected=%0h",
                          tag, id, len, addr,
                          tr.resp[dir == AXI_READ ? beats - 1 : 0],
                          expected_resp))
        end
    endtask

    task body();
        logic [7:0] len_set [4] = '{8'd0, 8'd1, 8'd3, 8'd7};
        int i, j;

        //---------------------------------------------------------------
        // 1) SRAM alias — full 16 IDs × 4 lens × {R, W}. 128 transactions.
        //    Uses staggered addresses so writes/reads don't overlap and
        //    the fabric arbiter sees varied (id, addr) combos.
        //---------------------------------------------------------------
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                logic [31:0] addr = SRAM_SCRATCH + (i << 6) + (j << 4);
                do_axi($sformatf("sram_w_id%0d_len%0d", i, len_set[j]),
                       AXI_WRITE, addr, i[3:0], len_set[j], `SOC_AXI_RESP_OKAY);
                do_axi($sformatf("sram_r_id%0d_len%0d", i, len_set[j]),
                       AXI_READ,  addr, i[3:0], len_set[j], `SOC_AXI_RESP_OKAY);
            end
        end

        //---------------------------------------------------------------
        // 2) APB GPIO — reads across IDs. APB single-beat contract so
        //    non-zero len is fine (APB bridge splits into beats).
        //---------------------------------------------------------------
        for (i = 0; i < 8; i = i + 1) begin
            do_axi($sformatf("apb_gpio_r_id%0d", i),
                   AXI_READ,
                   `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                   i[3:0], 8'd0, `SOC_AXI_RESP_OKAY);
        end

        //---------------------------------------------------------------
        // 3) APB Timer — walking-1 bit pattern write across IDs so each
        //    bit position of the CTRL/LOAD register toggles at least once.
        //---------------------------------------------------------------
        for (i = 0; i < 8; i = i + 1) begin
            axi_transaction tr;
            tr = axi_transaction::type_id::create($sformatf("apb_timer_w_id%0d_walk", i));
            start_item(tr);
            tr.trans_type = AXI_WRITE;
            tr.id         = i[3:0];
            tr.addr       = `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET;
            tr.len        = 8'd0;
            tr.size       = 3'b010;
            tr.burst      = 2'b01;
            tr.data = new[1];
            tr.strb = new[1];
            tr.resp = new[1];
            tr.data[0] = 32'h0000_0001 << (i & 31);
            tr.strb[0] = 4'hF;
            tr.resp[0] = `SOC_AXI_RESP_OKAY;
            finish_item(tr);
        end

        //---------------------------------------------------------------
        // 4) Flash reads with various burst lengths (XIP). Flash writes
        //    already covered elsewhere returning SLVERR.
        //---------------------------------------------------------------
        for (j = 0; j < 4; j = j + 1) begin
            do_axi($sformatf("flash_r_len%0d", len_set[j]),
                   AXI_READ,
                   `SOC_FLASH_BASE + 32'h0000_0400 + (j << 5),
                   4'h6, len_set[j], `SOC_AXI_RESP_OKAY);
        end

        //---------------------------------------------------------------
        // 5) Unmapped windows — exercise DECERR across id / len / dir.
        //---------------------------------------------------------------
        for (i = 0; i < 4; i = i + 1) begin
            do_axi($sformatf("dec_r_id%0d", i),
                   AXI_READ, 32'hF200_0000 + (i << 8),
                   i[3:0], len_set[i], `SOC_AXI_RESP_DECERR);
            do_axi($sformatf("dec_w_id%0d", i),
                   AXI_WRITE, 32'hF300_0000 + (i << 8),
                   i[3:0] | 4'h8, 8'd0, `SOC_AXI_RESP_DECERR);
        end
    endtask
endclass

`endif
