# QEMU System-Mode Differential Closure

> Temporary execution tracker. This document is intentionally separate from
> product signoff claims and will be folded into the permanent evidence
> registry only after the gates below have reproducible reports.

## Scope

Close the gap between the project bare-metal RTL and QEMU system-mode:

1. Run the exact bare-metal ELF on `mips32-soc-ref`.
2. Model the RTL-visible SRAM, APB, QSPI/XIP, and DDR behavioral contracts.
3. Capture one architectural retire record per instruction from both sides.
4. Compare GPR, CP0, memory, exception, interrupt, and mailbox behavior.

Default RTL configuration remains unchanged (`MMU=0`, blocking cache).
QEMU user-mode reference regression remains a separate Linux-user path.

## Status

### 2026-08-31 QEMU build recovery and bounded machine gate

The official QEMU 9.2.0 source tree was restored and the project custom
machine was rebuilt successfully. The resulting system binary reports
`QEMU emulator version 9.2.0`, advertises `mips32-soc-ref`, and passes
`make qemu-system-sram-uart-mailbox-gate` plus
`make qemu-system-peripheral-contract-gate`. The build helper now defaults to
`QEMU_BUILD_JOBS=1` and verifies the executable exists before recording its
input stamp, reducing host-memory pressure during recovery builds.

This closes the QEMU build and bounded machine-model prerequisite plus the
selected FPU state differential corpus. It does not close full
ISA/MMU/Linux lockstep, complete IEEE-754/FPU ABI behavior, or physical
DDR/QSPI behavior.

The fresh FPU differential initially identified a QEMU translator field
mapping defect in COP1X indexed memory: MIPS32 R2 uses `rd` as the FPR
destination/source, while the upstream call site passed `sa`. The project
QEMU patch `qemu-9.2-mips32-cop1x-memory-fields.patch` corrects this mapping.
The RTL FPU primitive also had an incorrect `SQRT.S` inexact comparison
(`sqrt(x)` was compared with `sqrt(x)^2`); that is now corrected, and the
trace corpus leaves enough retirement spacing to expose back-to-back FPR
updates. The fresh rerun with bounded state matching passes:
`TRACE_COMPARE_PASS records=1320` and
`qemu-system-fpu-single-differential-gate: PASS`.
The FPU state matcher uses a bounded 12-retire-record window for the observed
ID-to-WB snapshot latency; it is not a general trace resynchronization rule.
The double corpus also passes with `TRACE_COMPARE_PASS records=297`, including
the selected `SQRT.D` result check,
the MIPS default-NaN result for invalid `DIV.D 0/0`.

