#!/usr/bin/env bash
set -euo pipefail

# Capture the current-source Linux failure window without turning a bounded
# diagnostic capture into a boot pass.  This gate is intentionally useful when
# generic Linux is still open: it returns PASS only when the checkpoint and
# terminal-state evidence are complete.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-root-cause}
RUN_DIR=$(realpath -m "${RUN_DIR}")
KERNEL=${KERNEL:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts/vmlinux}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts}
HOST_TIMEOUT=${HOST_TIMEOUT:-900s}
RTL_CYCLE_LIMIT=${RTL_CYCLE_LIMIT:-80000000}
LINUX_TIMEOUT_NS=${LINUX_TIMEOUT_NS:-$((RTL_CYCLE_LIMIT * 10))}
LINUX_CP0_TRACE_LIMIT=${LINUX_CP0_TRACE_LIMIT:-256}
LINUX_CP0_READ_TRACE_LIMIT=${LINUX_CP0_READ_TRACE_LIMIT:-1024}

mkdir -p "${RUN_DIR}"
[[ -s "${KERNEL}" ]]
[[ -s "${LINUX_IMAGE_DIR}/bootrom.hex" && -s "${LINUX_IMAGE_DIR}/ddr.hex" ]]

set +e
env RUN_DIR="${RUN_DIR}" \
    KERNEL="${KERNEL}" \
    LINUX_IMAGE_DIR="${LINUX_IMAGE_DIR}" \
    SKIP_LINUX_BUILD=1 REUSE_LINUX_IMAGE=1 \
    LINUX_PROFILE=generic \
    HOST_TIMEOUT="${HOST_TIMEOUT}" \
    RTL_CYCLE_LIMIT="${RTL_CYCLE_LIMIT}" \
    LINUX_TIMEOUT_NS="${LINUX_TIMEOUT_NS}" \
    LINUX_REQUIRE_PROGRESS=1 LINUX_REQUIRE_USERSPACE=0 \
    LINUX_PROGRESS_TRACE=1 LINUX_WAIT_TRACE=1 LINUX_WAIT_TRACE_LIMIT=128 \
    LINUX_TIMER_HEARTBEAT=1 \
    LINUX_CP0_TRACE_LIMIT="${LINUX_CP0_TRACE_LIMIT}" \
    LINUX_CP0_READ_TRACE_LIMIT="${LINUX_CP0_READ_TRACE_LIMIT}" \
    LINUX_EXCEPTION_TRACE=1 LINUX_EXCEPTION_TRACE_LIMIT=128 \
    LINUX_WB_TRACE=1 LINUX_WB_TRACE_LIMIT=256 \
    LINUX_PC_TRACE=1 LINUX_PC_TRACE_RETIRE_ONLY=1 LINUX_PC_TRACE_LIMIT=512 \
    LINUX_PC_TRACE_SYMBOL=kernel_init \
    LINUX_FOCUS_TRACE=1 LINUX_FOCUS_TRACE_TARGET_ONLY=0 \
    LINUX_FOCUS_TRACE_LIMIT=4096 \
    "${SCRIPT_DIR}/run_rtl_linux_progress_gate.sh" \
    >"${RUN_DIR}/progress_runner.log" 2>&1
progress_rc=$?
set -e

SIM_LOG="${RUN_DIR}/sim/sim.log"
if [[ ! -s "${SIM_LOG}" && -s "${RUN_DIR}/sim/sim_runtime.log" ]]; then
    SIM_LOG="${RUN_DIR}/sim/sim_runtime.log"
fi
[[ -s "${SIM_LOG}" ]]

python3 "${ROOT_DIR}/scripts/analyze_linux_timer_wait.py" \
    "${SIM_LOG}" \
    --report "${RUN_DIR}/timer_wait_analysis.md"

# Require a bounded simulator terminal record and enough architectural trace
# to identify the last active PC.  A failure to boot is an expected diagnostic
# result here, but a missing capture is an infrastructure failure.
grep -Eq 'LINUX_(SIMULATION_BOUND_REACHED|BOUNDED_END_STATE)' "${SIM_LOG}"
grep -Eq 'LINUX_PROGRESS_TRACE cycle=[1-9][0-9]* pc=' "${SIM_LOG}"
if grep -Eiq 'SIGABRT|SIGSEGV|assertion failed|VCS.*fatal|REGRESSION_TEST_FAILED' "${SIM_LOG}"; then
    echo "root-cause checkpoint: fatal simulator diagnostic found" >&2
    exit 1
fi

last_progress=$(rg 'LINUX_PROGRESS_TRACE cycle=[0-9]+ pc=' "${SIM_LOG}" | tail -1)
last_wait=$(rg 'LINUX_WAIT_TRACE ' "${SIM_LOG}" | tail -1 || true)
last_end=$(rg 'LINUX_BOUNDED_END_STATE ' "${SIM_LOG}" | tail -1 || true)
printf '%s\n' "${last_progress}" >"${RUN_DIR}/last_progress.txt"
printf '%s\n' "${last_wait}" >"${RUN_DIR}/last_wait.txt"
printf '%s\n' "${last_end}" >"${RUN_DIR}/last_end_state.txt"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux Root-Cause Checkpoint Gate

- Result: PASS (diagnostic capture; generic Linux remains open)
- Progress runner status: ${progress_rc}
- Kernel: ${KERNEL}
- Image directory: ${LINUX_IMAGE_DIR}
- RTL cycle bound: ${RTL_CYCLE_LIMIT}
- Simulation log: ${SIM_LOG}
- Last progress record: \`${RUN_DIR}/last_progress.txt\`
- Last WAIT record: \`${RUN_DIR}/last_wait.txt\`
- Last bounded state: \`${RUN_DIR}/last_end_state.txt\`
- Timer/WAIT analysis: \`${RUN_DIR}/timer_wait_analysis.md\`
- Contract: current-source bounded trace is complete enough to classify the
  first stuck window; this result is not a boot, userspace, or differential pass.
- Next owner: compare the Linux __udelay/clock-progress contract and its
  Count-read values against the matching QEMU workload; the WAIT wakeup path
  has not been reached in this bounded run.
EOF
echo "RTL Linux root-cause checkpoint gate: PASS (diagnostic capture)"
