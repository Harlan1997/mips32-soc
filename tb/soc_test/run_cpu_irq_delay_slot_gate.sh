#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${FW_DIR:-${ROOT_DIR}/build/firmware/cpu_irq_delay_slot}
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/soc_test/cpu_irq_delay_slot}
FW_HEX="${FW_DIR}/firmware.hex"

make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=cpu_irq_delay_slot \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all

FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}" \
  VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK +define+SOC_DELAY_SLOT_ROLLBACK_ENABLE=1" \
  "${ROOT_DIR}/tb/soc_test/run.sh"

grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/sim.log"
summary=$(grep 'CPU_CP0_SUMMARY ' "${RUN_DIR}/sim.log" | tail -1)
if [[ -z "${summary}" ]]; then
    echo "ERROR: CPU/CP0 summary missing from delay-slot gate" >&2
    exit 1
fi
intr_count=$(sed -n 's/.* intr=\([0-9][0-9]*\) .*/\1/p' <<<"${summary}")
eret_count=$(sed -n 's/.* eret=\([0-9][0-9]*\).*/\1/p' <<<"${summary}")
if [[ -z "${intr_count}" || "${intr_count}" -lt 1 ||
      -z "${eret_count}" || "${eret_count}" -lt 1 ]]; then
    echo "ERROR: delay-slot retirement probe did not observe interrupt/ERET: ${summary}" >&2
    exit 1
fi
cat > "${RUN_DIR}/cpu_irq_delay_slot_completion_report.md" <<EOF
# CPU Delay-Slot Interrupt Retirement Gate

- Result: PASS
- Firmware: $(realpath "${FW_HEX}")
- Interrupts observed: ${intr_count}
- ERET instructions observed: ${eret_count}
- Contract: an interrupt accepted in the target branch delay slot must retain
  the delay-slot WB bundle for EPC/BD diagnostics while suppressing its GPR
  commit; ERET then replays the branch with the pre-slot register value.
- Negative path: an early commit changes v0 to 10 before ERET replay and
  reaches the failure mailbox instead of REGRESSION_TEST_SUCCESS.
EOF
echo "CPU IRQ branch-delay-slot gate: PASS"