| Slice | State | Evidence | Remaining |
| --- | --- | --- | --- |
| QEMU system binary | DONE | `make qemu-system-mips32-soc-ref` | None for build readiness |
| SRAM/kseg aliases | DONE | `build/isa_ref/qemu_system_smoke/completion_report.md` | Differential smoke |
| UART TX/LSR | PASS | `build/isa_ref/qemu_system_smoke/qemu_stdout.log` | RTL/QEMU compare |
| Exit mailbox | PASS | `build/isa_ref/qemu_system_smoke/completion_report.md` | Negative mailbox case |
| GPIO | PASS | `build/isa_ref/qemu_system_peripherals/completion_report.md`, `build/isa_ref/qemu_system_gpio_input/completion_report.md` | external pin electrical/synchronizer model remains abstract |
| Timer | PASS | `build/isa_ref/qemu_system_peripherals/completion_report.md`, `build/isa_ref/qemu_system_gpio_input/completion_report.md` | virtual-clock behavioral model; physical clock signoff remains open |
| PIC | PASS | `build/isa_ref/qemu_system_peripherals/completion_report.md`, `build/isa_ref/qemu_system_vic_full_sources_differential/completion_report.md` | selected priority/replay and 32-source contract pass; arbitrary OS nesting remains open |
| DMA | PASS (RTL v1/v2 contract; QEMU v1/v2 model implemented) | `build/soc_test/dma_cpu_gate/sim.log`, `build/isa_ref/qemu_system_dma_v2_differential_pass_final2/completion_report.md` | Full long-form retire differential remains bounded by implementation-dependent RTL status-poll latency; physical AXI timing and Linux DMA ABI remain open |
| QSPI/XIP | PASS (RTL x1/quad contract; QEMU transaction-level command/FIFO model) | `build/unit_tb/qspi_cmd_behavioral/sim.log`, `build/unit_tb/qspi_axi_xip_quad/sim.log`, `build/isa_ref/qemu_system_qspi/completion_report.md` | QEMU covers APB command/FIFO, x1/quad image-backed reads, TX/RX, IRQ/DONE W1C, abort and timeout; pin timing, PHY, JEDEC behavior, erase/program and physical-device signoff remain open |
| DDR | PASS (RTL protocol/ECC contract; QEMU behavioral window model) | `build/unit_tb/axi_ddr4_controller_stress/sim.log`, `build/unit_tb/ecc_secded_32/sim.log`, `build/isa_ref/qemu_system_ddr/completion_report.md` | QEMU covers status/version/error/W1C and cached/uncached access to the 128 MiB behavioral window; PHY training, JEDEC timing, physical refresh/ECC device behavior and board signoff remain open |
| System retire trace | PASS | `build/isa_ref/qemu_system_retire/completion_report.md` | broader exception/interrupt corpus |
| RTL/QEMU baseline differential | PASS | `build/isa_ref/qemu_system_differential/completion_report.md` | 10 retire records through a minimal SRAM/mailbox guest's magic-mailbox-store retirement boundary |
| RTL/QEMU architectural differential | PASS (selected system corpus) | `make qemu-system-retire-differential-gate`, exception/BD/peripheral/VIC gates | Baseline, CP0 syscall/ERET, branch-delay BD/EPC, GPIO/timer/DMA/QSPI/DDR, VIC IRQ, and full `vic_cpu` corpus now have dedicated RTL/QEMU retire evidence; full ISA compliance, physical interrupt timing, and production device behavior remain open |
| ISA-R2 retire differential CPU capability split | PASS | `make qemu-system-isa-r2-differential-gate`, `build/isa_ref/qemu_system_isa_r2_differential/qemu/trace_compare.log` (`TRACE_COMPARE_PASS records=454`) | Default integer RTL contract uses QEMU `24Kc` (`Config1.FP=0`); the custom machine aligns bare-metal `PRId=0x00019300` and `Config1=0xfe231180` with the RTL, while FPU opt-in uses `24Kf` explicitly. Full ISA and privileged/MMU differential remain open |
| QEMU CPU capability default | PASS | `build/isa_ref/qemu_system_isa_r2_differential_default_fixed/qemu/trace_compare.log` (`TRACE_COMPARE_PASS records=324`) | `mips32-soc-ref` direct invocation now defaults to `24Kc`; `Config1=0xfea83480` is observed before the retire comparison. FPU remains opt-in via explicit `24Kf` |
| Branch-likely RTL/QEMU differential | PASS | `make qemu-system-branch-likely-differential-gate` | 49 effective retire records compare through the mailbox boundary. QEMU plugin annulled-slot events are filtered by the preceding likely condition; full ISA compliance remains open. |
| RTL/QEMU syscall exception differential | PASS | `build/isa_ref/qemu_system_exception_differential/completion_report.md` | delay-slot BD and broader exception/MMU corpus remain open |
| RTL/QEMU MMU process-pressure contract | PASS (selected pass boundary) | `build/isa_ref/qemu_system_mmu_process_pressure_final/completion_report.md` | Four ASIDs, distinct PFNs, dynamic shootdown and post-shootdown refills run on both producers; Linux VM ownership and multicore shootdown remain open |
| RTL/QEMU MMU demand-page per-retire differential | PASS (opt-in bounded contract) | `build/isa_ref/qemu_system_mmu_refill_capture_final5/completion_report.md`, `trace_compare.log` (`TRACE_COMPARE_PASS records=3288`), `build/soc_test/mmu_refill_final/sim.log` | Four 4-KB demand pages, APB demand mapping, TLB pair merge, 64-entry CP0 Index use, permission fault, ERET retry, and completion marker compare one retire stream; Linux VM ownership, multicore shootdown, larger page-size corpus, and full privileged/MMU compliance remain open |
| RTL/QEMU branch-delay exception differential | PASS | `build/isa_ref/qemu_system_bd_exception_differential/completion_report.md` | 16 records: taken-branch delay-slot syscall, BD/EPC capture, EPC+8 recovery, mailbox |
| RTL/QEMU peripheral differential | PASS (selected QEMU model) | `build/isa_ref/qemu_system_peripheral_differential_ddr_status_fix2/completion_report.md` and `peripheral_scope.md` | Selected 115-record corpus: GPIO, timer control, legacy DMA status, QSPI version/status/XIP, DDR version/status/error/W1C, mailbox. Dedicated QEMU model gates now cover QSPI command/FIFO and DDR window; full retire differential and physical device behavior remain open |
| QEMU VIC machine-model firmware | PASS | `build/firmware/qemu_system_vic_cpu/firmware.elf` | Existing `vic_cpu` firmware reaches UART success under `mips32-soc-ref`; model covers enable set/clear, SOFT/SOFT_CLR, priority, VEC_ID accept, ACK, and CPU IRQ delivery |
| RTL/QEMU VIC interrupt differential | PASS | `build/isa_ref/qemu_system_vic_irq_differential/completion_report.md` | 48 records: simultaneous software sources 8/9, deterministic priority 9 then 8, VEC_ID accept, ACK/SOFT_CLR, two CPU interrupt entries/ERET returns, magic mailbox |
| Full `vic_cpu` RTL/QEMU differential | PASS (corpus uses direct caller MMIO loads) | `build/isa_ref/qemu_system_vic_cpu_differential_fix1/completion_report.md`, `trace_compare.log` | 736 records compare equal and both sides reach success; source traces contain 737 records on each side. The firmware avoids the currently open CPU subroutine-return/load forwarding bug; generic forwarding and full arbitrary firmware coverage remain open. |
| Opt-in FPU startup/CP1/COP1X differential | PASS | `make qemu-system-fpu-single-differential-gate`, `make qemu-system-fpu-double-differential-gate` | CP0 CU1 enable/readback, single COP1 arithmetic/conversion, COP1X `MADD.S/MSUB.S/NMADD.S/NMSUB.S`, and selected double pair arithmetic/conversion including COP1X `MADD.D/MSUB.D/NMADD.D/NMSUB.D` compare through the mailbox boundary; fresh traces pass with 1320 and 225 records respectively. Complete FPE/IEEE-754 and OS FPU context remain open. |
| Opt-in FPU CU1 negative differential | PASS | `make qemu-system-fpu-cu1-exception-differential-gate`, `build/isa_ref/qemu_system_fpu_cu1_exception_differential/completion_report.md` | COP1 with CU1 disabled retires the same CpU exception as QEMU, including Cause.CE=1; full FPE/double precision/OS context remains open. |
| Opt-in SRS exception entry/return differential | PASS | `make qemu-system-srs-exception-differential-gate`, `build/isa_ref/qemu_system_srs_exception_differential/completion_report.md`, `qemu/trace_compare.log` | 42 retire records compare equal across `PSS/CSS/ESS`, `RDPGPR`, exception entry, handler execution and `ERET`; SRSMap and nested-fault policy are covered by their dedicated gates; external EICSS/VEIC policy and Linux SRS ABI remain open. |
| Opt-in nested SRS exception differential | PASS | `make qemu-system-srs-nested-differential-gate`, `build/isa_ref/qemu_system_srs_nested_differential/completion_report.md`, `qemu/trace_compare.log` | Nested `SYSCALL` while EXL is set preserves CSS/PSS and original exception context; the RTL and QEMU traces compare equal through the success mailbox. |

