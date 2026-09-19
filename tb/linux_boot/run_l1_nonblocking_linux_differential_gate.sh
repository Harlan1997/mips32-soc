#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=$(realpath -m "${RUN_DIR:-${ROOT_DIR}/build/linux_boot/l1_nonblocking_differential}")
LINUX_BUILD_DIR=$(realpath -m "${LINUX_BUILD_DIR:-${RUN_DIR}/linux}")
IMAGE_DIR=$(realpath -m "${LINUX_IMAGE_DIR:-${RUN_DIR}/image}")
KERNEL_INPUT=${KERNEL:-}
LINUX_SOURCE_DIR=${LINUX_SOURCE_DIR:-${ROOT_DIR}/third_party/linux}
CROSS_COMPILE=${CROSS_COMPILE:-mips64-linux-gnu-}
DTC=${DTC:-}
LINUX_PROFILE=${LINUX_PROFILE:-rtl-minimal}
LINUX_CMDLINE=${LINUX_CMDLINE:-"console=null earlycon=uart8250,mmio32,0x40000000 lpj=624128 rdinit=/init loglevel=0 quiet"}
KERNEL_PHYSICAL_START=${KERNEL_PHYSICAL_START:-0x88800000}
RETIRE_COMPARE_RECORDS=${RETIRE_COMPARE_RECORDS:-300000}
RTL_CYCLE_LIMIT=${RTL_CYCLE_LIMIT:-1100000}
LINUX_TIMEOUT_NS=${LINUX_TIMEOUT_NS:-$((RTL_CYCLE_LIMIT * 10))}
HOST_TIMEOUT=${HOST_TIMEOUT:-600s}
LINUX_COMMON_VCS_EXTRA_ARGS=${LINUX_COMMON_VCS_EXTRA_ARGS:-${LINUX_VCS_EXTRA_ARGS:-}}
NONBLOCKING_DEFINES="+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_L1_NONBLOCKING_DDR_ENABLE=1"

