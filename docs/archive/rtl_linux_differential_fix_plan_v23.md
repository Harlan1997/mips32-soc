# QEMU Linux Terminal Closure Plan v23

Plan date: 2026-09-28  
Status: `QEMU CLOSED / RTL DECLARED USERSPACE CLOSED / DEFAULT BLOCKING RTL-QEMU DECLARED LINUX DIFFERENTIAL PASS`
Supersedes: `docs/rtl_linux_differential_fix_plan_v22.md`

This revision changed the immediate execution target from a coupled RTL/QEMU
terminal run to a standalone, compact QEMU closure. The independent current
RTL generic-userspace gate reaches the terminal marker. A later coupled strict
stream run completed the declared Linux workload through its terminal marker
and passed the architectural comparison for the default blocking RTL
configuration. The recorded scope does not include nonblocking RTL Linux or
unrestricted ISA/OS compliance.

## 1. QEMU closure objective

Close the declared generic Linux image through the unique
`MIPS32_SOC_LINUX_TERMINAL` userspace marker with the exact kernel, DTB,
Boot ROM/DDR image identity, command line, machine properties, and
deterministic entropy seed. The executable entry point is:

```bash
tb/isa_ref/run_qemu_linux_terminal_closure_gate.sh
```

The gate uses summary-only plugin capture. It records the retired-instruction
count through the terminal event and the complete UART peripheral JSONL, but
does not materialize the roughly 150M-record architectural trace.

The repository-level entry point is `make qemu-system-linux-full-closure-gate`;
`qemu-system-linux-terminal-closure-gate` is an explicit alias. The coupled
experiment runs through `make qemu-system-linux-full-differential-gate`; it
rebuilds the custom QEMU model inside a memory-capped run scope before starting
the two producers.

## 2. Acceptance contract

The gate passes only when all of the following hold:

1. `validate_linux_image_identity.py` accepts the supplied image manifest.
2. QEMU runs with the native Linux compatibility property `linux-guest=on`
   and the deterministic `linux-rng-seed` property. The DTB supplies the
   command line by default; `rtl-cp0-identity=on` is reserved for the deferred
   RTL differential phase.
3. QEMU stops because the terminal marker is observed, not because of a
   watchdog, capture limit, or host kill. Plugin status must contain
   `terminal_marker=flushed` and the terminal retire count.
4. Stdout and modeled UART bytes both contain the required marker sequence in
   workload order. The current image order is BOOT, GPIO, protection-fault,
   protection, brk, sleep, mmap, yield, exec, wait-status, fork/wait, then
   TERMINAL. Repeated BOOT/EXEC output is permitted where produced by the
   declared fork/exec workload; the terminal marker must occur exactly once.
5. The structured UART stream is valid JSONL, CRLF transport framing is
   normalized, and no panic/Oops/BUG/failure marker is present.
6. A compact manifest records hashes for the kernel, DTB, image artifacts,
   QEMU, plugin, marker evidence, command line, machine properties, entropy,
   commit, and terminal retire count.

## 3. Evidence and lifecycle

Each run is rooted under `/data/disk/tmp/mips32-soc` and retains:

- `completion_report.md`;
- `qemu_terminal_manifest.json`;
- `marker_evidence.json` and `marker_validation.log`;
- `qemu/qemu_stdout.log`, `qemu/qemu_capture_status.txt`, and
  `qemu/peripheral.jsonl`.

The QEMU capture lifecycle still has a large marker watchdog for deadlock
protection. Watchdog expiry, malformed peripheral records, missing or
duplicated terminal markers, and any capture-limit status fail closed.

## 4. RTL/differential closure

The standalone RTL and QEMU gates do not by themselves prove an architectural
differential. The coupled outside-sandbox run recorded below closes the
declared Linux workload from the shared kernel entry through the terminal
marker for the default blocking RTL configuration. Its producer record counts
differ because RTL includes a boot-ROM prefix and has explicit synchronous
exception redirect records; those records are separately accounted for and
validated. The remaining related scope is:

