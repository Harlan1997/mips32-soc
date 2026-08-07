#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/sva"}
SOC_RUN_DIR=${SOC_RUN_DIR:-"${RUN_ROOT}/soc_smoke"}
RESET_RUN_DIR=${RESET_RUN_DIR:-"${RUN_ROOT}/reset_sync"}
AXI_RUN_DIR=${AXI_RUN_DIR:-"${RUN_ROOT}/axi_sram"}

mkdir -p "${RUN_ROOT}" "${RESET_RUN_DIR}" "${AXI_RUN_DIR}"

echo "--- SVA SoC gate ---"
SVA_ENABLE=1 RUN_DIR="${SOC_RUN_DIR}" \
    FW_HEX="${FW_HEX:-${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex}" \
    "${ROOT_DIR}/tb/soc_test/run.sh"

echo "--- SVA reset_sync gate ---"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs
(
    cd "${RESET_RUN_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps -cm assert \
        +define+SVA_ENABLE \
        "${ROOT_DIR}/rtl/clock/reset_sync.v" \
        "${ROOT_DIR}/tb/sva/reset_sync_props.sv" \
        "${ROOT_DIR}/tb/sva/reset_sync_bind.sv" \
        "${ROOT_DIR}/tb/unit/clock/tb_reset_sync.v" -l compile.log
    ./simv -cm assert -l sim.log
)

echo "--- SVA AXI SRAM gate ---"
(
    cd "${AXI_RUN_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps -cm assert \
        +define+SVA_ENABLE \
        "${ROOT_DIR}/rtl/perips/axi_sram.v" \
        "${ROOT_DIR}/tb/sva/axi4_protocol_props.sv" \
        "${ROOT_DIR}/tb/sva/axi_sram_bind.sv" \
        "${ROOT_DIR}/tb/sva/tb_axi_sram_sva.sv" -l compile.log
    ./simv -cm assert -l sim.log
)

if grep -R -n -E 'SVA_FAIL|REGRESSION_TEST_FAIL|Error-[A-Z]+.*assert' \
        "${SOC_RUN_DIR}/sim.log" "${RESET_RUN_DIR}/sim.log" "${AXI_RUN_DIR}/sim.log"; then
    echo "SVA gate: FAIL"
    exit 1
fi

cat > "${RUN_ROOT}/sva_completion_report.md" <<EOF
# SVA Simulation Gate Report

- Status: \`SIM_ASSERT_CLOSED\`
- SoC run: \`${SOC_RUN_DIR}\`
- Reset synchronizer run: \`${RESET_RUN_DIR}\`
- AXI SRAM run: \`${AXI_RUN_DIR}\`
- Scope: AXI safety/backpressure, APB transfer protocol, and reset synchronizer assertions.
- Non-claim: no formal, CDC/RDC, lint, or product-level coverage signoff.
EOF

echo "SVA gate: PASS"
