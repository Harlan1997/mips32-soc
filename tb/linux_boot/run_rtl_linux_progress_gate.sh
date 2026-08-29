#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/rtl_progress_gate"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
HOST_TIMEOUT=${HOST_TIMEOUT:-180s}
RTL_CYCLE_LIMIT=${RTL_CYCLE_LIMIT:-1000000}
JOBS=${JOBS:-2}
KERNEL_PHYSICAL_START=${KERNEL_PHYSICAL_START:-0x88800000}
LINUX_DELAY_TRACE=${LINUX_DELAY_TRACE:-0}
LINUX_DELAY_TRACE_LIMIT=${LINUX_DELAY_TRACE_LIMIT:-256}
LINUX_DELAY_TRACE_START=${LINUX_DELAY_TRACE_START:-892434e0}
LINUX_DELAY_TRACE_END=${LINUX_DELAY_TRACE_END:-892434e4}
LINUX_DELAY_TRACE_CYCLE_START=${LINUX_DELAY_TRACE_CYCLE_START:-0}
LINUX_DELAY_TRACE_CYCLE_END=${LINUX_DELAY_TRACE_CYCLE_END:-0}
LINUX_GPR_TRACE=${LINUX_GPR_TRACE:-0}
LINUX_GPR_TRACE_LIMIT=${LINUX_GPR_TRACE_LIMIT:-256}
LINUX_GPR_TRACE_REG=${LINUX_GPR_TRACE_REG:-16}
LINUX_GPR_TRACE_CYCLE_START=${LINUX_GPR_TRACE_CYCLE_START:-0}
LINUX_GPR_TRACE_CYCLE_END=${LINUX_GPR_TRACE_CYCLE_END:-0}
LINUX_TARGET_DSIDE_TRACE=${LINUX_TARGET_DSIDE_TRACE:-0}
LINUX_TARGET_DSIDE_TRACE_LIMIT=${LINUX_TARGET_DSIDE_TRACE_LIMIT:-160}
LINUX_TARGET_TRACE_LINE=${LINUX_TARGET_TRACE_LINE:-0040133b}
LINUX_TARGET_TRACE_CYCLE_START=${LINUX_TARGET_TRACE_CYCLE_START:-0}
LINUX_TARGET_TRACE_CYCLE_END=${LINUX_TARGET_TRACE_CYCLE_END:-0}
LINUX_UART_TRACE=${LINUX_UART_TRACE:-0}
LINUX_UART_TRACE_LIMIT=${LINUX_UART_TRACE_LIMIT:-256}
LINUX_PANIC_TRACE=${LINUX_PANIC_TRACE:-0}
LINUX_PANIC_TRACE_LIMIT=${LINUX_PANIC_TRACE_LIMIT:-32}
LINUX_CACHE_OWNER_TRACE=${LINUX_CACHE_OWNER_TRACE:-0}
LINUX_CACHE_OWNER_TRACE_LIMIT=${LINUX_CACHE_OWNER_TRACE_LIMIT:-256}
LINUX_REFILL_TRACE=${LINUX_REFILL_TRACE:-1}
LINUX_PROGRESS_TRACE=${LINUX_PROGRESS_TRACE:-1}
LINUX_EXCEPTION_TRACE=${LINUX_EXCEPTION_TRACE:-1}
LINUX_EBASE_TRACE=${LINUX_EBASE_TRACE:-1}
LINUX_WB_TRACE=${LINUX_WB_TRACE:-1}
LINUX_TLB_TRACE=${LINUX_TLB_TRACE:-0}
LINUX_TLB_TRACE_LIMIT=${LINUX_TLB_TRACE_LIMIT:-256}
LINUX_VECTOR_TRACE=${LINUX_VECTOR_TRACE:-0}
LINUX_VECTOR_TRACE_LIMIT=${LINUX_VECTOR_TRACE_LIMIT:-1000}
LINUX_CACHEOP_TRACE_LIMIT=${LINUX_CACHEOP_TRACE_LIMIT:-0}
LINUX_CACHEOP_TRACE_LINE=${LINUX_CACHEOP_TRACE_LINE:-}
LINUX_CP0_TRACE_LIMIT=${LINUX_CP0_TRACE_LIMIT:-0}
LINUX_VECTOR_LINE_TRACE=${LINUX_VECTOR_LINE_TRACE:-0}
LINUX_VECTOR_LINE_TRACE_LIMIT=${LINUX_VECTOR_LINE_TRACE_LIMIT:-256}
LINUX_VECTOR_LINE=${LINUX_VECTOR_LINE:-470410}
SKIP_LINUX_BUILD=${SKIP_LINUX_BUILD:-0}
KERNEL_INPUT=${KERNEL:-}

mkdir -p "${RUN_DIR}"