The VIC differential gate also covers the precise-response fix in the RTL
blocking CPU path: an APB load response is committed while an unrelated IF
stall is present, and interrupt acceptance is deferred while a MEM transaction
is active. This prevents the first handler `VEC_ID` load from being flushed
after the VIC side effect has already returned data.

The bounded MMU and cache follow-up gates were also rerun during this closure
pass: `mmu-page-table-allocator-gate`,
`mmu-ipi-shootdown-pressure-gate`, and
`l1-nonblocking-cpu-multi-gate` pass. Their existing residual boundaries are
unchanged: page-table memory/PTE ownership and demand paging are not yet an
OS implementation, shootdown is not a multicore end-to-end coherency test,
and L1 nonblocking remains opt-in with maintenance/coherency stress open.

The bounded RTL/QEMU MMU retire closure was completed on 2026-08-17. The
standalone SoC produced 3279 RTL records and the same ELF reached
`mmu_refill: PASS` on `mips32-soc-ref`; the comparator passed 3288 common
records through the MMU completion marker. The opt-in QEMU profile now uses a
64-entry TLB context, does not pre-install the APB mapping, and routes refill
through the RTL vector contract. The firmware restores EntryHi after TLBR
before merging a pair, matching MIPS TLBWI semantics. The comparator excludes
only producer-specific fault-bus/GPR artifacts and mem_be encoding; instruction,
control-flow, CP0 writes, exceptions, addresses, and architectural data remain
checked. This closes the bounded 4-KB demand-page/MMU differential, not Linux
VM ownership, multicore shootdown, larger page-size coverage, or full
privileged/MMU compliance.
| `current-contract-signoff` | FAIL (coverage threshold) | `build/signoff/current_contract/current_contract_signoff_report.md` | Fresh 2026-08-12 run passed Phase 2 directed/coverage and Phase 3A directed, then failed the existing 99% coverage thresholds; see closure blockers below. |

