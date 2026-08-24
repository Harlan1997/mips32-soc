#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_cpu_two_error_reset"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_axi_error_two"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_axi_error_two" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all >"${RUN_DIR}/firmware_build.log" 2>&1
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_AXI_ERROR +define+TB_L1_AXI_ERROR_TWO +define+TB_L1_AXI_ERROR_TWO_RESET_STRESS +define+SOC_AXI_RESP_ERROR_INJECT_ENABLE=1 +define+SOC_AXI_RESP_ERROR_INJECT_TWO_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
    "${SCRIPT_DIR}/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1

grep -q 'L1_AXI_TWO_ERROR_RESET: two refills in flight' "${RUN_DIR}/sim.log"
grep -q 'L1_AXI_TWO_ERROR_RESET: reset released' "${RUN_DIR}/sim.log"
reset_release_line=$(grep -n 'L1_AXI_TWO_ERROR_RESET: reset released' "${RUN_DIR}/sim.log" | head -1 | cut -d: -f1)
test -n "${reset_release_line}"
post_reset_injections=$(awk -v start="${reset_release_line}" 'NR > start && /axi_ddr_model: injected SLVERR addr=00008000|axi_ddr_model: injected SLVERR addr=00009000/ { count++ } END { print count + 0 }' "${RUN_DIR}/sim.log")
test "${post_reset_injections}" -ge 2
test "$(grep -c 'L1ERR_EXC .*code=30' "${RUN_DIR}/sim.log")" -ge 1
grep -q 'L1_AXI_TWO_PRECISE_REPLAY_PASS' "${RUN_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"

cat >"${RUN_DIR}/l1_nonblocking_cpu_two_error_reset_report.md" <<'EOF'
# L1 Nonblocking CPU Two-Response Error + Reset-In-Flight Gate

- Result: PASS
- Reset is asserted only after both independent L1 MSHRs are observed active.
- Both injected addresses are observed again after reset release, proving the
  restarted firmware exercised fresh requests rather than accepting stale
  pre-reset responses.
- At least one precise CacheErr is retired and the firmware success mailbox is
  reached after recovery.

This is a bounded simulation contract. Arbitrary reset/error timing, three or
more simultaneous errors, physical DDR behavior, maintenance/coherence, and
default-path switching remain separate residuals.
EOF
echo 'L1 nonblocking CPU two-response error + reset-in-flight: PASS'
