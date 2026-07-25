# Current RTL Contract Full-Chip Sign-off Spec

> Lead agent: Codex
> Worker agent: AGY
> Status: COMPLETED - independently verified 2026-07-26
> Scope decision: current RTL contract sign-off (user selected option 1)

## 1. Objective

Create and execute one auditable full-chip verification entry point for the
repository's currently documented RTL contract. The flow must run all existing
Phase 2, Phase 3A, Phase 3B, and Phase 3C closure gates, add reproducible
multi-seed UVM stress, merge compatible UVM coverage databases, validate
coverage thresholds, and generate a single Markdown sign-off report.

The final claim is limited to the current product contract. It is not tapeout
sign-off and must not claim closure for features that the current RTL does not
implement.

## 2. Explicit Scope Boundary

In scope:

- Single-outstanding AXI fabric contract.
- Existing AXI/APB/SRAM/flash-XIP, DMA, GPIO, UART TX, timer, PIC, JTAG, CPU,
  CP0, checker, scoreboard, and documented exception/interrupt behavior.
- Loadable AXI flash-image/XIP verification model.
- Product-top firmware/CPU/CP0 smoke coverage.
- Current verification-only hook containment and current generated-artifact
  policy.

Explicitly out of scope and listed as unclosed in the final report:

- RTL multi-outstanding and response reordering.
- UART RX datapath and UART RX interrupt.
- SPI-serial protocol timing and real boot-from-flash.
- PIC priority encoding/order; current PIC only implements masked active bits
  and an OR-reduced CPU interrupt.
- New synthesis, STA, DFT, formal, lint, CDC, or RDC claims.
- Foundry/tapeout sign-off.

## 3. Required Implementation

### 3.1 Unified entry point

- Add `make current-contract-signoff`.
- Add `tb/uvm_tb/run_current_contract_signoff.sh` as the implementation entry.
- Default output root:
  `build/signoff/current_contract` (overridable through a Make variable).
- Rebuild firmware through the Make dependency and consume the explicit
  `FW_HEX` artifact. Never copy firmware implicitly into a run directory.
- Load VCS/URG through environment modules in every script that invokes them.

### 3.2 Mandatory gates

Run fresh artifacts under the unified output root:

1. Phase 2 complete: directed and coverage testlists, 16/16 each.
2. Phase 3A complete: directed and coverage testlists, 3/3 each, plus the
   product-top CPU/CP0 firmware gate.
3. Phase 3B complete: directed and coverage testlists, 1/1 each.
4. Phase 3C complete: directed and coverage testlists, 1/1 each.
5. Reproducible UVM `soc_bus_stress_test`: 10 deterministic seeds by default.

`run_phase3_complete.sh` must allow its CPU/CP0 run directory to be overridden
so all sign-off artifacts remain beneath the unified output root.

### 3.3 Stress regression hardening

Harden `tb/uvm_tb/run_regression.sh` without breaking its existing Make entry:

- Replace shell `$RANDOM` seed selection with reproducible seeds derived from
  `SEED_BASE` (default 1) and the test index.
- Remove stale simulator, log, and coverage artifacts before a run.
- Treat nonzero simulator status, SystemVerilog/VCS Error/Fatal diagnostics,
  direct UVM error/fatal records, nonzero UVM summary counts, and missing
  `REGRESSION_TEST_SUCCESS` as failures.
- Continue long enough to write a complete pass/fail table, but return nonzero
  if any test fails.
- Record every seed and log path in a machine-readable/plain-text summary.
- Generate URG text and HTML coverage reports and fail if report generation or
  required report artifacts are missing.

### 3.4 Coverage merge and gates

Merge the compatible UVM VDBs from Phase 2/3A/3B/3C coverage runs and the
multi-seed UVM stress run into:

- `build/signoff/current_contract/coverage/merged.vdb`
- `build/signoff/current_contract/coverage/urgReport/`
- `build/signoff/current_contract/coverage/urg.log`

Use strict URG failure handling. The flow must fail for corrupt/missing VDBs,
merge/report errors, or missing dashboard/groups reports.

