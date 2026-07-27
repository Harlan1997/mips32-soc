# TASK-009 Spec: Phase 4F L2 Current-Contract Commercial Closure

## Objective

Harden the already-integrated `l2_cache` DUT block into a commercial-quality
current-contract L2 cache baseline for this SoC.

This task must close the RTL-visible and product-testable contract of the
current 128 KB, 8-way, 32-byte-line, write-back/write-allocate, NINE,
single-outstanding blocking L2 cache.

Do not claim non-blocking L2, 8-entry MSHR, multi-outstanding AXI, coherent
snoop/directory protocol, ECC/SECDED, synthesis/timing, formal proof, or
board-level performance signoff in this task unless the required fabric/L1/SoC
contracts and verification are also implemented. Those remain future Phase 4G+
architecture extensions.

## Required RTL Contract

Keep the current external module interfaces and SoC integration stable unless a
change is strictly required for a bug fix and is fully propagated:

- `rtl/cache/l2_cache.v`
- `rtl/cache/l2_cache_caching.v`
- `rtl/soc_memory_subsystem.v` only if an integration bug requires it

Required current-contract behavior:

- Geometry and policy:
  - default 128 KB capacity, 8 ways, 32 B line, 8 32-bit words per line.
  - write-back and write-allocate.
  - pseudo-LRU replacement.
  - NINE single-core policy; no reverse L1 invalidation claim.
- AXI upstream contract:
  - single slave-side request accepted at a time.
  - accept aligned 32-bit INCR bursts that do not cross a 32 B L2 line.
  - reject or return deterministic `SLVERR` for unsupported burst type, size,
    length, unaligned address, or line-crossing burst instead of silently
    corrupting cache state.
  - hold response valid until upstream ready.
  - keep IDs deterministic for accepted requests.
- AXI downstream contract:
  - issue only one downstream transaction at a time.
  - refill and dirty eviction use 8-beat 32-bit INCR line transactions
    (`ARLEN/AWLEN=7`, `ARSIZE/AWSIZE=2`, `BURST=INCR`).
  - propagate downstream `RRESP`/`BRESP` errors to upstream.
  - on refill error, do not install a valid line.
  - on dirty eviction error, preserve the dirty victim and do not overwrite it
    with the new line.
- Hit/miss behavior:
  - cold miss refills a line and returns the requested beat.
  - same-line read hit must not issue a downstream AR.
  - write hit merges byte strobes and marks dirty.
  - write miss refills then merges write data and marks dirty.
  - clean victim replacement must not issue downstream writeback.
  - dirty victim replacement must write back the old line before refill.
  - multi-beat read and write bursts within one line must return/merge all
    beats correctly, including backpressure.
- Reset and tie-offs:
  - reset clears valid/dirty state and returns the FSM to idle.
  - snoop port remains an explicit tie-off in current contract:
    `snoop_ack = snoop_valid`, `snoop_hit = 0`, and snoop must not perturb the
    cache FSM or arrays.

Optional but preferred if it can be done without interface churn:

- Lightweight internal debug counters under `translate_off` or unit-test-only
  observability for hits, misses, dirty writebacks, and error responses. Do not
  expose a new architectural CSR unless the SoC memory map and firmware gate
  are updated coherently.

## Required Unit Verification

Extend `tb/unit/l2/tb_l2.v` into an explicit commercial unit gate. It must fail
loudly with `FAIL` output and finish with `REGRESSION_TEST_SUCCESS l2_cache`
only when all checks pass.

Cover at least:

- reset defaults and first cold miss.
- read miss/refill and same-line read hit with no downstream AR.
- write hit byte-strobe merge and dirty marking.
- write miss allocate/merge/readback.
- multi-beat read burst fully inside one line.
- multi-beat write burst fully inside one line with byte strobes.
- unsupported upstream requests:
  - unaligned address,
  - unsupported size,
  - non-INCR burst,
  - line-crossing burst,
  - unsupported length.
  Each must return deterministic error and must not install or corrupt a line.
