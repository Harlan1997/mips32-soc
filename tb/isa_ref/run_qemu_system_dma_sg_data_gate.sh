#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_dma_sg_data"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_dma_sg"}
FW_HEX=${FW_DIR}/firmware.hex
FW_ELF=${FW_DIR}/firmware.elf
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_dma_sg" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
# VCS module setup can export an SCL driver-only library path.  It is needed
# by the simulator but must not be inherited by the independently built QEMU.
env -u LD_LIBRARY_PATH timeout "${QEMU_TIMEOUT:-30}" "${QEMU_BIN}" \
    -M mips32-soc-ref -cpu 24Kc -m 64K -kernel "${FW_ELF}" \
    -nographic -monitor none >"${RUN_DIR}/qemu_stdout.log" \
    2>"${RUN_DIR}/qemu_stderr.log"

FW_HEX="${FW_HEX}" TESTNAME=soc_base_test SEED=1 RUN_DIR="${RUN_DIR}/rtl" \
    VCS_EXTRA_ARGS='+define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
    "${ROOT_DIR}/tb/uvm_tb/run_uvm.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/rtl_gate.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DMA v2 SG Data Gate

- Result: PASS
- Firmware: ${FW_ELF}
- RTL evidence: rtl_gate.log and the firmware's eight-word post-DMA compare
- QEMU evidence: qemu_stdout.log, qemu_stderr.log and clean guest shutdown
- Contract: two linked 16-byte descriptors perform real source-to-destination
  data movement on both the RTL SoC and the mips32-soc-ref machine. The guest
  compares all eight destination words before writing the success mailbox.
- Residual risk: this is a bounded data contract, not a full RTL/QEMU
  per-retire differential, physical AXI fault/reset timing, or Linux DMA ABI.
EOF
echo "QEMU system DMA v2 SG data gate: PASS"
