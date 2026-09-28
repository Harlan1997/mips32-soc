#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-generic-init}
RUN_DIR=$(realpath -m "${RUN_DIR}")
KERNEL=${KERNEL:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts/vmlinux}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-/data/disk/tmp/mips32-soc/rtl-linux-freeze-20260920/artifacts}

mkdir -p "${RUN_DIR}"
set +e
env RUN_DIR="${RUN_DIR}" KERNEL="${KERNEL}" \
    LINUX_IMAGE_DIR="${LINUX_IMAGE_DIR}" SKIP_LINUX_BUILD=1 REUSE_LINUX_IMAGE=1 \
    LINUX_PROFILE=generic LINUX_REQUIRE_PROGRESS=1 LINUX_REQUIRE_USERSPACE=1 \
    "${SCRIPT_DIR}/run_rtl_linux_progress_gate.sh" \
    >"${RUN_DIR}/progress_runner.log" 2>&1
runner_rc=$?
set -e

SIM_LOG="${RUN_DIR}/sim/sim.log"
[[ -s "${SIM_LOG}" ]]
if [[ "${runner_rc}" -ne 0 ]]; then
    echo "RTL generic init gate: progress runner failed (status ${runner_rc})" >&2
    exit "${runner_rc}"
fi
for marker in \
    'Linux version ' \
    'ttyS0' \
    'Run /init as init process' \
    'MIPS32_SOC_LINUX_BOOT_SUCCESS'; do
    rg -q "${marker}" "${SIM_LOG}"
done
if rg -Eiq 'Kernel panic|Oops:|BUG:|REGRESSION_TEST_FAILED|SIGABRT|SIGSEGV' "${SIM_LOG}"; then
    echo "RTL generic init gate: fatal Linux/simulator diagnostic found" >&2
    exit 1
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux Generic Init Gate

- Result: PASS
- Kernel: ${KERNEL}
- Image directory: ${LINUX_IMAGE_DIR}
- Evidence: Linux version, ttyS0 console binding, /init execution, and the
  guest boot marker were observed in the current-source RTL simulation.
- Scope: kernel entry through `/init`; VM, GPIO, timer/sleep, fork/exec, and
  complete QEMU/RTL retire differential are separate gates.
EOF
echo "RTL Linux generic init gate: PASS"
