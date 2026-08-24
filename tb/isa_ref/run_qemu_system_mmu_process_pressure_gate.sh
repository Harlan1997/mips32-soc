#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_mmu_process_pressure"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
RTL_RUN_DIR=${RTL_RUN_DIR:-"${ROOT_DIR}/build/soc_test/product_mmu_process_pressure"}
FW_DIR=${FW_DIR:-"${RTL_RUN_DIR}/firmware"}
FW_ELF=${FW_DIR}/firmware.elf
RTL_TRACE=${RTL_TRACE:-"${RUN_DIR}/rtl/rtl_retire.jsonl"}
QEMU_DIR=${QEMU_DIR:-"${RUN_DIR}/qemu"}

mkdir -p "${RUN_DIR}"
RUN_DIR=$(cd "${RUN_DIR}" && pwd)
RTL_TRACE=$(realpath -m "${RTL_TRACE}")
QEMU_DIR=$(realpath -m "${QEMU_DIR}")
mkdir -p "${RUN_DIR}/rtl" "${QEMU_DIR}"

TB_RETIRE_TRACE=1 RUN_DIR="${RUN_DIR}/rtl" RETIRE_TRACE="${RTL_TRACE}" \
    "${ROOT_DIR}/tb/soc_test/run_product_mmu_process_pressure.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1
RTL_RUN_DIR="${RUN_DIR}/rtl"
FW_DIR="${RTL_RUN_DIR}/firmware"
FW_ELF="${FW_DIR}/firmware.elf"
grep -q "REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8" "${RTL_RUN_DIR}/sim.log"

[[ -x "${QEMU_BIN}" ]]
[[ -s "${FW_ELF}" ]]
sha256sum "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"
"${QEMU_BIN}" --version >"${RUN_DIR}/qemu_build_identity.txt"

set +e
    env RUN_DIR="${QEMU_DIR}" FW_ELF="${FW_ELF}" RTL_TRACE="${RTL_TRACE}" \
    STOP_AFTER_MAILBOX=1 QEMU_CPU=24Kc \
    QEMU_MACHINE_PROPERTIES="software-mmu-guest=on,software-mmu-bootrom-guest=on" \
    REQUIRE_SMOKE_OUTPUT=0 "${ROOT_DIR}/tb/isa_ref/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1
qemu_status=$?
set -e

grep -q 'QEMU system retire capture: PASS' "${RUN_DIR}/qemu_gate.log"
grep -q '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System MMU Process Pressure Gate

- Result: PASS
- Firmware: ${FW_ELF}
- RTL evidence: product_mmu_process_pressure, refills=8
- QEMU machine: mips32-soc-ref
- Evidence: rtl_gate.log, firmware.sha256, rtl/rtl_retire.jsonl, qemu_gate.log, qemu/qemu_build_identity.txt, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Checked behavior: four software ASIDs, distinct PFN mappings, context reuse,
  dynamic TLB shootdown, wired mapping retention, and post-shootdown refills.
- Differential: $(grep '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log")
- Residual risk: OS scheduler/page-table ownership, multicore shootdown,
  Linux boot, and full privileged/ISA differential remain open.
EOF
echo "QEMU system MMU process pressure: PASS"