The first dedicated smoke guest and gate are now implemented. The status is
updated to `PASS` only after `make qemu-system-sram-uart-mailbox-gate` has
completed in the current workspace.

The APB behavioral gate is now implemented and passing with evidence in
`build/isa_ref/qemu_system_peripherals/`. The selected RTL/QEMU peripheral
retire differential is also passing in
`build/isa_ref/qemu_system_peripheral_differential_ddr_status_fix2/`; its
115-record corpus covers register-level GPIO, virtual-clock timer, immediate
DMA copy/status, QSPI version/status and image-backed XIP, DDR
version/status/error/W1C, and mailbox retirement. It does not claim QSPI
command/FIFO/quad/retry, DDR PHY/JEDEC behavior, physical pin timing, or full
architectural differential closure.

The system-mode capture gate verifies QEMU instruction and memory events plus
per-instruction state-boundary callbacks. The project-owned QEMU build supplies
the MIPS core register XML, so the plugin obtains GPR and selected CP0 state.
The baseline differential uses a deliberately minimal guest and compares every
retired instruction through the mailbox-store retirement boundary. It does not
constitute CP0, exception, interrupt, MMU, or full-system differential closure.

The mailbox boundary is a store of `0xDEADBEEF` to the mailbox address, not an
arbitrary write to physical `0x0000FFFC`. The latter aliases normal SRAM and is
used by the standard firmware stack, so treating it as an exit creates a false
positive truncated trace.

## Execution Order

### 1. Baseline differential (PASS)

- The `qemu_system_lockstep_min` guest performs arithmetic, SRAM write/read,
  and a success mailbox store.
- `make qemu-system-retire-differential-gate` compares 10 committed records,
  with only the documented kseg0/kseg1 direct-map alias normalization.
- The gate stops both streams at the mailbox-store retirement boundary so QEMU
  host exit timing cannot mask or create an architectural mismatch.

### 2. APB foundation (DONE for the bounded reference contract)

- GPIO, deterministic virtual-clock timer, and PIC models are implemented in
  `scripts/qemu/mips32_soc_ref.c`.
- MMIO state is resettable and deterministic; directed GPIO/timer, PIC and
  full-source priority tests have passing reports.
- External pin synchronization, physical timer clock behavior, and arbitrary
  OS interrupt nesting remain outside this reference-machine contract.

### 3. Data movers and memories (DONE for the bounded behavioral contract)

- DMA copy/status/error/reset and v2 event behavior are implemented and have
  RTL/QEMU contract evidence.
- Image-backed QSPI APB/XIP x1 and quad command/FIFO behavior is implemented;
  timeout, abort, IRQ/DONE W1C and shared model state are covered.
- DDR behavioral memory plus controller status/error/performance registers are
  implemented and covered with the RTL protocol/ECC contract.
- Physical DDR PHY/JEDEC timing, physical QSPI device timing/erase/program,
  and full unrestricted RTL retire differential remain product-level residuals.

### 4. Exception differential (PASS)

- `make qemu-system-exception-differential-gate` compares the syscall guest
  through mailbox retirement, including the general vector, Cause/EPC reads,
  EPC update, and ERET return.

### 5. Full differential orchestration (PASS for current system corpus)