# Build a self-contained relocated image.  Keeping the kernel, DTB, Boot ROM,
# DDR image and simulator in one run directory makes this probe reproducible
# and avoids accidentally reusing an image from a different address layout.
if [[ "${SKIP_LINUX_BUILD}" == "1" || -n "${KERNEL_INPUT}" ]]; then
    if [[ "${SKIP_LINUX_BUILD}" == "1" && -z "${KERNEL_INPUT}" ]]; then
        echo "SKIP_LINUX_BUILD=1 requires KERNEL=/path/to/vmlinux" >&2
        exit 1
    fi
    if [[ -z "${KERNEL_INPUT}" ]]; then
        echo "RTL Linux progress gate: no KERNEL supplied for build skip" >&2
        exit 1
    fi
    test -s "${KERNEL_INPUT}"
    KERNEL_PATH=$(realpath "${KERNEL_INPUT}")
    printf 'Linux kernel build: SKIPPED (reusing supplied KERNEL)\nKERNEL=%s\n' "${KERNEL_PATH}" >"${RUN_DIR}/build.log"
else
    BUILD_DIR="${RUN_DIR}" JOBS="${JOBS}" KERNEL_PHYSICAL_START="${KERNEL_PHYSICAL_START}" \
        "${SCRIPT_DIR}/build_linux_boot.sh" >"${RUN_DIR}/build.log" 2>&1
    KERNEL_PATH="${RUN_DIR}/kernel/vmlinux"
fi
KERNEL="${KERNEL_PATH}" \
    DTC="$(dirname "${KERNEL_PATH}")/scripts/dtc/dtc" \
    RUN_DIR="${RUN_DIR}/image" \
    "${SCRIPT_DIR}/build_rtl_linux_image.sh" >"${RUN_DIR}/image.log" 2>&1

if [[ ! -s "${RUN_DIR}/image/bootrom.hex" ||
      ! -s "${RUN_DIR}/image/ddr.hex" ]]; then
    echo "RTL Linux progress gate: image generation did not produce bootrom/ddr hex" >&2
    exit 1
fi

sim_dir="${RUN_DIR}/sim"
mkdir -p "${sim_dir}"
set +e
timeout "${HOST_TIMEOUT}" env \
    RUN_DIR="${sim_dir}" \
    FW_HEX="${RUN_DIR}/image/bootrom.hex" \
    SKIP_COVERAGE="${SKIP_COVERAGE:-0}" \
    VCS_EXTRA_ARGS='+define+SOC_LINUX_BOOT_ENABLE=1 +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1 +define+TB_LINUX_BOOT +define+TB_LINUX_BOOT_TRACE' \
    SIM_EXTRA_ARGS="+BOOT_ROM_HEX=${RUN_DIR}/image/bootrom.hex +DDR_HEX=${RUN_DIR}/image/ddr.hex +LINUX_TRACE_LIMIT=${RTL_CYCLE_LIMIT} +LINUX_REFILL_TRACE=${LINUX_REFILL_TRACE} +LINUX_PROGRESS_TRACE=${LINUX_PROGRESS_TRACE} +LINUX_EXCEPTION_TRACE=${LINUX_EXCEPTION_TRACE} +LINUX_EBASE_TRACE=${LINUX_EBASE_TRACE} +LINUX_WB_TRACE=${LINUX_WB_TRACE} +LINUX_TLB_TRACE=${LINUX_TLB_TRACE} +LINUX_TLB_TRACE_LIMIT=${LINUX_TLB_TRACE_LIMIT} +LINUX_VECTOR_TRACE=${LINUX_VECTOR_TRACE} +LINUX_VECTOR_TRACE_LIMIT=${LINUX_VECTOR_TRACE_LIMIT} +LINUX_CACHEOP_TRACE_LIMIT=${LINUX_CACHEOP_TRACE_LIMIT} +LINUX_CACHEOP_TRACE_LINE=${LINUX_CACHEOP_TRACE_LINE} +LINUX_CP0_TRACE_LIMIT=${LINUX_CP0_TRACE_LIMIT} +LINUX_VECTOR_LINE_TRACE=${LINUX_VECTOR_LINE_TRACE} +LINUX_VECTOR_LINE_TRACE_LIMIT=${LINUX_VECTOR_LINE_TRACE_LIMIT} +LINUX_VECTOR_LINE=${LINUX_VECTOR_LINE} +LINUX_DELAY_TRACE=${LINUX_DELAY_TRACE} +LINUX_DELAY_TRACE_LIMIT=${LINUX_DELAY_TRACE_LIMIT} +LINUX_DELAY_TRACE_START=${LINUX_DELAY_TRACE_START} +LINUX_DELAY_TRACE_END=${LINUX_DELAY_TRACE_END} +LINUX_DELAY_TRACE_CYCLE_START=${LINUX_DELAY_TRACE_CYCLE_START} +LINUX_DELAY_TRACE_CYCLE_END=${LINUX_DELAY_TRACE_CYCLE_END} +LINUX_TARGET_DSIDE_TRACE=${LINUX_TARGET_DSIDE_TRACE} +LINUX_TARGET_DSIDE_TRACE_LIMIT=${LINUX_TARGET_DSIDE_TRACE_LIMIT} +LINUX_TARGET_TRACE_LINE=${LINUX_TARGET_TRACE_LINE} +LINUX_TARGET_TRACE_CYCLE_START=${LINUX_TARGET_TRACE_CYCLE_START} +LINUX_TARGET_TRACE_CYCLE_END=${LINUX_TARGET_TRACE_CYCLE_END} +LINUX_UART_TRACE=${LINUX_UART_TRACE} +LINUX_UART_TRACE_LIMIT=${LINUX_UART_TRACE_LIMIT} +LINUX_PANIC_TRACE=${LINUX_PANIC_TRACE} +LINUX_PANIC_TRACE_LIMIT=${LINUX_PANIC_TRACE_LIMIT}" \
    LINUX_EXTRA_SIM_ARGS="+LINUX_GPR_TRACE=${LINUX_GPR_TRACE} +LINUX_GPR_TRACE_LIMIT=${LINUX_GPR_TRACE_LIMIT} +LINUX_GPR_TRACE_REG=${LINUX_GPR_TRACE_REG} +LINUX_GPR_TRACE_CYCLE_START=${LINUX_GPR_TRACE_CYCLE_START} +LINUX_GPR_TRACE_CYCLE_END=${LINUX_GPR_TRACE_CYCLE_END} +LINUX_CACHE_OWNER_TRACE=${LINUX_CACHE_OWNER_TRACE} +LINUX_CACHE_OWNER_TRACE_LIMIT=${LINUX_CACHE_OWNER_TRACE_LIMIT}" \
    "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/sim.log" 2>&1
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
    echo "RTL Linux progress gate: simulator command failed or timed out (status ${status})" >&2
    exit "${status}"
