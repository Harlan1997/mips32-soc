# Codex Code Review

> Task: TASK-002 - audited 99% coverage closure
> Reviewer: Codex
> Status: REJECTED

## Blocking Issues

Previous C2A attempt status: `MAX_RETRY_EXCEEDED / BLOCKED`.

The last AGY invocation failed before implementation or verification with:

```text
Error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 2h35m33s.
```

No `.agent/test_report.md` or `.agent/result.json` was produced. The retry
budget is exhausted (`attempt=3`, `max_attempts=3`), so Codex must stop
automatic AGY retries until quota resets or the retry budget is explicitly
extended.

User confirmed quota has recovered. Codex terminated the stale orphan `agy`
process from the quota-failed attempt and extended `max_attempts` to 4 for one
additional AGY run using the existing `AGY_PRINT_TIMEOUT=2h` control script.

Final resumed attempt (`attempt=4/max_attempts=4`) also failed. AGY launched
`make current-contract-signoff` as an opaque background task, exited non-zero,
and again did not produce `.agent/test_report.md` or `.agent/result.json`.
The latest observed signoff report remained `FAIL` at
`COVERAGE_THRESHOLDS`; representative adjusted coverage failures included UVM
Score/Cond/Toggle/FSM/Branch and Product Score/Line/Toggle/FSM/Branch below
99.00%.

0. Latest attempt with `--print-timeout 2h` still exited non-zero after about
   10 minutes and produced neither `.agent/test_report.md` nor
   `.agent/result.json`. This proves the current failure is not simply that
   30 minutes was too short; AGY must fix its own foreground execution/reporting
   flow.
1. AGY timed out at the `--print-timeout 30m` boundary and exited non-zero.
   `.agent/test_report.md` and `.agent/result.json` were not produced, so the
   C2A worker contract was not satisfied.
2. The last observed `build/signoff/current_contract/coverage_summary.json`
   did not meet the 99.00% adjusted coverage requirement. Observed failures
   included UVM Score/Line/Cond/Toggle/FSM/Branch below 99.00%, and Product
   CPU/CP0 Score/Line/Cond/FSM/Branch below 99.00%.
3. Do not launch long validation in a way that leaves AGY waiting past the
   print timeout without producing `.agent/test_report.md` and
   `.agent/result.json`. If the full sign-off cannot complete inside AGY's
   timeout, run narrower prechecks first, then run the required final command
   and summarize the exact failure.
4. Clean up temporary scratch/URG dump artifacts or keep them under documented
   ignored scratch paths only. The final diff must stay within the approved
   allowed paths and should not leave ad hoc top-level `fullexclude.*` files.

## Required Next Attempt

### Gap Review

The current closure approach is not acceptable. It mechanically generates broad
module/all-metric `.el` blocks and then filters URG attempts. That still leaves
major adjusted coverage gaps and also tries to classify reachable behavior as
`UNREACHABLE_CURRENT_CONTRACT`.

Latest observed adjusted module-definition gaps:

- UVM: Score 93.90, Cond 97.40, Toggle 79.14, FSM 98.85, Branch 94.12.
- Product CPU/CP0: Score 88.37, Line 78.16, Toggle 75.91, FSM 94.29,
  Branch 93.48.

High-impact reachable modules still below target include:

- UVM: `soc_peripheral_subsystem`, `soc_core_subsystem`,
  `soc_memory_subsystem`, `soc_fabric`, `mips_soc_impl`, `apb_uart`,
  `apb_pic`, `mips_if_stage`, `apb_timer`, `axi2apb_bridge`,
  `apb_axi_dma`, `mips_cp0`, `axi_arbiter_2x1`,
  `axi_arbiter_2x1_full`, `dcache`, `axi_decoder_1x3`, `icache`,
  `mips_mdu`, `mips_id_stage`, `mips_mem_stage`, `mips_alu`.
