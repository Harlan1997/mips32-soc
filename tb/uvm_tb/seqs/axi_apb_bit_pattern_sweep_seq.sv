`ifndef AXI_APB_BIT_PATTERN_SWEEP_SEQ_SV
`define AXI_APB_BIT_PATTERN_SWEEP_SEQ_SV

//------------------------------------------------------------------------------
// axi_apb_bit_pattern_sweep_seq
//
// Phase A closure companion (see .agent/review.md §"Required Closure Plan"
// item 2b — "APB/peripheral bit sweep"). Systematically walks 32-bit register
// patterns (0, all-ones, walking-1, walking-0, alternating 0xAA/0x55) into
// every APB peripheral scratch register that is safe to write without
// triggering downstream side effects (e.g., avoids arming interrupts that
// would require ISR handling).
//
// Targets:
//   * GPIO   — DATA + DIR
//   * Timer  — LOAD (max reload value patterns, keep CTRL disabled)
//   * DMA    — SRC / DST address registers (LEN kept 0 → no transfer)
//   * PIC    — MASK register (safe: only masks IRQ propagation)
//
// The intent is toggle / bit-pattern coverage on the peripheral register
// files, not functional interrupt exercise (other tests already cover that).
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_apb_bit_pattern_sweep_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_apb_bit_pattern_sweep_seq)

    function new(string name = "axi_apb_bit_pattern_sweep_seq");
        super.new(name);
    endfunction

    task apb_write(string tag,
                   logic [31:0] addr,
                   logic [31:0] wdata);
        axi_transaction tr;
        tr = axi_transaction::type_id::create(tag);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = 4'h3;
        tr.addr       = addr;
        tr.len        = 8'd0;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data = new[1];
        tr.strb = new[1];
        tr.resp = new[1];
        tr.data[0] = wdata;
        tr.strb[0] = 4'hF;
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);
        if (tr.resp[0] != `SOC_AXI_RESP_OKAY)
            `uvm_error("APB_BIT_SWEEP",
                       $sformatf("%s addr=0x%08h wdata=0x%08h resp=%0h",
                                 tag, addr, wdata, tr.resp[0]))
    endtask

    task apb_read_check(string tag,
                        logic [31:0] addr,
                        logic [31:0] expected,
                        logic [31:0] mask);
        // Reads back; only bits within `mask` are compared. Bits outside the
        // mask are typically read-only status / partial storage fields.
        axi_transaction tr;
        tr = axi_transaction::type_id::create(tag);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = 4'h3;
        tr.addr       = addr;
        tr.len        = 8'd0;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data = new[1];
        tr.strb = new[1];
        tr.resp = new[1];
        tr.strb[0] = 4'hF;
        tr.resp[0] = `SOC_AXI_RESP_OKAY;
        finish_item(tr);
        if ((tr.data[0] & mask) !== (expected & mask))
            `uvm_error("APB_BIT_SWEEP",
                       $sformatf("%s addr=0x%08h got=0x%08h expected=0x%08h mask=0x%08h",
                                 tag, addr, tr.data[0], expected, mask))
    endtask

    // Walk a 32-bit pattern generator through the standard set:
    //   0, all-ones, 32 walking-1s, 32 walking-0s, 0xAAAA_AAAA, 0x5555_5555.
    task walk_patterns(string reg_tag,
                       logic [31:0] addr,
                       logic [31:0] readback_mask);
        int i;
        logic [31:0] pat;
        apb_write($sformatf("%s_zero",  reg_tag), addr, 32'h0000_0000);
        apb_read_check($sformatf("%s_zero_rb", reg_tag), addr, 32'h0000_0000, readback_mask);
        apb_write($sformatf("%s_ones",  reg_tag), addr, 32'hFFFF_FFFF);
        apb_read_check($sformatf("%s_ones_rb", reg_tag), addr, 32'hFFFF_FFFF, readback_mask);
        for (i = 0; i < 32; i = i + 1) begin
            pat = 32'h0000_0001 << i;
            apb_write($sformatf("%s_walk1_%0d", reg_tag, i), addr, pat);
            apb_read_check($sformatf("%s_walk1_rb_%0d", reg_tag, i), addr, pat, readback_mask);
        end
        for (i = 0; i < 32; i = i + 1) begin
            pat = ~(32'h0000_0001 << i);
            apb_write($sformatf("%s_walk0_%0d", reg_tag, i), addr, pat);
            apb_read_check($sformatf("%s_walk0_rb_%0d", reg_tag, i), addr, pat, readback_mask);
        end
        apb_write($sformatf("%s_alt_a5", reg_tag), addr, 32'hAAAA_AAAA);
        apb_read_check($sformatf("%s_alt_a5_rb", reg_tag), addr, 32'hAAAA_AAAA, readback_mask);
        apb_write($sformatf("%s_alt_5a", reg_tag), addr, 32'h5555_5555);
        apb_read_check($sformatf("%s_alt_5a_rb", reg_tag), addr, 32'h5555_5555, readback_mask);
        // Restore zero so we leave state clean for subsequent tests
        apb_write($sformatf("%s_final_zero", reg_tag), addr, 32'h0000_0000);
    endtask

    task body();
        // ---------------- GPIO ----------------
        // DIR bits select whether DATA readback returns the driven output
        // (DIR=1) or the synchronized external pin (DIR=0). Force all-output
        // FIRST so DATA readback compares against the pattern; otherwise
        // pins are X in simulation. Sweep DIR after so DIR field toggles too.
        apb_write("gpio_dir_all_out_pre",
                  `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DIR_OFFSET,
                  32'hFFFF_FFFF);
        walk_patterns("gpio_data",
                      `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET,
                      32'hFFFF_FFFF);
        // Restore DIR sweep. Note: while DIR toggles inputs may bleed X into
        // DATA readback but we only compare DIR readback here.
        walk_patterns("gpio_dir",
                      `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DIR_OFFSET,
                      32'hFFFF_FFFF);
        // Leave DIR = all-outputs so downstream tests are not affected.
        apb_write("gpio_dir_all_out_post",
                  `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DIR_OFFSET,
                  32'hFFFF_FFFF);

        // ---------------- Timer LOAD ----------------
        // LOAD is 32-bit. Keep CTRL disabled (default) so the counter does not
        // start firing and blowing IRQ counters.
        walk_patterns("timer_load",
                      `SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET,
                      32'hFFFF_FFFF);

        // ---------------- DMA SRC / DST ----------------
        // Don't write LEN so no transfer starts. SRC/DST are pure storage
        // until the trigger.
        walk_patterns("dma_src",
                      `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_SRC_OFFSET,
                      32'hFFFF_FFFF);
        walk_patterns("dma_dst",
                      `SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_DST_OFFSET,
                      32'hFFFF_FFFF);

        // ---------------- PIC MASK ----------------
        // MASK propagation: reads back exactly what was written. Restoring to
        // 0 leaves subsequent IRQ tests unaffected.
        walk_patterns("pic_mask",
                      `SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_MASK_OFFSET,
                      32'hFFFF_FFFF);
    endtask
endclass

`endif