- a full Linux differential using the nonblocking RTL configuration, if that
  configuration is part of the claimed closure;
- unrestricted Linux and broader ISA, privileged, MMU, FPU, and OS compliance,
  which remain outside this declared workload.

The coupled gate now feeds both producers through live FIFOs to a bounded-
memory strict comparator. The first recorded architectural mismatch is owned
by the UART LSR read in the early serial-console path: in
`/data/disk/tmp/mips32-soc/full-qemu-strict-replay-uartdiag-20261002-0800/trace_compare.log`,
at PC `0x8858e27c` (`lw` from UART LSR address `0xa4000014`), RTL returned
`0x60` while QEMU returned `0x20`. In the archived QEMU peripheral stream, the
`'['` transmit was followed by LSR polls 20, 45, and 70 retirements later; the
mismatch is the second poll, 45 retirements after the write. No additional TX
write appears between that byte and the mismatching poll, so FIFO queueing does
not explain this first divergence. A review found
that the first Count-timed UART attempt was not a valid fix: it assumed a fixed
160-cycle 8N1 frame and converted that to 80 synthetic Count ticks, even
though QEMU's retire-clock advances once per retired instruction while RTL
Count advances once per two SoC clocks. The RTL UART resets to 8N1 with divisor
1, and the guest can change LCR/divisor, so frame length must come from the
register state.

The current implementation captures a sparse RTL cycle-versus-retirement
schedule during the existing full-workload preflight, interpolates that clock
in QEMU for peripheral timing, and derives each UART frame from LCR/divisor.
QEMU now initializes LCR to the RTL reset value (`0x03`, 8N1) and models the
transmit holding/FIFO queue separately from the active shifter, so LSR THRE
tracks FIFO availability while TEMT also waits for the active frame to drain.
The UART IIR and VIC TX interrupt source use the same FIFO-empty condition.
Its schedule index is the architectural instruction sequence, kept separate
from QEMU's synthetic Count timeline that advances across WAIT intervals.
The schedule declares its ELF start PC and sampling interval (8 retirements by
default), and the gate verifies both before reuse.
Focused interpolation/frame/FIFO tests and QEMU-model syntax compilation pass.
The first 2026-10-25 replay below exercised the new schedule/model but still
failed the terminal boundary; the post-marker-fixed retry is recorded as a
separate passing run below.

The same archived run later stopped CP0 Count schedule consumption at entry
6795 of 9873 (`RTL pc=0x88010330`, `QEMU pc=0x8801033c`). Because this occurs
after the UART value divergence, it is not evidence of an independent first
Count mismatch. The 2026-10-25 full replay removed that early UART LSR value
divergence and consumed the complete CP0 Count and declared UART APB schedules.
Its retry also closed the terminal boundary and validated the synchronous
exception state, as recorded below.

The coupled closure acceptance contract requires one run to prove all of the
following, not just terminal markers or a bounded prefix:

- both RTL and QEMU emit the unique terminal marker;
- strict architectural records match from the shared ELF entry through the
  terminal retire, with exact producer and compared-record counts; any
  producer-specific prefix or exception redirect records are accounted for
  and separately checked;
- the entire captured CP0 Count schedule is consumed, the RTL cycle schedule is
  used through the terminal retire, and all IRQ replay entries are released at
  their scheduled boundaries; synchronous exception transitions are validated
  against QEMU Cause, EPC, and BD state;
- the differential manifest validates hashes for the exact kernel, DTB, image,
  QEMU model, plugin, comparator, RTL capture, Count/IRQ/cycle schedules, and
  worktree state;
- blocking and nonblocking RTL configurations each have their own passing
  evidence if both are part of the claimed closure.

