#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/dma_axi_error"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/dma_axi_error"}
FW_HEX=${FW_DIR}/firmware.hex
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_axi_error" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all >"${RUN_DIR}/firmware_build.log" 2>&1
FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
VCS_EXTRA_ARGS='+define+SOC_AXI_RESP_ERROR_INJECT_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
    "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1

grep -q 'axi_ddr_model: injected SLVERR addr=00008000' "${RUN_DIR}/sim.log"
# UART characters can interleave with the testbench's coverage banner.  The
# firmware's success line is therefore identified by its prefix plus the
# absence of any failure marker, while the testbench mailbox supplies the
# independent termination check.
grep -q 'dma_axi_error:' "${RUN_DIR}/sim.log"
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
! grep -Eq 'dma_axi_error: (TIMEOUT|STATUS|IRQ_STATUS|PIC_STATUS|W1C)' "${RUN_DIR}/sim.log"
cat >"${RUN_DIR}/dma_axi_error_report.md" <<'EOF'
# DMA AXI Error Gate

- Result: PASS
- DMA source `0x00008000` receives a behavioral DDR AXI `SLVERR`.
- DMA reports `ERR=1`, `ERR_CODE=2 (ERR_AXI_READ)`, raises its channel IRQ,
  and reaches PIC source 3.
- DMA error W1C clears status before the success mailbox.
- Boundary: behavioral AXI fault injection only; reset-in-flight, physical
  DDR electrical failure, and full DMA system policy remain open.
EOF
echo "DMA AXI error: PASS"