- Product: `axi_sram`, `soc_debug_subsystem`, `mips_soc_impl`,
  `soc_fabric`, `soc_memory_subsystem`, `soc_core_subsystem`,
  `tb_mips_soc`, `mips_core`, `axi_ddr_model`, `apb_uart`,
  `soc_peripheral_subsystem`, `axi_decoder_1x3`, `apb_pic`,
  `axi_arbiter_2x1_full`, `apb_timer`, `axi2apb_bridge`,
  `jtag_debug_top`, `axi_spi_flash`, `apb_axi_dma`, `axi_arbiter_2x1`,
  `mips_cp0`, `dcache`, `icache`, `mips_mdu`, `mips_id_stage`,
  `mips_mem_stage`, `mips_alu`.

Examples of objects that must be treated as reachable unless proven otherwise:

- AXI ID/len/size/burst/cache/prot/lock/address/data toggles.
- Decoder APB/flash/SRAM/error select branches and SLVERR handshakes.
- APB timer/PIC/GPIO/DMA register bit patterns and interrupt paths.
- CPU opcode, jump/link, hazard, forwarding, load-use, ALU compare/shift,
  MDU mult/div, CP0 exception/ERET/status/cause paths.
- Cache/SRAM/DDR read/write/data/strobe/address variation.

Examples that may be excluded only with exact object-level evidence:

- UART RX-only logic under the current UART TX contract.
- Real SPI-serial timing/boot logic outside the AXI flash-image contract.
- Uninstantiated parameter variants such as explicitly absent configurations.
- Static tieoffs/reserved fields whose value cannot legally toggle.
- Defensive illegal/default FSM recovery reachable only by X/corrupt state.
- Non-product verification/bind/tool recording logic.

### Required Closure Plan

1. Stop generating broad module/all-metric exclusions. Exclusions must be
   exact object-level rules with allowed Spec categories and object-specific
   evidence. System labels such as "Bus & Fabric Interconnect" or
   "CPU Core & Pipeline" are not valid exclusion categories.
2. Add reachable stimulus first. Required new directed coverage tests:
   - AXI attribute sweep: vary ID 0..15, len 0/1/3/7, size 0/1/2, burst
     FIXED/INCR/WRAP where legal, cache/prot/lock bits, across SRAM/APB/flash
     and unmapped/error regions.
   - APB/peripheral bit sweep: timer/PIC/GPIO/DMA/UART TX register writes and
     reads using 0, all-ones, walking-1, walking-0, alternating patterns, and
     interrupt enable/clear/status paths.
   - CPU instruction firmware sweep: ADD/ADDU/SUB/SUBU/AND/OR/XOR/NOR/SLT/
     SLTU/SLL/SRL/SRA/LUI, branches taken/not-taken, J/JAL/JR/JALR, load/store
     byte/half/word if implemented, hazard/forwarding/load-use stalls, CP0
     mfc0/mtc0/syscall/RI/AdEL/ERET, MDU mult/multu/div/divu including
     signed/unsigned and divide corner cases.
   - Memory/cache sweep: SRAM/DDR/flash reads, writes, byte strobes, address
     low/high bits, cache hit/miss/refill/dirty/writeback paths where current
     RTL implements them.
   - Fabric arbitration/backpressure sweep: m0/m1 contention, read/write
     arbitration, wait-state, response, and error paths within the
     single-outstanding contract.
3. Product CPU/CP0 coverage must be improved with firmware and legacy
   observation TB stimulus, not with broad product exclusions. UVM-only tests
   do not close Product `tb_mips_soc`/CPU/module denominator unless the
   product-top simulation runs the same reachable behavior.
4. Split closure into measurable prechecks:
   - `make firmware`
   - focused UVM testlist for new closure tests
   - focused product CPU/CP0 firmware gate
   - raw/adjusted URG generation
   - final `make current-contract-signoff`
5. AGY must run commands synchronously in its shell or with explicit PID and
   exit-code collection. Do not use opaque Antigravity background task handles.
   Even on failure, write `.agent/test_report.md` and `.agent/result.json`
   before returning.
6. Final acceptance remains strict: both coverage domains must report all six
   adjusted metrics `>=99.00%`, with raw and adjusted reports from the same
   fresh VDBs, no `-excl_bypass_checks`, and no covered-object exclusion
   attempts in `attempts.log`.
