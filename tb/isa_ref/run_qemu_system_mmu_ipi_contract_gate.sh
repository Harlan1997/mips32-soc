#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_mmu_ipi_contract"}
RTL_DIR=${RUN_DIR}/rtl
QEMU_DIR=${RUN_DIR}/qemu
FW_DIR=${ROOT_DIR}/build/firmware/dual_core_ipi
FW_HEX=${FW_DIR}/firmware.hex
FW_ELF=${FW_DIR}/firmware.elf
RTL_TRACE=${RTL_DIR}/rtl_retire.jsonl

mkdir -p "${RTL_DIR}" "${QEMU_DIR}"
make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=dual_core_ipi \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware all >"${RUN_DIR}/firmware_build.log" 2>&1

# The RTL run covers both APB mailbox instances through the actual dual-core
# fabric. Its retire capture is used for the shared architectural event view.
FW_HEX="${FW_HEX}" RUN_DIR="${RTL_DIR}" \
TB_RETIRE_TRACE=1 RETIRE_TRACE="${RTL_TRACE}" \
VCS_EXTRA_ARGS='+define+SOC_ENABLE_DUAL_CORE +define+TB_RETIRE_TRACE' \
SIM_EXTRA_ARGS="+RETIRE_TRACE=${RTL_TRACE}" \
SKIP_URG_EXCLUSION_CHECK=1 "${ROOT_DIR}/tb/soc_test/run.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1
grep -q 'REGRESSION_TEST_SUCCESS' "${RTL_DIR}/sim.log"
test -s "${RTL_TRACE}"

# QEMU is intentionally a single-vCPU reference machine. It models the two
# mailbox state machines and target ACK/timeout outcomes, then runs the same
# guest request stream to completion.
FW_ELF="${FW_ELF}" RUN_DIR="${QEMU_DIR}" STOP_AFTER_MAILBOX=1 \
REQUIRE_SMOKE_OUTPUT=0 QEMU_TIMEOUT=8 QEMU_CPU=24Kc \
"${ROOT_DIR}/tb/isa_ref/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1
grep -q 'QEMU system retire capture: PASS' "${RUN_DIR}/qemu_gate.log"
test -s "${QEMU_DIR}/qemu_retire.jsonl"

python3 "${SCRIPT_DIR}/compare_mmu_ipi_contract.py" \
    "${RTL_TRACE}" "${QEMU_DIR}/qemu_retire.jsonl" \
    >"${RUN_DIR}/contract_compare.log"
grep -q '^IPI_CONTRACT_COMPARE_PASS ' "${RUN_DIR}/contract_compare.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System MMU IPI Contract Gate

- Result: PASS
- Firmware: ${FW_ELF}
- RTL: dual-core APB mailbox RTL/UVM path with retire capture
- QEMU: mips32-soc-ref explicit core-0/core-1 mailbox windows
- Evidence: firmware_build.log, rtl_gate.log, rtl/rtl_retire.jsonl, qemu_gate.log, qemu/qemu_retire.jsonl, contract_compare.log
- Checked behavior: target ACK, reverse target routing, W1C, target absent timeout, stale ACK timeout, rejected while busy, and reset fault controls
- Differential: bounded APB event contract comparison, $(grep '^IPI_CONTRACT_COMPARE_PASS ' "${RUN_DIR}/contract_compare.log")
- Scope boundary: QEMU remains single-vCPU; this does not claim Linux SMP scheduling, complete multicore TLB shootdown, or data coherency protocol signoff.
EOF
echo "QEMU system MMU IPI contract: PASS"