- The same bare-metal ELF is run on RTL and QEMU for each selected guest.
- RTL interrupt schedules are exported by retire index and replayed in QEMU
  for the full `vic_cpu` gate.
- The QEMU MIPS translator injects a retire-tick helper at one-instruction TCG
  boundaries; the schedule replay is therefore tied to architectural retire
  progress rather than host wall-clock timing.
- Architectural records and device-visible outputs compare through each
  guest's mailbox boundary. Evidence includes compile/runtime logs, guest
  hashes, QEMU traces, and trace comparison reports.

### 6. VIC interrupt differential (PASS for selected corpus)

- The QEMU model now implements the RTL `apb_vic` software-pending and
  priority/active contract and passes `vic_cpu` as a system-mode guest.
- `qemu_system_vic_irq` compares 48 records through magic mailbox retirement:
  it exercises simultaneous software sources 8/9, deterministic priority
  selection (9 then 8), VEC_ID accept, ACK/SOFT_CLR, two exception entries,
  and ERET. The QEMU and RTL producers represent an asynchronous redirect on
  different adjacent records, so its transition marker and next-PC field are
  compared by the common following vector instruction instead of an arbitrary
  producer-local Cause/IP update.
- The broader `vic_cpu` firmware reaches UART success and the magic mailbox in
  both RTL and QEMU. The current corpus uses direct caller-side MMIO loads for
  VIC readbacks because the generic CPU subroutine-return/load forwarding path
  is still open. With that explicit corpus constraint, the retire stream
  compares equal through the mailbox boundary: 736 records, with RTL IRQ
  schedule replay. This closes the selected VIC interrupt contract, but does
  not claim generic jal/load forwarding, external physical interrupt timing,
  VEIC vectors, nested schedules, or device error-path closure.

## Gate Naming

- `qemu-system-sram-uart-mailbox-gate`
- `qemu-system-gpio-timer-gate`
- `qemu-system-dma-pic-gate`
- `qemu-system-qspi-gate`
- `qemu-system-ddr-gate`
- `qemu-system-current-contract-gate`
- `qemu-system-retire-differential-gate`
- `qemu-system-isa-r2-differential-gate`
- `qemu-system-current-contract-gate`

## Completion Rule

Do not mark this work closed until every gate has a report with compile log,
runtime log, trace comparison result, guest ELF hash, QEMU build identity, and
an explicit residual-risk section. A passing user-mode reference or a booting
QEMU machine alone is insufficient.

## Closure Blockers

### MMU system-mode contract update (2026-08-13)

The selected QEMU system-mode MMU contract is now passing through the
`qemu-system-mmu-contract-gate` evidence at
`build/isa_ref/qemu_system_mmu_contract/`. The gate runs the RTL ASID/refill
and shootdown test and the same ELF on `mips32-soc-ref`; both reach their
architectural success boundary. The QEMU model now invalidates its translated
shadow TLB on shootdown ACK, preserving CP0 TLB state so the guest refill
handler is exercised after invalidation.

This closes only the bounded selected contract. It does not close a
per-retire RTL/QEMU MMU comparison, demand paging with OS-owned page tables,
Linux boot, or multicore shootdown stress.

### Current-contract aggregate and architecture rerun (2026-08-13)

`make qemu-system-current-contract-gate` passes. The aggregate includes the
QEMU peripheral contract, DMA v2 model, QSPI command/FIFO model, DDR
behavioral window, and retire capture. A fresh architecture rerun also passes
the ISA-R2 retire differential, MMU contract, four-ASID process-pressure,
single-precision FPU, and CU1-disabled FPU exception gates. These reports
close the selected executable contracts only; they do not change the explicit
full-ISA, full-MMU differential, Linux, or physical-device residual risks.

## Architecture Closure Update (2026-08-10)

### ISA R2 retire differential (PASS)

- The ISA R2 sweep now includes SPECIAL3 `EXT`/`INS`. The RTL decoder and
  QEMU state decoder agree on the architectural encodings (`EXT` encodes
  `size-1` in `rd`; `INS` encodes `msb` in `rd`).
- Evidence: `build/isa_ref/qemu_system_isa_r2_extins_final/completion_report.md`
  and `qemu/trace_compare.log` (`TRACE_COMPARE_PASS records=323`).
- This remains an implemented-subset differential, not full ISA compliance.

