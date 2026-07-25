# Project Rules

## EDA Environment

- Before running EDA tools such as VCS, Verdi, or Virtuoso, initialize modules:
  `source /etc/profile.d/modules.sh`
- Load the needed tools explicitly, for example:
  `module load vcs`

## Sandbox And License Limits

- VCS uses `SNPSLMD_LICENSE_FILE=2700@localhost` in this environment.
- Codex sandbox runs may use an isolated network namespace. In that mode,
  `localhost` refers to the sandbox, not the host, so VCS can fail with:
  `Cannot connect to the license server`.
- If a VCS/Verdi command fails only with a license connection error inside the
  sandbox, rerun the same command outside the sandbox before debugging RTL or
  scripts.
- Commands that should be run outside the sandbox include:
  `make uvm`, `make uvm-regression`, `make regression`, and direct `vcs` or
  `verdi` invocations.
- Firmware-only commands such as `make firmware` do not require VCS licensing
  and can run normally as long as the MIPS cross toolchain is installed.

## Recommended Regression Entry Points

- Build firmware artifacts:
  `make firmware`
- Run a single UVM smoke test outside the sandbox:
  `make uvm`
- Run the UVM regression outside the sandbox:
  `make uvm-regression`
- Build firmware and then run UVM regression outside the sandbox:
  `make regression`
- Run the full Phase 2 closure gate outside the sandbox:
  `make phase2-complete`
- Run the Phase 3A directed gate outside the sandbox:
  `make phase3-regression`
- Run the full Phase 3A closure gate outside the sandbox:
  `make phase3-complete`
- Run the Phase 3B CPU/CP0 UVM coverage gate outside the sandbox:
  `make phase3b-complete`
- Run the Phase 3C PIC mask arbitration gate outside the sandbox:
  `make phase3c-complete`
- Run the CPU/CP0 firmware gate outside the sandbox:
  `make cpu-cp0-gate`

UVM runs consume an explicit firmware artifact through `FW_HEX` and pass it to
simulation as `+FW_HEX=...`. Do not restore the old implicit copy of
`../soc_test/fw/firmware.hex` into the UVM run directory.

`make phase2-complete` runs both the non-coverage and coverage Phase 2 directed
gates, performs the project error scan, checks required URG functional groups,
and writes `build/uvm/phase2_complete/phase2_completion_report.md`.

`make phase3-complete` runs the Phase 3A directed and coverage gates, checks
UART TX IRQ, APB wait/PSLVERR stress, loadable flash-image reads, and the
CPU/CP0 firmware gate, then writes
`build/uvm/phase3_complete/phase3_completion_report.md`.

`make phase3b-complete` runs the UVM-visible CPU/CP0 exception-entry/return
coverage gate and writes
`build/uvm/phase3b_complete/phase3b_completion_report.md`.

`make phase3c-complete` runs the PIC multi-source mask arbitration gate and
writes `build/uvm/phase3c_complete/phase3c_completion_report.md`.
