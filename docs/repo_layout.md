# Repository Layout

The repository separates design sources from process artifacts. Source
directories are the reviewable source of truth. Build and run directories are
disposable and must be reproducible from source plus tool versions.

## Source Directories

- `rtl/`: synthesizable RTL and shared RTL include files.
- `tb/`: verification source, including UVM agents, sequences, scoreboards,
  directed testlists, legacy SoC tests, and firmware source.
- `sim/`: block/stage simulation Makefile and helper entry point only. Simulator
  output from this flow goes under `build/stage/<stage>/`.
- `docs/`: architecture, migration, coverage, signoff, and repository process
  documents.
- `.agents/` and `AGENTS.md`: local agent/tooling instructions.

These directories should not receive simulator databases, generated firmware
images, logs, coverage reports, or waveform dumps during normal runs.

## Generated Directories

- `build/firmware/<name>/`: firmware ELF/bin/hex/map/objdump/manifest artifacts.
- `build/uvm/single/`: single UVM test compile and simulation output.
- `build/uvm/regression/`: seeded UVM regression output.
- `build/uvm/directed/`: deterministic Phase 2 directed gate output.
- `build/uvm/phase2_complete/`: Phase 2 closure output, including
  non-coverage run, coverage run, error scan, and completion report.
- `build/uvm/phase3_directed/`: deterministic Phase 3A directed gate output.
- `build/uvm/phase3_complete/`: Phase 3A closure output, including
  non-coverage run, coverage run, error scan, and completion report.
- `build/uvm/phase3b_directed/`: deterministic Phase 3B CPU/CP0 UVM coverage
  gate output.
- `build/uvm/phase3b_complete/`: Phase 3B CPU/CP0 UVM closure output,
  including non-coverage run, coverage run, error scan, and completion report.
- `build/uvm/phase3c_directed/`: deterministic Phase 3C PIC mask arbitration
  gate output.
- `build/uvm/phase3c_complete/`: Phase 3C PIC mask arbitration closure output,
  including non-coverage run, coverage run, error scan, and completion report.
- `build/signoff/current_contract/`: current RTL contract full-chip sign-off output,
  including all Phase 2/3A/3B/3C gates, multi-seed stress regression, merged VDB,
  and sign-off report.
- `build/uvm/<custom>/`: caller-selected UVM run directories through
  `UVM_RUN_DIR`, `UVM_REG_DIR`, or `UVM_DIRECTED_DIR`.
- `build/soc_test/smoke/`: legacy SoC smoke compile, simulation, and coverage
  output.
- `build/soc_test/cpu_cp0_gate/`: CPU/CP0 firmware gate output and
  machine-readable event summary.
- `build/soc_test/random_regression/`: random MIPS firmware regression output,
  including per-test generated assembly/firmware and logs.
- `build/stage/<stage>/`: block/stage VCS output from `sim/Makefile`.

Everything under `build/` is disposable and ignored by git.

Current Phase 2 baselines are kept as named disposable run directories:
- `build/uvm/directed_apb_burst_stress_closed/`: latest non-coverage directed
  baseline with internal fabric protocol checker binds, directed APB read-burst
  checking, directed timer/PIC interrupt checking, and directed timer+DMA
  combined PIC interrupt checking, and multi-peripheral APB burst stress.
- `build/uvm/directed_cov_apb_burst_stress_closed/`: latest coverage directed
  baseline with internal fabric protocol checker binds, directed APB read-burst
  checking, directed timer/PIC interrupt checking, directed timer+DMA combined
  PIC interrupt checking, multi-peripheral APB burst stress, and URG report
  output.

## Entry Points

- `make firmware`: builds firmware into `build/firmware/<FW_NAME>/`.
- `make uvm`: runs one UVM test in `build/uvm/single/`.
- `make phase2-regression`: runs the deterministic Phase 2 directed gate in
  `build/uvm/directed/`.
- `make phase2-regression UVM_ENABLE_COV=1`: runs the same directed gate with
  VCS/URG coverage enabled and writes `urgReport` under the selected run
  directory.
- `make phase2-complete`: runs the full Phase 2 closure gate in
  `build/uvm/phase2_complete/`, including non-coverage regression, coverage
  regression, error scan, required group checks, and a completion report.
- `make phase3-regression`: runs the deterministic Phase 3A directed gate in
  `build/uvm/phase3_directed/`.
- `make phase3-complete`: runs the full Phase 3A closure gate in
  `build/uvm/phase3_complete/`, including non-coverage regression, coverage
  regression, CPU/CP0 firmware gate, error scan, required group checks, and a
  completion report.
- `make phase3b-regression`: runs the deterministic Phase 3B CPU/CP0 UVM
  coverage gate in `build/uvm/phase3b_directed/`.
- `make phase3b-complete`: runs the full Phase 3B CPU/CP0 UVM closure gate in
  `build/uvm/phase3b_complete/`, including non-coverage regression, coverage
  regression, error scan, required group checks, and a completion report.
- `make phase3c-regression`: runs the deterministic Phase 3C PIC mask
  arbitration gate in `build/uvm/phase3c_directed/`.
- `make phase3c-complete`: runs the full Phase 3C PIC mask arbitration closure
  gate in `build/uvm/phase3c_complete/`, including non-coverage regression,
  coverage regression, error scan, required group checks, and a completion
  report.
- `make current-contract-signoff`: runs the full current RTL contract full-chip
  sign-off flow in `build/signoff/current_contract/`, including Phase 2, Phase 3A,
  Phase 3B, Phase 3C, multi-seed stress regression, merged coverage check, and
  sign-off report generation.
- `make soc-smoke`: runs the legacy SoC smoke test in `build/soc_test/smoke/`.
- `make cpu-cp0-gate`: runs the CPU/CP0 firmware smoke gate in
  `build/soc_test/cpu_cp0_gate/`.
- `make soc-random-regression NUM_TESTS=<n>`: runs random MIPS firmware tests in
  `build/soc_test/random_regression/`.
- `make stage-sim STAGE=<ex|id|if|mem>`: runs a block/stage simulation in
  `build/stage/<stage>/`.
- `make project-tree`: prints the source directory tree and current generated
  build tree.

## Cleanup

- `make clean-build`: removes `build/` only.
- `make clean`: aliases `clean-build`.
- `make clean-legacy-artifacts`: removes known simulator, coverage, firmware,
  and log artifacts that older flows may have emitted into `sim/`,
  `tb/soc_test/`, or `tb/soc_test/fw/`.

Do not manually remove source directories as a cleanup shortcut. If a generated
file appears outside `build/`, update the responsible script or Makefile so the
artifact is produced under a run directory, then add the legacy pattern to
`.gitignore` and `clean-legacy-artifacts` if needed.
