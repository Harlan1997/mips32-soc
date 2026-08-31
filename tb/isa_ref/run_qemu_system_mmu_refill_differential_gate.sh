#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_mmu_refill_differential"}
RTL_DIR=${RTL_DIR:-"${RUN_DIR}/rtl"}
RTL_TRACE=${RTL_TRACE:-"${RTL_DIR}/rtl_retire.jsonl"}
RTL_RUN_DIR=${RTL_RUN_DIR:-"${RTL_DIR}/soc"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/tb/soc_test/fw/tests/mmu_refill"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
QEMU_DIR=${QEMU_DIR:-"${RUN_DIR}/qemu"}
OS_PRESSURE=${OS_PRESSURE:-0}
QEMU_MACHINE_PROPERTIES=${QEMU_MACHINE_PROPERTIES:-"software-mmu-guest=on"}
if [[ "${OS_PRESSURE}" == 1 ]]; then
    WORKLOAD_SCOPE="four-ASID OS-style page-table ownership pressure, task switching and per-task post-shootdown demand refill"
else
    WORKLOAD_SCOPE="two-level 4KB software page-table demand refill, four backing pages and permission recovery"
fi

RUN_DIR=$(realpath -m "${RUN_DIR}")
RTL_DIR=$(realpath -m "${RTL_DIR}")
RTL_TRACE=$(realpath -m "${RTL_TRACE}")
RTL_RUN_DIR=$(realpath -m "${RTL_RUN_DIR}")
FW_DIR=$(realpath -m "${FW_DIR}")
FW_ELF=$(realpath -m "${FW_ELF}")
FW_HEX=$(realpath -m "${FW_HEX}")
QEMU_DIR=$(realpath -m "${QEMU_DIR}")
mkdir -p "${RUN_DIR}" "${RTL_DIR}" "${QEMU_DIR}"

# This is the opt-in two-level 4KB software page-table workload.  The
# standalone SoC runner owns the TB_MMU_REFILL completion-marker check and
# emits the same retire schema used by the QEMU comparator.
RUN_DIR="${RTL_RUN_DIR}" OS_PRESSURE="${OS_PRESSURE}" TB_RETIRE_TRACE=1 RETIRE_TRACE="${RTL_TRACE}" \
    tb/soc_test/run_mmu_refill.sh >"${RUN_DIR}/rtl_gate.log" 2>&1
[[ -s "${RTL_TRACE}" && -s "${FW_ELF}" && -s "${FW_HEX}" ]]

# The RTL runner rebuilds the workload into its run-local firmware directory.
# Point QEMU at that exact ELF; using the repository source ELF here can leave
# a stale build in the reference path and cause an early retire mismatch.
FW_ELF="${RTL_RUN_DIR}/firmware/firmware.elf"
FW_ELF=$(realpath -m "${FW_ELF}")
[[ -s "${FW_ELF}" ]]

sha256sum "${FW_HEX}" "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"

env RUN_DIR="${QEMU_DIR}" FW_ELF="${FW_ELF}" RTL_TRACE="${RTL_TRACE}" \
    QEMU_CPU=24Kc QEMU_MACHINE_PROPERTIES="${QEMU_MACHINE_PROPERTIES}" \
    REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

grep -q '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System MMU Refill RTL Retire Differential

- Result: PASS
- Firmware: ${FW_ELF}
- RTL trace: ${RTL_TRACE}
- QEMU trace: ${QEMU_DIR}/qemu_retire.jsonl
- Comparator: $(grep '^TRACE_COMPARE_PASS ' "${QEMU_DIR}/trace_compare.log")
- Scope: opt-in ${WORKLOAD_SCOPE}, ERET retry and mailbox completion.
- OS pressure extension: ${OS_PRESSURE} (four ASID-owned roots/L2 tables, task switching and per-task post-shootdown refill when enabled)
- Evidence: rtl_gate.log, firmware.sha256, qemu_gate.log, qemu/completion_report.md, qemu/qemu_build_identity.txt, qemu/trace_compare.log
- Residual risk: larger page sizes, production OS allocator/scheduler policy, multicore shootdown, full privileged/MMU compliance, Linux VM, and physical device timing remain open.
EOF
echo "QEMU system MMU refill RTL retire differential: PASS"