fi

test -s "${sim_dir}/sim.log" || {
    echo "RTL Linux progress gate: simulator log is missing" >&2
    exit 1
}

# A bounded probe is useful only when it demonstrates post-boot instruction
# progress.  It is deliberately not a boot gate: userspace and its success
# marker are checked by the future RTL Linux boot gate.
if ! rg -q 'LINUX_PROGRESS_TRACE cycle=[1-9][0-9]* pc=(?!bfc00000)' \
        --pcre2 "${sim_dir}/sim.log"; then
    echo "RTL Linux progress gate: no post-reset CPU progress observed (status ${status})" >&2
    exit 1
fi
if rg -q 'REGRESSION_TEST_FAILED|Comprehensive SoC Test Failed|tb_mips_soc: ERROR' \
        "${sim_dir}/sim.log"; then
    echo "RTL Linux progress gate: simulator reported a regression failure" >&2
    exit 1
fi

marker_count=$(rg -c 'MIPS32_SOC_LINUX_BOOT_SUCCESS' "${sim_dir}/sim.log" || echo 0)
cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux Progress Gate

- Result: PASS (bounded post-reset progress probe)
- Host timeout: ${HOST_TIMEOUT}
- RTL cycle limit: ${RTL_CYCLE_LIMIT}
- Delay trace: ${LINUX_DELAY_TRACE} (limit=${LINUX_DELAY_TRACE_LIMIT}, window=${LINUX_DELAY_TRACE_START}..${LINUX_DELAY_TRACE_END})
- UART trace: ${LINUX_UART_TRACE} (limit=${LINUX_UART_TRACE_LIMIT})
- Panic trace: ${LINUX_PANIC_TRACE} (limit=${LINUX_PANIC_TRACE_LIMIT})
- GPR trace: ${LINUX_GPR_TRACE} (reg=${LINUX_GPR_TRACE_REG}, limit=${LINUX_GPR_TRACE_LIMIT}, cycles=${LINUX_GPR_TRACE_CYCLE_START}..${LINUX_GPR_TRACE_CYCLE_END})
- Cache owner trace: ${LINUX_CACHE_OWNER_TRACE} (limit=${LINUX_CACHE_OWNER_TRACE_LIMIT}, line=${LINUX_TARGET_TRACE_LINE})
- Refill/progress/exception/EBase trace: ${LINUX_REFILL_TRACE}/${LINUX_PROGRESS_TRACE}/${LINUX_EXCEPTION_TRACE}/${LINUX_EBASE_TRACE}
- WB trace: ${LINUX_WB_TRACE}
- Image manifest: ${RUN_DIR}/image/image_manifest.txt
- Simulator log: ${sim_dir}/sim.log
- Linux userspace success markers observed: ${marker_count}
- Scope: relocated Linux image construction, Boot ROM/DDR preload, RTL
  compilation/elaboration and bounded post-reset CPU progress.
- Boundary: this is not RTL Linux userspace boot and not RTL/QEMU Linux
  differential signoff; the userspace marker is intentionally reported but
  is not required by this progress gate.
EOF

echo "RTL Linux progress gate: PASS (userspace marker count=${marker_count}, simulator status=${status})"