All 15 required functional coverage groups from the existing four completion
gates must be present and exactly 100.00% in the merged report.

Minimum merged UVM module-definition coverage thresholds:

| Metric | Minimum |
| --- | ---: |
| Score | 75.00% |
| Line | 70.00% |
| Condition | 80.00% |
| Toggle | 60.00% |
| FSM | 85.00% |
| Branch | 70.00% |

The product-top CPU/CP0 smoke uses a different coverage hierarchy and must be
reported separately rather than merged with the UVM database. Minimum product
module-definition thresholds:

| Metric | Minimum |
| --- | ---: |
| Score | 80.00% |
| Line | 70.00% |
| Condition | 85.00% |
| Toggle | 55.00% |
| FSM | 90.00% |
| Branch | 90.00% |

Thresholds may be exposed as environment/Make overrides, but the defaults above
are mandatory and the effective values must appear in the report. Numeric
comparisons must be robust decimal comparisons, not lexicographic comparisons.

### 3.5 Final report and provenance

Generate
`build/signoff/current_contract/current_contract_signoff_report.md` containing:

- Overall `PASS` only when every mandatory gate and threshold passes.
- Date/time, host, VCS/URG version, Git HEAD, worktree status, firmware path and
  SHA256, flash-image path and SHA256, testlists, deterministic stress seeds,
  and output paths.
- Gate table with total/passed/failed counts and links/paths to each subordinate
  completion report and stress summary.
- Merged UVM and product-top code coverage actuals versus thresholds.
- All required functional group names and actual scores.
- Clean project error-scan result.
- Exact scope limitations listed in section 2.
- Clear wording: `PASS for the current documented RTL contract`; never
  `tapeout sign-off` or an unqualified production-final claim.

On failure, return nonzero and leave a failure report/status artifact identifying
the failed stage. Stale PASS reports must be removed or overwritten before a
new run begins.

## 4. Documentation

Update the Make target documentation and the relevant repository/coverage/
sign-off documents so users know:

- how to run `make current-contract-signoff`;
- where the report and merged coverage are written;
- which checks are hard gates;
- which product features and physical/static sign-off domains remain open.

Do not rewrite historical Phase 2/3A/3B/3C results as if the new flow has passed
until Codex independently runs it successfully.

## 5. Allowed Paths and Single-Writer Rules

AGY may modify only:

- `Makefile`
- `.gitignore` (only to ignore `.agent/run.lock`)
- `README.md`
- `docs/coverage_plan.md`
- `docs/signoff_criteria.md`
- `docs/repo_layout.md`
- `tb/uvm_tb/run_current_contract_signoff.sh`
- `tb/uvm_tb/run_regression.sh`
- `tb/uvm_tb/run_phase3_complete.sh`
- `.agent/test_report.md`
- `.agent/result.json`

AGY must not modify RTL, UVM components/sequences/tests, firmware sources,
testlists, `.agent/tasks.json`, `.agent/spec.md`, `.agent/review.md`, or
`.agent/run_agent_flow.sh`.

## 6. Acceptance Tests

AGY must run and report at least:

```bash
bash -n tb/uvm_tb/run_current_contract_signoff.sh
bash -n tb/uvm_tb/run_regression.sh
bash -n tb/uvm_tb/run_phase3_complete.sh
make -n current-contract-signoff
make firmware
```

Codex will independently:

1. Review every diff and verify allowed-path compliance.
2. Re-run syntax/dry-run/firmware checks.
3. Initialize modules with `source /etc/profile.d/modules.sh` and load VCS.
4. Run the full `make current-contract-signoff` gate outside any isolated
   network sandbox.
5. Inspect logs, subordinate reports, merged URG output, group coverage,
   numeric thresholds, provenance, and dirty-tree effects.
6. Reject the implementation if the flow can emit PASS with a missing/failed
   gate, stale artifact, malformed metric, or scope overclaim.

## 7. Completion Criteria

The task is complete only when Codex's independent full run exits zero, the
final report says PASS for the current documented RTL contract, all coverage
and functional gates meet the defaults, review is APPROVED, `.agent/tasks.json`
is set to CLOSED/completed, and the reviewed changes are committed to Git.
