#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_current_contract"}
mkdir -p "${RUN_DIR}"

run_gate() {
    local name=$1
    shift
    echo "== ${name} ==" | tee "${RUN_DIR}/${name}.log"
    "$@" >>"${RUN_DIR}/${name}.log" 2>&1
}

run_gate qemu_system_peripheral_contract \
    make -C "${ROOT_DIR}" qemu-system-peripheral-contract-gate
run_gate qemu_system_dma_v2_model \
    make -C "${ROOT_DIR}" qemu-system-dma-v2-model-gate
run_gate qemu_system_qspi \
    make -C "${ROOT_DIR}" qemu-system-qspi-gate
run_gate qemu_system_ddr \
    make -C "${ROOT_DIR}" qemu-system-ddr-gate
run_gate qemu_system_retire_capture \
    make -C "${ROOT_DIR}" qemu-system-retire-capture-gate

QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
{
    "${QEMU_BIN}" --version
    sha256sum "${QEMU_BIN}"
} >"${RUN_DIR}/qemu_build_identity.txt"

reports=(
    "${ROOT_DIR}/build/isa_ref/qemu_system_peripherals/completion_report.md"
    "${ROOT_DIR}/build/isa_ref/qemu_system_dma_v2_model/completion_report.md"
    "${ROOT_DIR}/build/isa_ref/qemu_system_qspi/completion_report.md"
    "${ROOT_DIR}/build/isa_ref/qemu_system_ddr/completion_report.md"
    "${ROOT_DIR}/build/isa_ref/qemu_system_retire/completion_report.md"
)
for report in "${reports[@]}"; do
    [[ -s "${report}" ]]
done

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Current Contract Gate

- Result: PASS
- Machine: mips32-soc-ref
- Sub-gates: GPIO/timer/PIC/peripheral contract, DMA v2 model, QSPI
  command/FIFO model, DDR behavioral window model, and retire capture.
- Evidence: qemu_system_*.log, qemu_build_identity.txt, and the five child
  completion reports under build/isa_ref/.
- Differential boundary: selected RTL/QEMU differential gates remain separate;
  this aggregate does not claim full ISA/MMU/Linux differential equality.
- Residual risk: QSPI/DDR are transaction-level behavioral models; DMA v2
  long-form retire equality remains blocked by implementation-dependent RTL
  polling latency; PHY/JEDEC/device timing, SG/reset-in-flight, full MMU
  demand paging, full ISA/FPU and Linux/OS boot remain open.
EOF
echo "QEMU system current contract gate: PASS"
