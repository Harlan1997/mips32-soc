#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_cpu_error_reset"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_axi_error"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_axi_error" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all >"${RUN_DIR}/firmware_build.log" 2>&1
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_AXI_ERROR +define+TB_L1_AXI_ERROR_RESET_STRESS +define+SOC_AXI_RESP_ERROR_INJECT_ENABLE=1' \
    "${SCRIPT_DIR}/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1

grep -q 'L1_AXI_ERROR_RESET: refill in flight' "${RUN_DIR}/sim.log"
grep -q 'L1_AXI_ERROR_RESET: reset released' "${RUN_DIR}/sim.log"
reset_release_line=$(grep -n 'L1_AXI_ERROR_RESET: reset released' "${RUN_DIR}/sim.log" | head -1 | cut -d: -f1)
inject_line=$(grep -n 'axi_ddr_model: injected SLVERR addr=00008000' "${RUN_DIR}/sim.log" | head -1 | cut -d: -f1)
test -n "${reset_release_line}"
test -n "${inject_line}"
test "${inject_line}" -gt "${reset_release_line}"
test "$(grep -c 'L1ERR_EXC .*code=30' "${RUN_DIR}/sim.log")" -ge 1
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"

cat >"${RUN_DIR}/l1_nonblocking_cpu_error_reset_report.md" <<'EOF'
# L1 Nonblocking CPU AXI Error + Reset-In-Flight Gate

Result: PASS

- The testbench waits for a real L1 MSHR before asserting SoC reset.
- The behavioral DDR model injects the same refill SLVERR again after reset,
  proving that the post-reset path is exercised rather than relying on a
  pre-reset completion.
- The restarted CPU reaches precise CacheErr/ErrorEPC recovery and the
  success mailbox.

This is a bounded simulation contract. Arbitrary reset/error timing,
simultaneous independent faults, physical DDR behavior, and coherency remain
separate residuals.
EOF
echo "L1 nonblocking CPU AXI error + reset-in-flight: PASS"
