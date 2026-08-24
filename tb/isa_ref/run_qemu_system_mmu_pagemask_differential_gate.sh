#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_mmu_pagemask_differential"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}
QEMU_DIR=${QEMU_DIR:-"${RUN_DIR}/qemu"}
RTL_DIR=${RTL_DIR:-"${RUN_DIR}/rtl"}
RTL_TRACE=${RTL_TRACE:-"${RTL_DIR}/rtl_retire.jsonl"}

RUN_DIR=$(realpath -m "${RUN_DIR}")
FW_DIR=$(realpath -m "${FW_DIR}")
FW_ELF=$(realpath -m "${FW_ELF}")
QEMU_DIR=$(realpath -m "${QEMU_DIR}")
RTL_DIR=$(realpath -m "${RTL_DIR}")
RTL_TRACE=$(realpath -m "${RTL_TRACE}")
mkdir -p "${RUN_DIR}" "${FW_DIR}" "${QEMU_DIR}" "${RTL_DIR}"

TB_RETIRE_TRACE=1 RUN_DIR="${RTL_DIR}" RETIRE_TRACE="${RTL_TRACE}" \
    "${ROOT_DIR}/tb/soc_test/run_product_mmu_pagemask.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1
FW_DIR="${RTL_DIR}/firmware"
FW_ELF="${FW_DIR}/firmware.elf"
[[ -s "${FW_ELF}" ]]
sha256sum "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"

env RUN_DIR="${QEMU_DIR}" FW_ELF="${FW_ELF}" QEMU_CPU=24Kc \
    STOP_AFTER_MAILBOX=1 RTL_TRACE="${RTL_TRACE}" \
    QEMU_MACHINE_PROPERTIES="software-mmu-guest=on,software-mmu-bootrom-guest=on" \
    REQUIRE_SMOKE_OUTPUT=0 "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

grep -q 'QEMU system retire capture: PASS' "${RUN_DIR}/qemu_gate.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System MMU PageMask Gate

- Result: PASS
- Firmware: ${FW_ELF}
- QEMU machine: mips32-soc-ref
- Scope: opt-in boot-ROM software-managed TLB workload covering 4KB, 16KB, 64KB, and 256KB PageMask programming, ASIDs 4-7, even/odd halves, and mailbox completion.
- Evidence: rtl_gate.log, firmware.sha256, qemu_gate.log, rtl/rtl_retire.jsonl, qemu/qemu_build_identity.txt, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Differential: $(grep '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log")
- Residual risk: OS demand paging, allocator/scheduler ownership, multicore shootdown, privileged ISA, Linux VM, and physical device timing remain open.
EOF
echo "QEMU system MMU PageMask architectural gate: PASS"