- upstream read backpressure and write-response backpressure.
- downstream AR/R backpressure and AW/W/B backpressure.
- 8-way fill and pseudo-LRU/victim rotation sufficient to force replacement.
- clean victim replacement without writeback.
- dirty victim replacement with full 8-beat writeback.
- downstream refill error propagation and no invalid line install.
- downstream dirty eviction `BRESP` error propagation and dirty victim
  preservation.
- snoop tie-off and no side effects during active/idle cache states.
- single-outstanding rejection/backpressure: a second AR/AW must not be
  accepted while a request is active.

The existing `make dut-block-unit-gate` must keep all five DUT block unit tests
passing.

## Required Product Firmware Gate

Add a focused product-level L2 gate:

- firmware under `tb/soc_test/fw/tests/l2_cpu/`
- script `tb/soc_test/run_l2_cpu_gate.sh`
- top-level Makefile target `make l2-cpu-gate`

Firmware should verify the SoC-visible L2 path without relying on private
testbench hierarchy:

- cached memory read/write data integrity over a region larger than L1 D-cache
  and spanning enough lines to exercise L2 refill/hit behavior.
- byte/half/word store merge correctness as observed by CPU loads.
- conflict/eviction-style sweep that stresses multiple addresses mapping to
  the same L2 set when practical.
- cached and uncached alias interactions must be documented carefully. If the
  CPU/L1 cache hierarchy lacks architectural flush/invalidate support for a
  fully deterministic alias coherency test, do not overclaim it; keep the
  firmware gate to CPU-visible data integrity and stress.

Failure must write product failure magic `0xDEADDEAD` or otherwise cause
`REGRESSION_TEST_FAILED`. Gate scripts must reject false passes by checking:

- no `REGRESSION_TEST_FAILED`
- no `FAIL:`
- required `REGRESSION_TEST_SUCCESS`
- zero simulator exit status

## Documentation Requirements

Update:

- `docs/block_specs/l2_spec.md`
- `docs/commercial_dut_block_readiness_plan.md`
- `docs/refactor_roadmap.md`

Documentation must clearly distinguish:

- Phase 4F closed current single-outstanding blocking L2 contract.
- exact unsupported request/error policy.
- dirty eviction/refill error preservation semantics.
- product firmware gate scope.
- future work: MSHR, writeback buffer, coherent snoop/directory, ECC/SECDED,
  performance counters/CSRs, formal proof, synthesis/timing, and coverage
  exclusion maintenance.

Do not modify coverage exclusion files in this task.

## Allowed Paths

AGY may edit only:

- `Makefile`
- `rtl/cache/l2_cache.v`
- `rtl/cache/l2_cache_caching.v`
- `rtl/soc_memory_subsystem.v`
- `docs/block_specs/l2_spec.md`
- `docs/commercial_dut_block_readiness_plan.md`
- `docs/refactor_roadmap.md`
- `tb/unit/l2/tb_l2.v`
- `tb/unit/run_dut_block_unit_gate.sh`
- `tb/soc_test/run_l2_cpu_gate.sh`
- `tb/soc_test/fw/Makefile`
- `tb/soc_test/fw/tests/l2_cpu/**`
- `.agent/test_report.md`
- `.agent/result.json`

AGY must not edit `.agent/tasks.json`, coverage exclusion files, unrelated CPU,
L1 cache, fabric, peripheral RTL, UVM infrastructure, or generated/historical
run artifacts.

## Acceptance Commands

AGY must run and report:

```bash
make dut-block-unit-gate
make l2-cpu-gate
make firmware
make uvm
RUN_DIR=build/soc_test/phase4f_l2_cpu \
  FW_HEX=build/firmware/soc_smoke/firmware.hex \
  tb/soc_test/run.sh
git diff --check
```