if ! [[ "${RETIRE_COMPARE_RECORDS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "L1 Linux differential: RETIRE_COMPARE_RECORDS must be positive" >&2
    exit 2
fi
if ! [[ "${RTL_CYCLE_LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "L1 Linux differential: RTL_CYCLE_LIMIT must be positive" >&2
    exit 2
fi
if [[ " ${LINUX_COMMON_VCS_EXTRA_ARGS} " == *" +define+SOC_L1_NONBLOCKING_ENABLE=1 "* ||
      " ${LINUX_COMMON_VCS_EXTRA_ARGS} " == *" +define+SOC_CPU_NONBLOCKING_ENABLE=1 "* ]]; then
    echo "L1 Linux differential: common VCS arguments must not select nonblocking L1" >&2
    exit 2
fi

mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/trace_compare.log"

if [[ -n "${KERNEL_INPUT}" ]]; then
    test -s "${KERNEL_INPUT}"
    KERNEL_PATH=$(realpath "${KERNEL_INPUT}")
    printf 'Linux kernel build: SKIPPED\nKERNEL=%s\n' "${KERNEL_PATH}" \
        >"${RUN_DIR}/build.log"
else
    BUILD_DIR="${LINUX_BUILD_DIR}" JOBS="${JOBS:-1}" \
        KERNEL_PHYSICAL_START="${KERNEL_PHYSICAL_START}" \
        LINUX_PROFILE="${LINUX_PROFILE}" LINUX_CMDLINE="${LINUX_CMDLINE}" \
        LINUX_SOURCE_DIR="${LINUX_SOURCE_DIR}" \
        "${SCRIPT_DIR}/build_linux_boot.sh" >"${RUN_DIR}/build.log" 2>&1
    KERNEL_PATH="${LINUX_BUILD_DIR}/kernel/vmlinux"
fi
test -s "${KERNEL_PATH}"

if [[ -z "${DTC}" ]]; then
    DTC="$(dirname "${KERNEL_PATH}")/scripts/dtc/dtc"
fi
KERNEL="${KERNEL_PATH}" DTC="${DTC}" RUN_DIR="${IMAGE_DIR}" \
    "${SCRIPT_DIR}/build_rtl_linux_image.sh" >"${RUN_DIR}/image.log" 2>&1

DTB_PATH="$(dirname "${KERNEL_PATH}")/../mips32_soc_ref.dtb"
if [[ ! -s "${DTB_PATH}" ]]; then
    DTB_PATH="${LINUX_BUILD_DIR}/mips32_soc_ref.dtb"
fi
test -s "${DTB_PATH}"
for image_file in bootrom.hex ddr.hex; do
    test -s "${IMAGE_DIR}/${image_file}"
done

# This manifest is the contract boundary for both RTL runs. Absolute paths are
# intentional: sha256sum -c then verifies the exact files used by each child.
IMAGE_HASH_MANIFEST="${RUN_DIR}/shared_image.sha256"
sha256sum "${KERNEL_PATH}" "${DTB_PATH}" \
    "${IMAGE_DIR}/bootrom.hex" "${IMAGE_DIR}/ddr.hex" >"${IMAGE_HASH_MANIFEST}"
cat >"${RUN_DIR}/shared_image_manifest.txt" <<EOF
KERNEL=${KERNEL_PATH}
DTB=${DTB_PATH}
IMAGE_DIR=${IMAGE_DIR}
KERNEL_PHYSICAL_START=${KERNEL_PHYSICAL_START}
LINUX_PROFILE=${LINUX_PROFILE}
LINUX_CMDLINE=${LINUX_CMDLINE}
RETIRE_COMPARE_RECORDS=${RETIRE_COMPARE_RECORDS}
EOF

check_image() {
    sha256sum -c "${IMAGE_HASH_MANIFEST}" >/dev/null
}

run_rtl_mode() {
    local mode=$1
    local mode_defines=$2
    local mode_dir="${RUN_DIR}/${mode}"
    local trace_path="${mode_dir}/sim/rtl_retire.jsonl"
    mkdir -p "${mode_dir}"
    check_image
    env \
        RUN_DIR="${mode_dir}" \
        KERNEL="${KERNEL_PATH}" \
        SKIP_LINUX_BUILD=1 \
        LINUX_IMAGE_DIR="${IMAGE_DIR}" \
        REUSE_LINUX_IMAGE=1 \
        LINUX_PROFILE="${LINUX_PROFILE}" \
        LINUX_CMDLINE="${LINUX_CMDLINE}" \
        RTL_CYCLE_LIMIT="${RTL_CYCLE_LIMIT}" \
        LINUX_TIMEOUT_NS="${LINUX_TIMEOUT_NS}" \
        HOST_TIMEOUT="${HOST_TIMEOUT}" \
        SKIP_COVERAGE=1 \
        LINUX_PROGRESS_TRACE=0 \
        LINUX_REQUIRE_PROGRESS=0 \
        LINUX_REQUIRE_USERSPACE=0 \
        LINUX_RETIRE_TRACE=1 \
        LINUX_RETIRE_TRACE_MAX_RECORDS="${RETIRE_COMPARE_RECORDS}" \
        LINUX_RETIRE_TRACE_STOP_AT_MAX=1 \
        LINUX_VCS_EXTRA_ARGS="${LINUX_COMMON_VCS_EXTRA_ARGS} ${mode_defines}" \
        "${SCRIPT_DIR}/run_rtl_linux_progress_gate.sh" \
        >"${mode_dir}/gate.log" 2>&1
    check_image
    test -s "${trace_path}"
    local records
    records=$(wc -l <"${trace_path}")
    if (( records < RETIRE_COMPARE_RECORDS )); then
        echo "L1 Linux differential: ${mode} trace is short (${records}/${RETIRE_COMPARE_RECORDS})" >&2
        exit 1
    fi
}

run_rtl_mode blocking ""
run_rtl_mode nonblocking "${NONBLOCKING_DEFINES}"

blocking_trace="${RUN_DIR}/blocking/sim/rtl_retire.jsonl"
nonblocking_trace="${RUN_DIR}/nonblocking/sim/rtl_retire.jsonl"
python3 "${ROOT_DIR}/tb/isa_ref/trace_compare.py" \
    --stream --limit "${RETIRE_COMPARE_RECORDS}" --max-mismatches 5 \
    "${blocking_trace}" "${nonblocking_trace}" \
    >"${RUN_DIR}/trace_compare.log" 2>&1
expected_pass="TRACE_COMPARE_PASS records=${RETIRE_COMPARE_RECORDS} mode=stream-limit"
grep -qx "${expected_pass}" "${RUN_DIR}/trace_compare.log"
check_image

cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux L1 Nonblocking Differential

- Result: PASS
- Linux profile: ${LINUX_PROFILE}
- Kernel: ${KERNEL_PATH}
- Shared image manifest: shared_image_manifest.txt
- Shared image hashes: shared_image.sha256
- Blocking trace: ${blocking_trace}
- Nonblocking trace: ${nonblocking_trace}
- Compared records: ${RETIRE_COMPARE_RECORDS}
- Comparator: trace_compare.py streaming fixed-prefix mode
- Blocking VCS defines: baseline (SOC_L1_NONBLOCKING_ENABLE=0)
- Nonblocking VCS defines: ${LINUX_COMMON_VCS_EXTRA_ARGS} ${NONBLOCKING_DEFINES}
- Scope: same kernel, DTB, Boot ROM and DDR image are used for both RTL runs.
- Boundary: this is a bounded cache-path differential; Linux cache ABI beyond
  the prefix, full ISA/MMU/FPU/OS semantics, coherency and product signoff
  remain outside this gate.
EOF
echo "RTL Linux L1 nonblocking differential: PASS (${RETIRE_COMPARE_RECORDS} records)"
