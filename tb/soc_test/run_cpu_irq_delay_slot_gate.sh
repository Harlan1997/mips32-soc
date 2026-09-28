#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FW_DIR=${FW_DIR:-${ROOT_DIR}/build/firmware/cpu_irq_delay_slot}
RUN_DIR=${RUN_DIR:-${ROOT_DIR}/build/soc_test/cpu_irq_delay_slot}
FW_HEX="${FW_DIR}/firmware.hex"

make -C "${ROOT_DIR}/tb/soc_test/fw" FW_NAME=cpu_irq_delay_slot \
  OUT_DIR="${FW_DIR}" FW_BASE=firmware all

run_case() {
    local mode=$1
    local case_dir="${RUN_DIR}/mode${mode}"
    local case_log="${case_dir}/sim.log"
    mkdir -p "${case_dir}"
    FW_HEX="${FW_HEX}" RUN_DIR="${case_dir}" \
      SIM_EXTRA_ARGS="${SIM_EXTRA_ARGS:-} +IRQ_DELAY_BUBBLE_MODE=${mode}" \
      VCS_EXTRA_ARGS="${VCS_EXTRA_ARGS:-} +define+TB_SKIP_UART_PIN_CHECK +define+SOC_DELAY_SLOT_ROLLBACK_ENABLE=1" \
      "${ROOT_DIR}/tb/soc_test/run.sh"

    grep -q 'REGRESSION_TEST_SUCCESS' "${case_log}"
    local summary
    summary=$(grep 'CPU_CP0_SUMMARY ' "${case_log}" | tail -1)
    if [[ -z "${summary}" ]]; then
        echo "ERROR: CPU/CP0 summary missing from delay-slot mode ${mode}" >&2
        exit 1
    fi
    local intr_count eret_count wb_ex_count wb_id_count unowned_bd_count
    intr_count=$(sed -n 's/.* intr=\([0-9][0-9]*\) .*/\1/p' <<<"${summary}")
    eret_count=$(sed -n 's/.* eret=\([0-9][0-9]*\).*/\1/p' <<<"${summary}")
    wb_ex_count=$(sed -n 's/.* wb_ex=\([0-9][0-9]*\) .*/\1/p' <<<"${summary}")
    wb_id_count=$(sed -n 's/.* wb_id=\([0-9][0-9]*\) .*/\1/p' <<<"${summary}")
    unowned_bd_count=$(sed -n 's/.* unowned_bd=\([0-9][0-9]*\).*/\1/p' <<<"${summary}")
    if [[ -z "${intr_count}" || "${intr_count}" -lt 1 ||
          -z "${eret_count}" || "${eret_count}" -lt 1 ]]; then
        echo "ERROR: mode ${mode} did not observe interrupt/ERET: ${summary}" >&2
        exit 1
    fi
    if [[ "${mode}" -eq 1 && ( -z "${wb_ex_count}" || "${wb_ex_count}" -lt 1 ) ]]; then
        echo "ERROR: mode 1 did not directly observe WB-to-EX recovery: ${summary}" >&2
        exit 1
    fi
    if [[ "${mode}" -eq 2 && ( -z "${wb_id_count}" || "${wb_id_count}" -lt 1 ) ]]; then
        echo "ERROR: mode 2 did not directly observe WB-to-ID recovery: ${summary}" >&2
        exit 1
    fi
    if [[ -z "${unowned_bd_count}" || "${unowned_bd_count}" -ne 0 ]]; then
        echo "ERROR: mode ${mode} observed Cause.BD without a recognized owner: ${summary}" >&2
        exit 1
    fi
    printf '%s\n' "${summary}" > "${case_dir}/cpu_cp0_summary.txt"
    echo "CPU delay-slot mode ${mode}: PASS (${summary})"
}

run_case 1
run_case 2

cat > "${RUN_DIR}/cpu_irq_delay_slot_completion_report.md" <<EOF
# CPU Delay-Slot Interrupt Retirement Gate

- Result: PASS
- Firmware: $(realpath "${FW_HEX}")
- Mode 1 run: \`${RUN_DIR}/mode1/sim.log\` (one ID/EX bubble, WB-to-EX)
- Mode 2 run: \`${RUN_DIR}/mode2/sim.log\` (two ID/EX bubbles, WB-to-ID)
- Summaries: see \`${RUN_DIR}/mode{1,2}/cpu_cp0_summary.txt\`
- Contract: an interrupt accepted in the target branch delay slot must retain
  the delay-slot WB bundle for EPC/BD diagnostics while suppressing its GPR
  commit; ERET then replays the branch with the pre-slot register value.
- Coverage contract: mode 1 directly observes \`interrupt_wb_branch_delay_from_ex\`;
  mode 2 directly observes \`interrupt_wb_branch_delay_from_id\`.
- Negative path: an early commit changes v0 to 10 before ERET replay and
  reaches the failure mailbox instead of REGRESSION_TEST_SUCCESS.
EOF
echo "CPU IRQ branch-delay-slot gate: PASS"
