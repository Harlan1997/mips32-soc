#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/perf/coremark_gate"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
SIM_DIR=${SIM_DIR:-"${RUN_DIR}/sim"}
mkdir -p "${FW_DIR}" "${SIM_DIR}"

make -C "${ROOT_DIR}/tb/perf/coremark" OUT_DIR="${FW_DIR}" all
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${SIM_DIR}" \
  FW_DIR="${FW_DIR}" \
  SIM_EXTRA_ARGS="+SOC_TIMEOUT_NS=${SOC_TIMEOUT_NS:-100000000}" \
  VCS_EXTRA_ARGS='+define+SOC_PERF_COUNTERS=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
  "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/sim.log" 2>&1

grep -q 'Correct operation validated' "${SIM_DIR}/sim.log"
grep -q 'seedcrc' "${SIM_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${SIM_DIR}/sim.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# CoreMark Bare-Metal Baseline

- Result: PASS
- Source: official EEMBC CoreMark, Apache-2.0 (tb/perf/coremark/LICENSE.md)
- Configuration: ITERATIONS=1, PERFORMANCE_RUN=1, one context, static 2 KB data
- Timer: SoC APB cycle counter (PERF_CYCLE_COUNT)
- UART: SoC UART TX register
- RTL log: ${SIM_DIR}/sim.log
- Boundary: this is a real RTL execution and validation-CRC baseline. It is
  not a normalized CoreMark/MHz score because the freestanding run does not
  provide the required 10-second benchmark timing protocol.
EOF
echo "CoreMark bare-metal RTL gate: PASS"
