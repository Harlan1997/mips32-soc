#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-generic-userspace}
RUN_DIR=$(realpath -m "${RUN_DIR}")
KERNEL=${KERNEL:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts/vmlinux}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-}
VALIDATE_EXISTING_RUN=${VALIDATE_EXISTING_RUN:-0}

mkdir -p "${RUN_DIR}"
runner_rc=0
if [[ "${VALIDATE_EXISTING_RUN}" != "1" ]]; then
    set +e
    env RUN_DIR="${RUN_DIR}" KERNEL="${KERNEL}" \
        LINUX_IMAGE_DIR="${LINUX_IMAGE_DIR}" SKIP_LINUX_BUILD=1 REUSE_LINUX_IMAGE=1 \
        LINUX_RNG_SEED="${LINUX_RNG_SEED}" \
        LINUX_PROFILE=generic LINUX_REQUIRE_PROGRESS=1 LINUX_REQUIRE_USERSPACE=1 \
        "${SCRIPT_DIR}/run_rtl_linux_progress_gate.sh" \
        >"${RUN_DIR}/progress_runner.log" 2>&1
    runner_rc=$?
    set -e
else
    echo "RTL generic userspace gate: validating existing bounded RTL evidence" \
        >"${RUN_DIR}/progress_runner.log"
fi

SIM_LOG="${RUN_DIR}/sim/sim.log"
[[ -s "${SIM_LOG}" ]]
UART_TRANSCRIPT="${RUN_DIR}/sim/uart.transcript"
marker_source="${SIM_LOG}"
if [[ -s "${UART_TRANSCRIPT}" ]]; then
    marker_source="${UART_TRANSCRIPT}"
fi
if [[ "${runner_rc}" -ne 0 ]]; then
    echo "RTL generic userspace gate: progress runner failed (status ${runner_rc})" >&2
    exit "${runner_rc}"
fi

required_markers=(
    MIPS32_SOC_LINUX_BOOT_SUCCESS
    MIPS32_SOC_LINUX_GPIO_SUCCESS
    MIPS32_SOC_LINUX_MPROTECT_FAULT_SUCCESS
    MIPS32_SOC_LINUX_MPROTECT_SUCCESS
    MIPS32_SOC_LINUX_BRK_SUCCESS
    MIPS32_SOC_LINUX_SLEEP_SUCCESS
    MIPS32_SOC_LINUX_MMAP_SUCCESS
    MIPS32_SOC_LINUX_EXEC_SUCCESS
    MIPS32_SOC_LINUX_YIELD_SUCCESS
    MIPS32_SOC_LINUX_WAIT_STATUS_SUCCESS
    MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS
)

# Progress/UART diagnostics are emitted by separate simulator paths and can
# split a marker across writes. Remove complete diagnostic records before
# checking presence and order so the gate observes the guest byte stream.
normalize_marker_stream() {
    local log_path=$1
    tr -d '\r\n' <"${log_path}" |
        sed -E \
            -e 's/LINUX_PROGRESS_TRACE cycle=[0-9]+ pc=[0-9A-Fa-f]{8}[[:space:]]+retire=[0-9A-Fa-f]+//g' \
            -e 's/LINUX_TASK_LOAD_TRACE cycle=[0-9]+ pc=[0-9A-Fa-f]{8} inst=[0-9A-Fa-f]{8} va=[0-9A-Fa-f]{8} pa=[0-9A-Fa-f]{8} data=[0-9A-Fa-f]{8} gp4=[0-9A-Fa-f]{8}//g'
}

marker_stream=$(normalize_marker_stream "${marker_source}")
marker_stream_file="${RUN_DIR}/sim/markers.normalized.log"
printf '%s' "${marker_stream}" >"${marker_stream_file}"
for marker in "${required_markers[@]}"; do
    rg -q "${marker}" "${marker_stream_file}"
done
marker_order=$(
    for marker in "${required_markers[@]}"; do
        # -m limits matching lines, while the transcript is normalized to one
        # line and can contain the boot marker twice. Keep the first byte
        # offset explicitly so the second terminal boot marker cannot make a
        # valid sequence look out of order.
        rg -bo -m 1 "${marker}" "${marker_stream_file}" |
            cut -d: -f1 | head -n 1
    done
)
previous_line=0
while IFS= read -r marker_line; do
    [[ -n "${marker_line}" ]] || continue
    if (( marker_line <= previous_line )); then
        echo "RTL generic userspace gate: required markers are out of order" >&2
        exit 1
    fi
    previous_line=${marker_line}
done <<<"${marker_order}"
if rg -i -q 'Kernel panic|Oops:|BUG:|REGRESSION_TEST_FAILED|SIGABRT|MIPS32_SOC_LINUX_[A-Z0-9_]+_FAILURE' \
    "${SIM_LOG}" "${marker_source}"; then
    echo "RTL generic userspace gate: fatal Linux/simulator diagnostic found" >&2
    exit 1
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux Generic Userspace Gate

- Result: PASS
- Kernel: ${KERNEL}
- Image directory: ${LINUX_IMAGE_DIR}
- Evidence: process/VM, GPIO, timer/sleep, protection-fault, exec, and
  fork/wait guest markers were all observed in order in ${marker_source}.
- Scope: the declared bounded userspace workload only; arbitrary Linux
  applications, SMP, and full ISA/MMU compliance remain separate contracts.
EOF
echo "RTL Linux generic userspace gate: PASS"