- The same corpus includes `PREF` as a no-result hint; QEMU and RTL compare
  equal through 324 retire records in
  `build/isa_ref/qemu_system_isa_r2_pref_final/qemu/trace_compare.log`.

`make qemu-system-isa-r2-differential-gate` compares the selected
`isa_r2_sweep` bare-metal corpus through its mailbox store. The current run
produced 324 matching retire records. It covers the implemented R2
CLZ/CLO/SEB/SEH/WSBH/ROTR/ROTRV/MOVN/MOVZ/BAL operations and static CP0
PRId/Config0/Config1/EBase reads. The custom QEMU machine explicitly resets
those CP0 static identity/geometry registers to the RTL contract and
preserves the selected CPU capability: the default path selects `24Kc` and
reports `Config1.FP=0`, while FPU gates select `24Kf`. Evidence is retained
at `build/isa_ref/qemu_system_isa_r2_differential/`.

The comparison also fixed the RTL pipeline's link-value forwarding: link
instructions carry PC+8 through EX/MEM so a target instruction can consume
`$ra` immediately after its delay slot. The retirement trace derives access
byte lanes from the retired opcode and address. Full ISA/FPU compliance,
uncovered privileged/MMU behavior, and arbitrary interrupt timing remain
outside this selected corpus.

`BITSWAP` is intentionally excluded from the MIPS32r2 differential corpus.
QEMU 9.2 gates the legacy SPECIAL3 encoding behind `ISA_MIPS_R6`; available
R2 CPU profiles raise RI. The RTL capability is covered independently by
`make bitswap-gate`; this exclusion applies only to QEMU differential
evidence.

The opt-in micro-TLB integration gap is closed for the current RTL/SoC
contract. `make product-mmu-micro-tlb-gate` runs two real SoC workloads with
`SOC_MICRO_TLB_ENABLE=1`: `product_mmu_boot` observes a D-side micro-TLB hit
after software TLB refill, and `product_tlb_vectors` observes an I-side hit on
the translated instruction path. The default `SOC_MICRO_TLB_ENABLE=0` product
MMU boot was rerun and passed unchanged. Block coverage remains provided by
`make micro-tlb-gate` for refill, ASID, eviction, page sizes, permissions and
flush. This does not close full MMU demand paging, OS shootdown policy, or
performance signoff.

The CPU-facing L1 nonblocking work is now closed for its selected opt-in
contract independently of the QEMU differential gates: the real CPU/D-cache
path passes dirty eviction, sub-word load formatting, three-seed
reset-in-flight stress, precise refill error recovery, ROB unit regression,
and RTL frontend elaboration. This does not extend QEMU claims to full
nonblocking CPU lockstep, arbitrary multi-error/reset traffic, Linux, or full
ISA/MMU differential.

The standalone opt-in L1 nonblocking transaction block now retains one
secondary request per MSHR instead of dropping merged IDs. Its directed gate
checks a shared-refill two-response sequence as well as two distinct lines
completing out of order. It remains explicitly `BLOCK_VERIFIED`: the CPU's
architectural D-cache interface is still blocking, so no CPU/SoC hit-under-
miss claim is made.

The fresh `make current-contract-signoff` run on 2026-08-12 completed every
functional stage but failed `COVERAGE_THRESHOLDS`. The authoritative report is
`build/signoff/current_contract/current_contract_signoff_report.md`; the latest
run recorded the following actual merged values versus the required 99%:

| Scope | Failing metrics |
| --- | --- |
| UVM merged | SCORE 72.00%, COND 96.96%, TOGGLE 65.87%, FSM 37.33%, BRANCH 59.93% |
| Product CPU/CP0 | SCORE 70.02%, LINE 86.56%, TOGGLE 64.60%, FSM 37.69%, BRANCH 61.40% |

The same run also emitted fresh URG exclusion checksum mismatches and an
invalid branch vector in the committed exclusion files. Functional PASS and
coverage metadata hygiene are therefore tracked separately; no threshold or
exclusion semantics were changed to obtain this result.

URG also reported numerous checksum mismatches and an invalid branch vector in
the committed exclusion files. These must be audited against the freshly
generated VDBs. The failure is intentionally retained: no threshold reduction
or exclusion change may be used to turn this run into a signoff pass.
