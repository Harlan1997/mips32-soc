#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_uart_vic_transaction_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_uart_vic"}
RTL_UART=${RUN_DIR}/rtl_uart_apb_schedule.txt
QEMU_TRACE=${RUN_DIR}/qemu/peripheral_trace.jsonl
RTL_TRACE=${RUN_DIR}/rtl/sim.log
RTL_VIC_TRACE=${RUN_DIR}/rtl_vic_trace.log

mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RTL_UART}" "${RTL_TRACE}" "${RTL_VIC_TRACE}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_uart_vic" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

# These streams are independent of the retire comparator.  Cycle numbers are
# retained in the RTL schedule for diagnosis but are intentionally ignored by
# the normalized transaction comparator.
FW_HEX="${FW_DIR}/firmware.hex" RUN_DIR="${RUN_DIR}/rtl" \
SKIP_COVERAGE=1 \
VCS_EXTRA_ARGS="+define+TB_LINUX_BOOT_TRACE +define+TB_LINUX_DIFF_UART_TIMING" \
SIM_EXTRA_ARGS="+LINUX_UART_APB_SCHEDULE_PATH=${RTL_UART} +LINUX_VIC_TRACE=1 +LINUX_VIC_TRACE_LIMIT=4096" \
    "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1

env RUN_DIR="${RUN_DIR}/qemu" FW_ELF="${FW_DIR}/firmware.elf" \
QEMU_PERIPHERAL_TRACE="${QEMU_TRACE}" \
QEMU_PLUGIN_UART_TRACE="${RUN_DIR}/qemu/plugin_uart_trace.log" \
QEMU_MACHINE_PROPERTIES="uart-diff-timing=on" \
REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=1 SKIP_COMPARE=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

test -s "${RTL_UART}"
test -s "${RTL_TRACE}"
test -s "${QEMU_TRACE}"
rg 'LINUX_VIC_TRACE ' "${RTL_TRACE}" >"${RTL_VIC_TRACE}"
test -s "${RTL_VIC_TRACE}"
python3 "${ROOT_DIR}/scripts/compare_peripheral_transactions.py" \
    --kind uart --ref "${QEMU_TRACE}" --dut "${RTL_UART}" \
    >"${RUN_DIR}/uart_transaction_compare.log" 2>&1
python3 "${ROOT_DIR}/scripts/compare_peripheral_transactions.py" \
    --kind vic --ref "${QEMU_TRACE}" --dut "${RTL_VIC_TRACE}" \
    >"${RUN_DIR}/vic_transaction_compare.log" 2>&1

uart_records=$(python3 - "${QEMU_TRACE}" <<'PY'
import json
import sys
print(sum(1 for line in open(sys.argv[1])
          if json.loads(line).get("kind") == "uart"))
PY
)
vic_records=$(python3 - "${QEMU_TRACE}" <<'PY'
import json
import sys
print(sum(1 for line in open(sys.argv[1])
          if json.loads(line).get("kind") == "vic"))
PY
)
(( uart_records == 3 && vic_records == 6 ))
rg -q '^PERIPHERAL_DIFF_PASS kind=uart records=3$' "${RUN_DIR}/uart_transaction_compare.log"
rg -q '^PERIPHERAL_DIFF_PASS kind=vic records=6$' "${RUN_DIR}/vic_transaction_compare.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System UART/VIC Transaction Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- UART records: ${uart_records}
- VIC records: ${vic_records}
- Evidence: qemu/peripheral_trace.jsonl, rtl_uart_apb_schedule.txt,
  rtl/sim.log, rtl_vic_trace.log, uart_transaction_compare.log,
  vic_transaction_compare.log, rtl_gate.log, qemu_gate.log
- Contract: normalized ordered UART APB accesses (including reads) and VIC
  state transitions are compared independently of simulation cycle numbers.
  CPU Cause/Status and acceptance fields remain in the raw traces and are
  covered by the architectural retire differential; they are not used as
  peripheral transition keys because their sampling edge is CPU-registered.
EOF
echo "QEMU system UART/VIC transaction differential: PASS"
