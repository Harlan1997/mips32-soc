# Current RTL Contract 99% Coverage Closure Spec

> Lead agent: Codex
> Worker agent: AGY
> Status: APPROVED - user confirmed 2026-07-26
> Scope: current documented RTL contract only; not tapeout sign-off

## 1. Objective

Raise the auditable full-chip coverage gate to at least 99.00% for every
reported code-coverage metric while preserving all functional and regression
gates from the existing current-contract sign-off flow.

The 99% target applies independently to both:

1. The merged UVM module-definition report.
2. The product-top CPU/CP0 module-definition report.

For each report, `SCORE`, `LINE`, `COND`, `TOGGLE`, `FSM`, and `BRANCH` must
each be at least 99.00% after reviewed exclusions. Functional coverage remains
15/15 required groups at exactly 100.00%.

## 2. Coverage Closure Policy

### 2.1 Test before exclude

- First cover every legally reachable current-contract behavior with directed
  or constrained-random stimulus.
- Add focused tests/sequences/firmware for reachable holes and keep them in the
  normal sign-off regression.
- Do not exclude an object merely because it is difficult, slow, or currently
  uncovered.
- Do not modify RTL behavior to manufacture coverage. If a reachable hole
  cannot be covered without an RTL or architecture change, report `FAILED`
  with evidence for Codex review.

### 2.2 Permitted exclusion categories

An `.el` rule is permitted only when the exact coverage object is proven to be:

- `UNREACHABLE_CURRENT_CONTRACT`: impossible under the documented
  single-outstanding/current-feature contract.
- `STATIC_TIEOFF_RESERVED`: a constant/tied-off or reserved field with no
  legal transition in the selected configuration.
- `UNINSTANTIATED_CONFIGURATION`: an alternate parameterization/top/module not
  instantiated in either signed-off product configuration.
- `DEFENSIVE_ILLEGAL_STATE`: recovery/default behavior reachable only through
  an illegal/X-corrupted state outside the verification contract.
- `NON_PRODUCT_VERIFICATION`: verification-only instrumentation, bind wrappers,
  or tool-generated recording logic that is not product RTL.
- `OUT_OF_SCOPE_FEATURE`: logic solely for a feature explicitly outside the
  current RTL contract, such as UART RX or real SPI-serial flash behavior.

No other category is accepted without a new human-approved Spec.

### 2.3 Exclusion provenance and enforcement

- Generate exclusion candidates from fresh `urg -dump full_exclusions` output
  produced from the exact VDBs used by this sign-off run. Never reuse stale
  checksums or hierarchy paths.
- Store source-controlled UVM and product exclusion files under
  `tb/coverage/` and keep them separate when their hierarchy/checksums differ.
- Every active excluded object or explicitly documented group of equivalent
  objects must have a stable unique ID, category, source/module/object,
  rationale, and concrete reachability evidence in a machine-readable manifest.
- Add an automated audit that fails for an active `.el` record without a valid
  manifest entry, duplicate IDs, unknown categories, missing evidence, stale or
  unmatched rules, malformed files, or manifest entries with no active rule.
- Apply exclusions with `-excl_strict`. `-excl_bypass_checks` is forbidden.
- Treat exclusion-related URG warnings/errors, checksum mismatches, covered
  object exclusion attempts, and zero-match exclusion rules as sign-off
  failures.
- Do not add new hidden object-level coverage omissions in `cov.cfg`. Migrate
  existing object-level `-node` toggle omissions to reviewed `.el` rules when
  still justified. `cov.cfg` may retain module-level removal of non-product
  testbench/tool instrumentation only when that scope is explicit in the final
  report.
- Blanket exclusion of instantiated product modules is forbidden.

## 3. Raw and Adjusted Reporting

The flow must generate both raw and exclusion-adjusted reports from the same
fresh coverage databases:

- Merged UVM raw report: `coverage/raw_urgReport/`.
- Merged UVM adjusted report: `coverage/urgReport/`.
- Product CPU/CP0 raw report: `phase3_complete/cpu_cp0_gate/textReportRaw/`.
- Product CPU/CP0 adjusted report:
  `phase3_complete/cpu_cp0_gate/textReportFinal/`.

Raw reports must not load any `.el` file. Adjusted reports must use only the
reviewed source-controlled `.el` files and strict exclusion validation.

The final Markdown report and a machine-readable JSON summary must include:

- Raw and adjusted values for all six metrics for both report domains.
- Required threshold and PASS/FAIL for each adjusted metric.
- Active exclusion counts by domain, metric, category, and manifest ID.
- Paths and SHA256 hashes for each `.el` file and its manifest.
- URG commands/options and proof that strict exclusion checking was enabled.
- Counts of tests and functional groups, all subordinate gate results, seeds,
  tool versions, Git provenance, and clean error scan.
- A prominent statement that adjusted coverage includes justified exclusions
  and is not the same as raw stimulus coverage.
- The unchanged current-contract/tapeout scope limitations.

Stale raw, adjusted, full-exclusion dump, and audit artifacts must be removed
before each run. Missing or empty text/HTML/JSON artifacts fail closed.

## 4. Mandatory 99% Gates

Default adjusted thresholds for both merged UVM and product CPU/CP0 reports:

| Metric | Minimum |
| --- | ---: |
| Score | 99.00% |
| Line | 99.00% |
| Condition | 99.00% |
| Toggle | 99.00% |
| FSM | 99.00% |
| Branch | 99.00% |