An earlier attempt used a list-based comparison path and reached about 3 GB
RSS from roughly 800 MB of trace files. The FIFO/streaming path passed its
focused regression and previously measured about 10 MB RSS on a bounded
2-million-cycle comparison. The full gate now defaults to a 2 GiB RAM and
512 MiB swap cgroup and refuses to run without the user systemd cgroup manager.
The gate also requires 2 GiB free on its run and TMPDIR filesystems, with the
default TMPDIR under `/data/disk/tmp/mips32-soc`. On 2026-10-07 the environment
had 408 MB free on `/data/disk` and the user systemd bus was unavailable, so no
full RTL/QEMU run was started at that time.

### 2026-10-25 full-workload diagnostic replay

The host-side run at
`/tmp/mips32-soc-full-qemu-replay-outside-20261025-032813/` completed the
declared Linux workload with RTL and QEMU terminal markers. Its generated gate
report says PASS, but this is diagnostic evidence, not differential closure:

- RTL emitted 70,056,187 records; QEMU emitted 70,056,146; 70,056,146 records
  compared without a field mismatch.
- The comparator classified RTL's 41 unpaired records as 23 boot-ROM records
  before the shared kernel entry and 18 synchronous exception redirect records.
  Each exception record redirected to the QEMU handler's current PC. QEMU had
  no unpaired records. The run did not compare those 18 exception codes and
  EPC/BD values against QEMU's captured CP0 state.
- All 55,724 declared UART APB schedule entries were consumed, but QEMU then
  reported `UART APB schedule exhausted at retire=70056463 access=W04000004`.
  This is after plugin terminal capture (`record=70056146`); the sparse cycle
  schedule ended at retire 70,056,164. Setting
  `QEMU_TERMINAL_DRAIN_SECONDS=0` did not prevent the extra access.
- IRQ replay released all 1,008 entries. CP0 Count consumed all 9,875 entries,
  CP0 Random all 132 entries, and the cycle schedule was used through the
  post-marker QEMU instruction above.

The streaming comparator now reports bounded record samples and a count by
alignment reason. The full gate rejects unreviewed alignment reasons and
post-marker UART schedule exhaustion. The later retry below satisfies those
checks and records the exception-state validation.

### 2026-10-25 post-marker-fixed terminal differential PASS

The outside-sandbox run at
`/data/disk/tmp/mips32-soc/full-qemu-schema-v2-index-taint-postmarker-fixed-20261025/`
completed the declared Linux workload through `MIPS32_SOC_LINUX_TERMINAL` and
passed the full shared-entry streaming comparison for the default blocking RTL
configuration:

- RTL emitted 70,056,187 records and QEMU emitted 70,056,146. All 70,056,146
  shared records matched. The 41 RTL-only records are accounted for as 23
  boot-ROM prefix records and 18 synchronous exception redirects; QEMU had no
  unpaired records.
- All 18 synchronous redirects passed Cause/EPC/BD validation against QEMU
  state. The RTL terminal marker occurred once; QEMU flushed the terminal
  marker at record 70,056,145 and exited cleanly with status 0.
- QEMU consumed all 55,724 UART APB schedule entries and released all 1,008
  IRQ replay entries. CP0 Count consumed 9,875 entries, CP0 Random consumed
  132 entries, and the cycle schedule was used through retire 70,056,164.
- The differential manifest validator passed with SHA-256
  `05cfdc24340543ff73ba916ad52f8621593d9e4fc3832d93fc84b4eab5642a25`.

This closes the declared image's blocking RTL/QEMU differential through its
terminal userspace marker. It does not prove nonblocking RTL Linux, arbitrary
Linux, full MIPS32/privileged/FPU compliance, or product signoff.

## 5. Explicit non-claims

This plan does not close unrestricted RTL Linux, unrestricted Linux, complete MIPS32/
privileged/FPU compliance, SMP shootdown, physical DDR/QSPI/PHY behavior,
U-Boot board support, CDC/RDC/lint/formal signoff, synthesis timing, or ASIC
release readiness.

## 6. Reusable closure lessons

