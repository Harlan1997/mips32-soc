#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_mmu_contract"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
RTL_RUN_DIR=${RTL_RUN_DIR:-"${ROOT_DIR}/build/soc_test/product_mmu_asid_context"}
FW_DIR=${FW_DIR:-"${RTL_RUN_DIR}/firmware"}
FW_ELF=${FW_DIR}/firmware.elf
RTL_TRACE=${RTL_TRACE:-"${RUN_DIR}/rtl/rtl_retire.jsonl"}
QEMU_DIR=${QEMU_DIR:-"${RUN_DIR}/qemu"}

mkdir -p "${RUN_DIR}"
RUN_DIR=$(realpath -m "${RUN_DIR}")
RTL_TRACE=$(realpath -m "${RTL_TRACE}")
QEMU_DIR=$(realpath -m "${QEMU_DIR}")
mkdir -p "${RUN_DIR}/rtl" "${QEMU_DIR}"

# The RTL gate is the architectural producer for the software refill and
# shootdown contract.  Keep its existing VCS entry point and evidence intact.
TB_RETIRE_TRACE=1 RUN_DIR="${RUN_DIR}/rtl" RETIRE_TRACE="${RTL_TRACE}" \
    "${ROOT_DIR}/tb/soc_test/run_product_mmu_asid_context.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1
RTL_RUN_DIR="${RUN_DIR}/rtl"
FW_DIR="${RTL_RUN_DIR}/firmware"
FW_ELF="${FW_DIR}/firmware.elf"

[[ -x "${QEMU_BIN}" ]]
[[ -s "${FW_ELF}" ]]
sha256sum "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"
"${QEMU_BIN}" --version >"${RUN_DIR}/qemu_build_identity.txt"

env RUN_DIR="${QEMU_DIR}" FW_ELF="${FW_ELF}" RTL_TRACE="${RTL_TRACE}" \
    STOP_AFTER_MAILBOX=1 QEMU_CPU=24Kc \
    QEMU_MACHINE_PROPERTIES="software-mmu-guest=on,software-mmu-bootrom-guest=on" \
    REQUIRE_SMOKE_OUTPUT=0 "${ROOT_DIR}/tb/isa_ref/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1
grep -q 'QEMU system retire capture: PASS' "${RUN_DIR}/qemu_gate.log"
grep -q '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System MMU Contract Gate

- Result: PASS
- RTL gate: product_mmu_asid_context, software refill and APB shootdown
- QEMU machine: mips32-soc-ref
- Firmware: ${FW_ELF}
- Evidence: rtl_gate.log, firmware.sha256, rtl/rtl_retire.jsonl, qemu_gate.log, qemu/qemu_build_identity.txt, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Checked behavior: ASID-specific refill, ASID reuse, shootdown ACK, post-shootdown refill, wired APB mapping, success mailbox boundary
- Differential: $(grep '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log")
- Residual risk: demand paging, OS page-table ownership, multi-core shootdown, Linux boot, complete privileged ISA, and full MMU differential remain open.
EOF
echo "QEMU system MMU contract: PASS"