Threshold overrides may only make a run stricter. The sign-off script must
reject environment or Make overrides below 99.00%, nonnumeric values, NaN,
infinity, duplicates, missing fields, and values above 100.00%.

The following existing gates remain mandatory and must not be weakened:

- Phase 2 directed and coverage: 16/16 each.
- Phase 3A directed and coverage: 3/3 each.
- Product CPU/CP0 firmware gate: 1/1.
- Phase 3B directed and coverage: 1/1 each.
- Phase 3C directed and coverage: 1/1 each.
- Deterministic stress regression: at least 10/10.
- Merged UVM test count: expected coverage-run cardinality, currently 31 with
  default tests/seeds; update the exact expected count if new retained coverage
  tests are added.
- Required functional groups: 15/15 at 100.00%.
- Project error/fatal/license/exclusion-warning scan: clean.

Any new test must check its intended behavior, return nonzero on failure, and
be included in both the applicable directed and coverage regression paths.

## 5. Baseline and Scope Integrity

The prior adjusted baseline was:

| Domain | Score | Line | Cond | Toggle | FSM | Branch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Merged UVM | 77.78 | 73.26 | 83.51 | 67.39 | 88.89 | 75.85 |
| Product CPU/CP0 | 81.40 | 74.20 | 90.31 | 59.27 | 91.67 | 91.54 |

These values used historical coverage scoping and are recorded only as
provenance. After migrating hidden object omissions, the new raw denominator
may increase and the raw percentage may decrease. That is acceptable only when
the final report explains the scope change and the adjusted result is backed by
the audited manifest.

The signed-off contract remains:

- Single-outstanding AXI; no multi-outstanding/reordering claim.
- UART TX only; UART RX remains open.
- AXI flash-image/XIP verification model; no SPI timing or real flash boot.
- PIC mask arbitration without priority encoding.
- No synthesis, STA, DFT, formal, lint, CDC, RDC, physical-design, foundry, or
  tapeout sign-off claim.

## 6. Allowed Paths and Single-Writer Rules

AGY may modify only:

- `Makefile`
- `.gitignore`
- `README.md`
- `docs/coverage_plan.md`
- `docs/signoff_criteria.md`
- `docs/repo_layout.md`
- `tb/coverage/**`
- `tb/uvm_tb/cov.cfg`
- `tb/uvm_tb/data/**`
- `tb/uvm_tb/agents/**`
- `tb/uvm_tb/checkers/**`
- `tb/uvm_tb/env/**`
- `tb/uvm_tb/seqs/**`
- `tb/uvm_tb/tests/**`
- `tb/uvm_tb/tb_top/**`
- `tb/uvm_tb/*_directed_tests.txt`
- `tb/uvm_tb/run_current_contract_signoff.sh`
- `tb/uvm_tb/run_phase2_complete.sh`
- `tb/uvm_tb/run_phase3_complete.sh`
- `tb/uvm_tb/run_phase3b_complete.sh`
- `tb/uvm_tb/run_phase3c_complete.sh`
- `tb/uvm_tb/run_regression.sh`
- `tb/uvm_tb/run_testlist.sh`
- `tb/uvm_tb/run_uvm.sh`
- `tb/soc_test/cov.cfg`
- `tb/soc_test/run.sh`
- `tb/soc_test/run_cpu_cp0_gate.sh`
- `tb/soc_test/tb_mips_soc.v`
- `tb/soc_test/axi_monitor.v`
- `tb/soc_test/soc_legacy_observation_bind.sv`
- `tb/soc_test/soc_legacy_observation_if.sv`
- `tb/soc_test/fw/**`
- `.agent/test_report.md`
- `.agent/result.json`

AGY must not modify RTL, architecture/source specifications, existing legacy
`.el`/`fullexclude.*` artifacts under `tb/soc_test/`, `.agent/tasks.json`,
`.agent/spec.md`, `.agent/review.md`, or `.agent/run_agent_flow.sh`.

## 7. Acceptance Tests

AGY must run and record at least:

```bash
bash -n tb/uvm_tb/run_current_contract_signoff.sh
bash -n tb/uvm_tb/run_regression.sh
bash -n tb/uvm_tb/run_testlist.sh
bash -n tb/soc_test/run.sh
bash -n tb/soc_test/run_cpu_cp0_gate.sh
make -n current-contract-signoff
make firmware
make current-contract-signoff
git diff --check
```

Also run the exclusion-audit tool directly against positive and deliberately
malformed fixtures. The negative cases must fail for missing evidence, stale or
unmatched rules, forbidden category, duplicate ID, and attempts to lower any
threshold below 99.00%.

Codex will independently review every diff, verify allowed-path compliance,
inspect every active exclusion and its evidence, rerun lightweight checks, and
run the full `make current-contract-signoff` flow with VCS/URG loaded through
environment modules.

## 8. Completion Criteria

The task is complete only when:

- All mandatory regression/functional gates pass.
- All six adjusted metrics are at least 99.00% in both coverage domains.
- Raw and adjusted reports are present and consistent.
- Every exclusion passes the manifest audit and strict URG application.
- The error scan is clean and the final report makes no scope overclaim.
- Codex independently approves the implementation.
- `.agent/tasks.json` is `CLOSED` with TASK-002 `completed` before Git commit.
