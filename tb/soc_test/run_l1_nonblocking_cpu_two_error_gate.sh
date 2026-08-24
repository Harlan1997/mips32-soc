#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_cpu_two_error"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_axi_error_two"}
FW_HEX=${FW_DIR}/firmware.hex
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_axi_error_two" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_AXI_ERROR +define+TB_L1_AXI_ERROR_TWO +define+SOC_AXI_RESP_ERROR_INJECT_ENABLE=1 +define+SOC_AXI_RESP_ERROR_INJECT_TWO_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
    "${SCRIPT_DIR}/run.sh"

grep -q 'axi_ddr_model: injected SLVERR addr=00008000' "${RUN_DIR}/sim.log"
grep -q 'axi_ddr_model: injected SLVERR addr=00009000' "${RUN_DIR}/sim.log"
test "$(grep -c 'L1ERR_EXC .*code=30' "${RUN_DIR}/sim.log")" -ge 1
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
cat >"${RUN_DIR}/l1_nonblocking_cpu_two_error_report.md" <<'EOF'
# L1 Nonblocking CPU Two-Response Error Gate

- Result: PASS
- Two distinct cache-line DDR model reads (`0x00008000`, `0x00009000`) are
  issued back-to-back and both injected responses are observed. The first
  error retires as a precise CacheErr; the younger request is flushed and is
  required to replay after ERET rather than being retired from a stale
  response. This is the precise-exception contract for simultaneous in-flight
  faults.
- This remains behavioral simulation fault injection. Physical DDR failures,
  arbitrary reset/error interleaving, maintenance/coherence, and default-path
  switching remain open.
EOF
echo 'L1 nonblocking CPU two-response error: PASS'
