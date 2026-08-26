#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_vic_cpu_differential"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_vic_cpu"}

RTL_IRQ_REPLAY=1 RTL_IRQ_SCHEDULE_OFFSET=-1 IRQ_REPLAY_PIC_MASK=0x300 FW_TEST=vic_cpu FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

grep -q '^TRACE_COMPARE_PASS records=736$' "${RUN_DIR}/qemu/trace_compare.log"
grep -q '^REGRESSION_TEST_SUCCESS$' "${RUN_DIR}/rtl/vcs_uvm.log"
grep -q 'vic_cpu test: REGRESSION_TEST_SUCCESS' "${RUN_DIR}/qemu/qemu_stdout.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Full VIC CPU RTL Retire Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: 736 compared retire records through the magic mailbox retirement boundary (source traces contain 737 records on each side), covering UART output, reset defaults, enable set/clear, software sources 4/5 and 6/7 priority arbitration, simultaneous CPU IRQ sources 8/9, VEC_ID, ACK/SOFT_CLR, two interrupt entries/ERET returns, and the magic mailbox.
- Evidence: firmware_build.log, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Residual risk: external interrupt timing/replay, nested interrupt schedules, VEIC vectors, reset-in-flight, and device error paths remain separate gates.
EOF
echo "QEMU system full VIC CPU RTL retire differential: PASS"