The blocking Linux closure required more than a trace comparator. The following
lessons are part of the execution contract for future differential work,
especially the opt-in nonblocking-L1 path.

### 6.1 Classify the first divergence before changing RTL

Linux failures often appear many millions of cycles after the responsible
event. A WAIT loop, timer interrupt, scheduler handoff, bad virtual address, or
userspace panic is a symptom until the first architectural divergence is
identified. Every investigation should preserve the exact image and capture
enough state at the first mismatch to classify its owner as one of:

- RTL architectural state or pipeline ownership;
- QEMU instruction or peripheral model;
- input/image/configuration identity;
- trace capture, alignment, or conversion infrastructure; or
- resource/termination behavior.

Do not change CPU, CP0, or cache behavior based only on a late PC, a guessed
register producer, or a bounded progress timeout. A focused QEMU GPR capture,
matching RTL retire record, and precise fault-address token are required when
the existing trace cannot establish ownership.

### 6.2 Separate architectural state from microarchitectural timing

Blocking and nonblocking implementations may issue AXI requests, refill lines,
return responses, and drain writebacks at different times. The authoritative
comparison is the architectural retirement contract: PC, instruction effect,
GPR, HI/LO, CP0, memory effect, exception, interrupt, BD/EPC, and ERET state.
AXI order and cache timing are compared only where they are externally
observable or needed to explain an architectural event.

The nonblocking path additionally requires explicit transaction ownership in
the trace: request/response ID, MSHR, cache line, ROB allocation and head,
completion, flush, replay, and response-error state. A matching retire stream
without these fields is insufficient to debug a late response or a precise
flush failure.

### 6.3 Close in progressively larger scopes

Use the following progression and retain a report for every boundary:

1. QEMU machine and RTL frontend/elaboration smoke.
2. Small bare-metal mailbox and peripheral differentials.
3. Exception, delay-slot, CP0, interrupt, and memory-ordering corpus.
4. Same-image Linux prefix with a bounded streaming comparison.
5. Linux userspace marker workload.
6. Full terminal-marker workload with clean producer shutdown.

For nonblocking Linux, run the blocking and nonblocking configurations from
the same immutable image manifest before comparing their results. Blocking PASS
is a reference baseline, not evidence that the nonblocking cache/ROB path is
closed.

### 6.4 Treat external timing models as first-class contracts

The UART LSR mismatch showed that fixed timing guesses are unsafe. UART frame
length must follow LCR and divisor state; FIFO availability, THRE, TEMT, IIR,
and TX IRQ must share one model. CP0 Count, CP0 Random, IRQ release, and
cycle-to-retire schedules must likewise be explicit, versioned, consumed, and
validated through the terminal boundary.

Schedule replay must not be used to hide an unclassified mismatch. It is valid
only when its source image, start PC, sampling interval, hash, and consumption
count are recorded in the differential manifest.

### 6.5 Make evidence and termination fail closed

The terminal marker alone is not a differential PASS. A valid full run must
also prove that both producers stopped for the marker, all declared schedules
were consumed, all producer-specific records have an approved reason, all
synchronous exception transitions were checked, and QEMU exited cleanly.
Post-marker UART accesses, unreviewed alignment reasons, stale reports, and
reused artifacts must fail the gate.

Every result should bind the exact kernel, DTB, Boot ROM, DDR image, QEMU,
plugin, converter, comparator, RTL capture, source commit, dirty status, and
worktree content. A report that cannot reproduce this identity is diagnostic
evidence only.

### 6.6 Budget resources before running long traces

Long Linux traces must use streaming FIFOs or bounded readers; list-based
materialization is not an acceptable default. Run directories, temporary
files, QEMU builds, VCS databases, and coverage outputs must be isolated under
an explicitly sized filesystem. Long Linux differential runs should disable
coverage and use the documented EDA resource limits. Coverage closure is a
separate gate and must not be mixed into a multi-hour architectural diagnosis.
