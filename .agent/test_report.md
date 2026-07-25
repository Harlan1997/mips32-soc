# Verification Test Report: Current RTL Contract Full-Chip Sign-off

## 1. Overview & Work Summary

- **Task**: Implement and verify unified full-chip sign-off entry point `make current-contract-signoff`.
- **Rework Iteration**: Rework 2 addressing review findings in `.agent/review.md`.
- **Final Result**: **SUCCESS** (Exit Code: 0).
- **Report Location**: `build/signoff/current_contract/current_contract_signoff_report.md`.
- **Coverage Summary**: `build/signoff/current_contract/coverage_summary.json`.

---

## 2. Review Findings & Fixes Verification

### Finding 1: Duplicate Summary Fields Extractor Enforcements
- **Fix**: Replaced `head -n 1` in `extract_summary_counts` and `extract_stress_counts` within `tb/uvm_tb/run_current_contract_signoff.sh` with a strict `extract_single_val` helper.
- **Behavior**: Emits `MULTIPLE_MATCHES` when matching record count > 1, `MISSING_MATCH` when match count == 0, and `INVALID_FILE` if the summary file is missing. Nonnumeric values are strictly rejected by `validate_decimal_int`.
- **Unit Test Execution & Output**:
```bash
Normal summary extraction result: 16 16 0
Duplicate summary extraction result: MULTIPLE_MATCHES 16 0
CALL_FAIL_SIGNOFF: code=REGRESSION_CARDINALITY msg=Malformed summary count for p2_dir_tot: 'MULTIPLE_MATCHES' (expected non-negative integer)
Missing summary extraction result: MISSING_MATCH 16 0
CALL_FAIL_SIGNOFF: code=REGRESSION_CARDINALITY msg=Malformed summary count for p2_dir_tot: 'MISSING_MATCH' (expected non-negative integer)
Non-existent summary extraction result: INVALID_FILE INVALID_FILE INVALID_FILE
CALL_FAIL_SIGNOFF: code=REGRESSION_CARDINALITY msg=Malformed summary count for p2_dir_tot: 'INVALID_FILE' (expected non-negative integer)
```

### Finding 2: Coverage Values Alignment
- **Fix**: Authoritative coverage metrics extracted directly from `build/signoff/current_contract/coverage_summary.json`.
- **Merged UVM Coverage (Module Definition)**:
  - Score: **77.78%** (Threshold: 75.00%) -> PASS
  - Line: **73.26%** (Threshold: 70.00%) -> PASS
  - Condition: **83.51%** (Threshold: 80.00%) -> PASS
  - Toggle: **67.39%** (Threshold: 60.00%) -> PASS
  - FSM: **88.89%** (Threshold: 85.00%) -> PASS
  - Branch: **75.85%** (Threshold: 70.00%) -> PASS
- **Product-Top CPU/CP0 Coverage (Module Definition)**:
  - Score: **81.40%** (Threshold: 80.00%) -> PASS
  - Line: **74.20%** (Threshold: 70.00%) -> PASS
  - Condition: **90.31%** (Threshold: 85.00%) -> PASS
  - Toggle: **59.27%** (Threshold: 55.00%) -> PASS
  - FSM: **91.67%** (Threshold: 90.00%) -> PASS
  - Branch: **91.54%** (Threshold: 90.00%) -> PASS

### Finding 3: Negative Test Artifact Retention Wording
- **Clarification**: Controlled failure tests (such as threshold failures and duplicate field extractions) were run in controlled temporary test fixtures prior to the final sign-off run. The FAIL state outputs were observed and verified in bash, then intentionally superseded by the final full sign-off PASS run in `build/signoff/current_contract/`. No separate negative test output directory is retained in `build/signoff/`.

---

## 3. Mandatory Verification Entry Points & Syntax Checks

1. **Syntax Checks**:
   - `bash -n tb/uvm_tb/run_current_contract_signoff.sh`: Exit 0
   - `bash -n tb/uvm_tb/run_regression.sh`: Exit 0
   - `bash -n tb/uvm_tb/run_phase3_complete.sh`: Exit 0
   - `make -n current-contract-signoff`: Exit 0
   - `git diff --check`: Exit 0

2. **Firmware Build**:
   - `make firmware`: Exit 0

3. **Full Sign-off Execution (`make current-contract-signoff`)**:
   - Command: `make current-contract-signoff`
   - Exit Code: 0
   - Summary:
     - Phase 2 Directed: 16/16 Passed
     - Phase 2 Coverage: 16/16 Passed
     - Phase 3A Directed: 3/3 Passed
     - Phase 3A Coverage: 3/3 Passed
     - Phase 3A CPU/CP0 Smoke: 1/1 Passed
     - Phase 3B Directed: 1/1 Passed
     - Phase 3B Coverage: 1/1 Passed
     - Phase 3C Directed: 1/1 Passed
     - Phase 3C Coverage: 1/1 Passed
     - Multi-seed Stress Regression: 10/10 Passed (Seeds 1..10)
     - Required Functional Coverage Groups: 15/15 at 100.00%
     - Project Error Scan: CLEAN (0 errors/fatals)
     - Final Status: **PASS for the current documented RTL contract**

---

## 4. Subordinate Stack & Run Logs

Log summary from `make current-contract-signoff`:
```
SUCCESS: ALL TESTS PASSED!
======================================================================
 Merging UVM Coverage Databases
======================================================================
URG Report written to directory /home/admin/mips32-soc/build/signoff/current_contract/coverage/urgReport
======================================================================
 SUCCESS: CURRENT RTL CONTRACT FULL-CHIP SIGNOFF PASSED!
```
