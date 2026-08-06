# Commercial DUT Block Readiness Plan

> Scope: recently integrated DUT blocks that must not be considered
> product-complete only because smoke tests pass.

## Strategy

Commercial readiness is closed by evidence, not by file headers. Each block is
tracked across five dimensions:

- Architectural contract: documented feature set, non-goals, register map, and
  externally visible timing/response behavior.
- RTL correctness: reset behavior, error handling, corner cases, backpressure,
  illegal input handling, and integration into the product top.
- Verification depth: block unit tests, SoC UVM directed tests, scoreboard
  checks, functional coverage, and negative/error-path tests.
- Signoff hygiene: lint friendliness, debug gating, no generated
  artifacts in source, and clean build/test entry points.
- Residual-risk log: explicit future features that are not yet claimed.

## Module Review Matrix

| Block | Current DUT Status | Commercial Readiness Gaps | First Closure Step | Phase Status |
| --- | --- | --- | --- | --- |
| `mips_mdu` | Integrated in `mips_ex_stage`; full MULT/MULTU/DIV/DIVU/MFHI/MFLO/MTHI/MTLO and MADD/MADDU/MSUB/MSUBU/MUL pipeline path connected. | Closed CPU-visible MDU ISA gap in Phase 4B. CLZ/CLO remain in ALU path. | Closed in Phase 4B with 4-bit MDU plumbing, CPU decode/writeback, and mdu_cpu firmware gate. | CLOSED in Phase 4B (RTL, CPU pipeline, firmware test, mdu-cpu-gate passed) |
| `apb_axi_dma` | Integrated in `soc_peripheral_subsystem`; legacy ch0 alias works for existing DMA copy/IRQ tests; v2 windows fully functional. | Closed in Phase 4C under single-outstanding AXI contract (direct/SG, error codes, busy protection, W1C, IRQ). Burst/multi-outstanding tracked for future fabric upgrade. | Closed in Phase 4C with unit & firmware gates (`tb_dma.v`, `dma_cpu` firmware, `make dma-cpu-gate`). | CLOSED in Phase 4C (RTL, error policy, busy protection, unit & dma-cpu-gate passed) |
| `apb_vic` | Integrated as the interrupt controller baseline for the current single-line IRQ + APB VEC_ID dispatch model. | Closed in Phase 4D under single sequential writer state ownership and priority arbitration contract. | Closed in Phase 4D with unit & firmware gates (`tb_vic.v`, `vic_cpu` firmware, `make vic-cpu-gate`). | CLOSED in Phase 4D (RTL single writer, arbitration, nesting, accept, unit & vic-cpu-gate passed) |
| `apb_uart_16550` | Integrated as UART baseline with TX/RX FIFO (16 default), divisor, loopback, modem pins, RX timeout, FCR reset, and interrupt logic. | Closed in Phase 4E under PC16550D-compatible DUT contract (DLAB, SCR, FCR FIFO/single-byte, RX timeout, IIR priority, MSR delta, byte strobe, VIC IRQ). | Closed in Phase 4E with unit & firmware gates (`tb_uart_16550.v`, `uart_cpu` firmware, `make uart-cpu-gate`). | CLOSED in Phase 4E (RTL hardening, RX timeout, FCR reset, IIR priority, byte strobe, unit & uart-cpu-gate passed) |
| `l2_cache` | Integrated in DUT. `SOC_L2_CACHING=1` (default) selects the reset-safe **write-through / no-write-allocate** impl `l2_cache_wt` (128 KB, 8-way, caches reads, forwards every write to SRAM, no dirty state). `SOC_L2_WRITEBACK` selects the **write-back / write-allocate** impl `l2_cache_caching` (WB/WA, NINE, pseudo-LRU, dirty eviction), now also reset-safe (retention arrays survive the TB's async `rst_n` pulses, mirroring `axi_sram.v`). | Closed in Phase 4F under current single-outstanding blocking contract. Both impls service aligned word INCR bursts including line-crossing bursts (re-lookup per beat) and return `SLVERR` only for genuinely-illegal requests (non-word size, unaligned, non-INCR, `len>7`). Burst/multi-outstanding tracked for future fabric upgrade. | Closed in Phase 4F with unit & firmware gates (`tb_l2.v` WB contracts, `tb_l2_wt.v` WT fixes, `l2_cpu` firmware, `make l2-cpu-gate`). | CLOSED in Phase 4F (RTL error policy, single-outstanding backpressure, unit & l2-cpu-gate passed; full acceptance incl. `make uvm` clean — 0 UVM_ERROR / 0 SB_RESP). Write-through made the default in a follow-on fix (see Phase 4F note). Write-back subsequently signed off at SoC level via the opt-in `L2_WRITEBACK=1` build switch: phase3-complete + `soc_bus_stress_test` (0 UVM_ERROR) + phase2 directed 16/16 incl. `soc_jtag_reset_recovery_test`, all green with write-back enabled. |

## Phase 4A: Readiness Gate And First Hardening

Deliverables:

- Accurate block status in docs and RTL headers. Block specs and RTL headers updated to reflect actual integration and CPU pipeline boundaries.
- `make dut-block-unit-gate` entry point that compiles and runs focused unit tests for `mips_mdu`, `apb_axi_dma`, `apb_vic`, `apb_uart_16550`, and `l2_cache` under `build/unit_tb/dut_block_readiness/`.
- Focused directed checks added for high-risk behavior: MDU signed/accumulate corner cases and divide-by-zero, DMA SG and AXI error termination, VIC low-offset compatibility and same-priority tie-break, UART DLAB/SCR and FIFO interrupt handling, and L2 dirty/error paths.
- All product smoke and UVM smoke gates pass with the new gate in place.

Acceptance:

- `make dut-block-unit-gate`
- `make firmware`
- `make uvm`
- `RUN_DIR=build/soc_test/dut_block_readiness FW_HEX=build/firmware/soc_smoke/firmware.hex tb/soc_test/run.sh`
- `git diff --check`

## Phase 4B MDU CPU ISA Closure

CLOSED in Phase 4B:
- Upgraded CPU MDU control plumbing to 4-bit `mips_mdu` operation encoding across `mips_control.v`, `mips_id_stage.v`, `mips_id_ex_reg.v`, `mips_ex_stage.v`, and `mips_cpu.v`.
- Decoded `MADD`, `MADDU`, `MUL`, `MSUB`, and `MSUBU` using the standard MIPS32 R2 SPECIAL2 opcode.
- Routed `MUL` low-word result through `ex_out` to GPR writeback (`rd`).
- Added dedicated `mdu_cpu` firmware test and `make mdu-cpu-gate` entry point.

## Phase 4C DMA Commercial Closure

CLOSED in Phase 4C:
- Hardened `apb_axi_dma` for direct copy, scatter-gather, error handling (`ERR_ALIGN`, `ERR_AXI_READ`, `ERR_AXI_WRITE`, `ERR_DESC`, `ERR_DESC_LIMIT`), busy reprogramming protection, bounded descriptor chains (`MAX_DESCRIPTORS=16`), and status W1C/re-arm semantics under the single-outstanding AXI fabric contract.
- Updated `docs/block_specs/dma_spec.md` with full commercial DUT specification.
- Extended `tb/unit/dma/tb_dma.v` unit test suite covering direct, SG, AXI error, alignment rejection, malformed descriptor, descriptor limit, busy protection, and W1C/IRQ test cases.
- Added product firmware test `tb/soc_test/fw/tests/dma_cpu/` and `make dma-cpu-gate` top-level entry point.
- Clarified non-claims: single-beat single-outstanding contract (no burst/multi-outstanding claim), no IOMMU/coherency claim, no formal/lint closure claim; coverage exclusion maintenance remains separate.

## Phase 4D VIC Commercial Closure

CLOSED in Phase 4D:
- Hardened `apb_vic` with deterministic single sequential state writers for all state registers (`active_r`, `edge_pending_r`, `soft_r`, `enable_r`, `type_r`, `polarity_r`, `prio_r`).
- Verified current SoC interrupt source map in `rtl/soc_peripheral_subsystem.v`:
  - Source 0: `uart_rx_int`
  - Source 1: `uart_tx_int`
  - Source 2: `timer_int`
  - Source 3: `dma_int`
  - Sources 4..31: tied low/reserved
- Verified priority arbitration with lower-ID tie-breaking, preemption, nesting via `ACTIVE` and `RUNNING_PRIO`, APB `VEC_ID` read accept event, repeated `VEC_ID` read protection, ACK clear, level/edge/soft trigger modes, and legacy map compatibility (`0x004` enable/mask, `0x008` masked pending).
- Extended `tb/unit/vic/tb_vic.v` unit test suite covering all 16 required commercial contract test cases.
- Added product firmware test under `tb/soc_test/fw/tests/vic_cpu/` and `make vic-cpu-gate` top-level entry point.
- Documented explicit non-claims: single-line IRQ + APB dispatch contract (no CPU EIC/VEIC claim), no MSI claim, no multicore routing claim, no formal proof claim; coverage exclusion maintenance remains separate.

## Phase 4E UART Commercial Closure

CLOSED in Phase 4E:
- Hardened `apb_uart_16550` for PC16550D-compatible DUT contract:
  - DLAB 0x00/0x04 register access separation (DLL/DLM vs RBR/THR/IER).
  - SCR scratchpad 8-bit read/write.
  - FCR FIFO enabled (1/4/8/14 trigger levels) vs FIFO disabled (1-byte compatibility mode with OE overrun on unread data).
  - Self-clearing FCR reset bits (`RCVR_RESET`, `XFR_RESET`).
  - RX character timeout interrupt after 4 character times when data is below threshold.
  - IIR priority order (LSI > RDA/CTI > THRE > MSR) with accurate FCR FIFO enable prefix.
  - Modem loopback and MSR delta bits cleared on MSR read.
  - Byte strobe `pstrb[3:0]` byte-lane selection contract.
  - APB `pready=1`, `pslverr=0`, and unsupported read 0 behavior.
- Extended `tb/unit/uart/tb_uart_16550.v` unit test suite covering all 15 required unit test cases.
- Added product firmware test under `tb/soc_test/fw/tests/uart_cpu/` and `make uart-cpu-gate` top-level entry point.
## Phase 4F L2 Commercial Closure

CLOSED in Phase 4F. Full acceptance sequence passed (`make dut-block-unit-gate`
5/5, `make l2-cpu-gate`, `make firmware`, `make uvm` default `soc_bus_stress_test`
with 0 UVM_ERROR / 0 SB_RESP, `soc_test run.sh` clean `$finish`, `git diff --check`
clean).

Follow-on fix (2026-07-29): the DUT default caching impl was switched to
**write-through / no-write-allocate** (`l2_cache_wt`). Enabling the write-back
caching FSM broke `soc_axi_attribute_cross_sweep_test` (SRAM-alias reads returned
0): the TB pulses async global `rst_n` mid-run (JTAG reset-recovery coverage), and
a write-back L2 holds written data as dirty until eviction, so a reset wipes it
before writeback — a silent write loss. Write-through forwards every write to SRAM
immediately, so nothing dirty is lost across reset. Write-back/write-allocate
(`l2_cache_caching`) stays available behind `SOC_L2_WRITEBACK`. Three latent
write-through defects were fixed at the same time (multi-beat write re-forwarding
AW → downstream deadlock; read-miss partial-line refill → stale 0 on un-fetched
words; line-crossing read burst not re-looking-up per beat), covered by
`tb/unit/l2/tb_l2_wt.v`. The DUT block unit gate compiles the WB impl explicitly
via `+define+SOC_L2_WRITEBACK` because its 16 unit contracts are write-back-specific
(write-allocate, dirty eviction, PLRU); the write-through path is validated at SoC
level. Re-verified end-to-end: phase3 completion gate PASS, DUT block unit gate
PASS, 0 UVM errors/fatals.

Follow-on fix (2026-07-29, reset-safety): the write-back impl `l2_cache_caching`
is now itself reset-safe, removing the liability the write-through switch worked
around. Previously its async `rst_n` branch cleared `valid_ram`/`dirty_ram`/
`plru_ram`, so a warm reset pulse dropped committed dirty lines before writeback.
Fix: those arrays (with `tag_ram`/`data_ram`, already retention) are now retention
memory — initialized once at cold boot via an `initial` block and NOT wiped by
warm `rst_n`; only the FSM control state resets. This is symmetric with the SoC
SRAM model (`rtl/perips/axi_sram.v`), which is why write-through worked: SRAM is a
retention memory across the reset pulse. Added `tb/unit/l2/tb_l2.v` Test 19 (write
dirty line → pulse `rst_n` → readback must L2-hit with the pre-reset value and
issue no downstream AR). Verified: `make dut-block-unit-gate` 5/5 (L2 19/19 with
`+define+SOC_L2_WRITEBACK`); write-through `tb_l2_wt.v` still `WT_TEST_SUCCESS`.
Write-through remains the DUT default; write-back is opt-in via `SOC_L2_WRITEBACK`.

Follow-on fix (2026-07-29, write-back SoC signoff): write-back is now signed off at
SoC level, not just block level. Added an opt-in `L2_WRITEBACK=1` build switch to the
UVM/soc_test compile scripts and the Makefile `uvm`/`phase3-complete`/`soc-smoke`
recipes (appends `+define+SOC_L2_WRITEBACK`; default unchanged = write-through). The
concern noted below — "the scoreboard treats SRAM as authoritative, which write-back
defers" — was investigated and found NOT to hold: `tb/uvm_tb/env/soc_scoreboard.sv`
builds its SRAM content model entirely from AXI taps UPSTREAM of the L2 (external
master port for content via `update_sram_model`/`check_sram_read_data`; fabric `s0`
for responses/DMA) and never reads physical SRAM. Since L2 is the single coherence
point all masters funnel through and returns dirty data on read hits, the upstream
model stays consistent regardless of when L2 flushes downstream — no scoreboard change
needed. Verified with `L2_WRITEBACK=1`: `make phase3-complete` PASS (8 directed +
CPU/CP0 gate), `make uvm` (soc_bus_stress_test) 0 UVM_ERROR / 0 UVM_FATAL, `make
soc-smoke` PASS, and the phase2 directed list 16/16 PASS — critically including
`soc_jtag_reset_recovery_test`, which injects the async `rst_n` pulses that directly
exercise the reset-safety retention fix. Both L2 policies now pass at SoC level;
write-through stays the default.

Two defects from the prior rejected attempt were fixed during closure:
- Removed an ungated per-cycle `$display("[L2 FSM] ...")` debug statement from the
  `l2_cache_caching` sequential FSM.
- Fixed a sample/drive race in the `tb/unit/l2/tb_l2.v` `cache_write_raw` helper
  that latched `WLAST` one beat early on a line-crossing write burst (the DUT FSM
  already services line-crossing bursts correctly by re-looking-up per beat; the
  reported `SB_RESP` regression did not reproduce on the current tree).

- Hardened `l2_cache` / `l2_cache_caching` under the current single-outstanding blocking contract:
  - Strict validation of upstream AXI requests, returning deterministic `SLVERR` (`2'b10`) for unsupported size, burst type, length, unaligned address, or line-crossing burst.
  - Downstream `RRESP`/`BRESP` error propagation with no invalid line installation on refill error and dirty victim preservation on eviction error.
  - Single-outstanding rejection and backpressure (`s_arready=0`, `s_awready=0` while a request is active).
  - Continuous `s_rvalid` assertion during multi-beat read hit bursts.
  - Reserved snoop tie-off without side effects.
- Extended `tb/unit/l2/tb_l2.v` to cover all 16 required commercial unit test cases.
- Added product firmware gate `tb/soc_test/fw/tests/l2_cpu/` and `make l2-cpu-gate` top-level entry point.
- Updated `docs/block_specs/l2_spec.md`, `docs/commercial_dut_block_readiness_plan.md`, and `docs/refactor_roadmap.md`.
- Documented explicit non-claims: non-blocking L2, MSHR, writeback buffer, multi-outstanding AXI, coherent snoop/directory, ECC/SECDED, formal proof, and coverage exclusion maintenance.

## Follow-On Phases

- Phase 4G+: MSHR, writeback buffer, coherency/snoop, ECC/parity, formal AXI
  protocol binders, performance counters, and performance regression.
