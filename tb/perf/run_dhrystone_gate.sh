#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/perf/dhrystone_gate"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
SIM_DIR=${SIM_DIR:-"${RUN_DIR}/sim"}
mkdir -p "${FW_DIR}" "${SIM_DIR}"

make -C "${ROOT_DIR}/tb/perf/dhrystone" OUT_DIR="${FW_DIR}" all
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${SIM_DIR}" \
  FW_DIR="${FW_DIR}" \
  SIM_EXTRA_ARGS="+SOC_TIMEOUT_NS=${SOC_TIMEOUT_NS:-100000000}" \
  VCS_EXTRA_ARGS='+define+SOC_PERF_COUNTERS=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
  "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/sim.log" 2>&1

grep -q 'Dhrystone Benchmark, Version 2.1' "${SIM_DIR}/sim.log"
grep -q 'Dhrystone validation: PASS' "${SIM_DIR}/sim.log"
grep -q 'Dhrystone cycles:' "${SIM_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${SIM_DIR}/sim.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# Dhrystone 2.1 Bare-Metal Baseline

- Result: PASS
- Source: Dhrystone C version 2.1 by Reinhold P. Weicker, distributed by
  Netlib; original source and README are retained in this directory.
- Configuration: 100 runs, one context, static 512-byte allocator, \`-O2\`
- Timer: SoC APB cycle counter (\`PERF_CYCLE_COUNT\`)
- UART: SoC UART TX register
- RTL log: ${SIM_DIR}/sim.log
- Boundary: this is a real RTL execution and validation baseline. It is not
  a standard DMIPS/MHz result because the freestanding port does not implement
  the Unix timing protocol or a calibrated reference machine.
EOF
echo "Dhrystone bare-metal RTL gate: PASS"
