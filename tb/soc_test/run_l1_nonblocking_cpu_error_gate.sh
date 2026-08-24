#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_cpu_error"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/l1_axi_error"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/l1_axi_error" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_AXI_ERROR +define+SOC_AXI_RESP_ERROR_INJECT_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
    "${SCRIPT_DIR}/run.sh"

grep -q "axi_ddr_model: injected SLVERR addr=00008000" "${RUN_DIR}/sim.log"
grep -q "L1ERR_EXC .*code=30" "${RUN_DIR}/sim.log"
grep -q "REGRESSION_TEST_SUCCESS" "${RUN_DIR}/sim.log"

cat > "${RUN_DIR}/l1_nonblocking_cpu_error_report.md" <<EOF
# L1 Nonblocking CPU AXI Error Gate

Result: PASS

- Opt-in real CPU/D-cache path: L1 2-MSHR, ROB FIFO, CPU nonblocking.
- Downstream DDR behavioral model injects one SLVERR on physical line
  \`0x00008000\`.
- Write-through L2 drains the downstream error burst and returns an error
  burst without installing the poisoned line.
- CPU/ROB retires precise MIPS \`CacheErr\` (ExcCode 30); ErrorEPC recovery
  reaches the success mailbox.
- This is a simulation fault-injection contract, not DDR electrical fault
  coverage or arbitrary multi-error stress.
EOF
echo "L1 nonblocking CPU AXI error: PASS"
