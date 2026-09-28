#!/usr/bin/env bash
set -euo pipefail

# Full closure is deliberately a separate entry point from the historical
# bounded differential gate.  It has one successful terminal condition: the
# complete Linux userspace marker reaches both UART producers.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=$(realpath -m "${RUN_DIR:-/data/disk/tmp/mips32-soc/full-qemu-closure-$(date +%Y%m%d-%H%M%S)}")
KERNEL=${KERNEL:-}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-}
REUSE_LINUX_IMAGE=${REUSE_LINUX_IMAGE:-0}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}
QEMU_BIN=${QEMU_BIN:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel}
QEMU_SRC=${QEMU_SRC:-/data/disk/tmp/mips32-soc/qemu-9.2.0}
QEMU_BUILD=${QEMU_BUILD:-${QEMU_SRC}/build-mipsel-softmmu}
QEMU_MEMORY=${QEMU_MEMORY:-128M}
QEMU_APPEND=${QEMU_APPEND:-console=ttyS0,115200 earlycon=uart8250,mmio32,0x40000000 lpj=624128 rdinit=/init}
HOST_TIMEOUT=${HOST_TIMEOUT:-1h}
QEMU_MARKER_WATCHDOG_SECONDS=${QEMU_MARKER_WATCHDOG_SECONDS:-3600}
RTL_WATCHDOG_CYCLES=${RTL_WATCHDOG_CYCLES:-1000000000}
TERMINAL_MARKER=MIPS32_SOC_LINUX_TERMINAL

[[ -n "${KERNEL}" && -s "${KERNEL}" ]] || {
    echo "full QEMU closure: KERNEL=/path/to/marker-bearing/vmlinux is required" >&2
    exit 2
}
[[ -x "${QEMU_BIN}" ]] || {
    echo "full QEMU closure: QEMU_BIN is not executable: ${QEMU_BIN}" >&2
    exit 2
}
[[ "${LINUX_RNG_SEED}" =~ ^[0-9a-fA-F]+$ && $(( ${#LINUX_RNG_SEED} % 2 )) -eq 0 ]] || {
    echo "full QEMU closure: LINUX_RNG_SEED must be even-length hexadecimal" >&2
    exit 2
}
KERNEL=$(realpath "${KERNEL}")
mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/rtl_gate.log" "${RUN_DIR}/qemu_gate.log"

rtl_env=(
    SKIP_COVERAGE=1
    KERNEL="${KERNEL}"
    SKIP_LINUX_BUILD=1
    LINUX_IMAGE_DIR="${LINUX_IMAGE_DIR}"
    REUSE_LINUX_IMAGE="${REUSE_LINUX_IMAGE}"
    LINUX_RNG_SEED="${LINUX_RNG_SEED}"
    HOST_TIMEOUT="${HOST_TIMEOUT}"
    RTL_CYCLE_LIMIT="${RTL_WATCHDOG_CYCLES}"
    LINUX_TIMEOUT_CYCLES="${RTL_WATCHDOG_CYCLES}"
    LINUX_REQUIRE_PROGRESS=1
    LINUX_REQUIRE_USERSPACE=1
    LINUX_TERMINAL_STOP=1
    LINUX_TRACE_LIMIT=0
    LINUX_RETIRE_TRACE_MAX_RECORDS=0
    LINUX_RETIRE_TRACE_STOP_AT_MAX=0
)
run_rtl_stage() {
    local stage_dir=$1
    local trace_enabled=$2
    local stage_log=$3
    local stage_env=("${rtl_env[@]}" RUN_DIR="${stage_dir}")
    if [[ "${trace_enabled}" == "1" ]]; then
        stage_env+=(LINUX_RETIRE_TRACE=1)
    else
        stage_env+=(LINUX_RETIRE_TRACE=0)
    fi
    echo "full QEMU closure: running RTL terminal preflight=${trace_enabled}" >&2
    set +e
    env "${stage_env[@]}" bash "${ROOT_DIR}/tb/linux_boot/run_rtl_linux_progress_gate.sh" \
        >"${stage_log}" 2>&1
    local stage_status=$?
    set -e
    if [[ ${stage_status} -ne 0 ]]; then
        tail -100 "${stage_log}" >&2 || true
        echo "full QEMU closure: RTL producer failed (${stage_status})" >&2
        exit "${stage_status}"
    fi
    grep -q 'PASS (terminal-marker full workload)' "${stage_dir}/completion_report.md"
}

# First prove reachability without materializing a multi-gigabyte retire trace.
# Only a workload that actually reaches the terminal marker is traced in full.
run_rtl_stage "${RUN_DIR}/rtl_preflight" 0 "${RUN_DIR}/rtl_preflight_gate.log"
run_rtl_stage "${RUN_DIR}/rtl" 1 "${RUN_DIR}/rtl_gate.log"
rtl_trace="${RUN_DIR}/rtl/sim/rtl_retire.jsonl"
rtl_uart="${RUN_DIR}/rtl/sim/uart.transcript"
[[ -s "${rtl_trace}" && -s "${rtl_uart}" ]]
rtl_records=$(wc -l <"${rtl_trace}")
rtl_terminal_count=$(rg -o "${TERMINAL_MARKER}" "${rtl_uart}" | wc -l | tr -d ' ')
[[ "${rtl_terminal_count}" == "1" ]]

image_dir=${LINUX_IMAGE_DIR:-${RUN_DIR}/rtl/image}
image_dir=$(realpath -m "${image_dir}")
identity_args=(--image-dir "${image_dir}" --kernel "${KERNEL}")
python3 "${ROOT_DIR}/scripts/validate_linux_image_identity.py" \
    "${identity_args[@]}" >"${RUN_DIR}/image_identity.log"
DTB=$(sed -n 's/.* dtb=\([^ ]*\).*/\1/p' "${RUN_DIR}/image_identity.log")
[[ -s "${DTB}" ]]

echo "full QEMU closure: running unbounded QEMU producer through terminal marker" >&2
env RUN_DIR="${RUN_DIR}/qemu" \
    QEMU_BIN="${QEMU_BIN}" QEMU_SRC="${QEMU_SRC}" QEMU_BUILD="${QEMU_BUILD}" \
    QEMU_KERNEL="${KERNEL}" QEMU_DTB="${DTB}" QEMU_MEMORY="${QEMU_MEMORY}" \
    QEMU_APPEND="${QEMU_APPEND}" QEMU_MACHINE_PROPERTIES="rtl-cp0-identity=on,linux-guest=on" \
    QEMU_LINUX_RNG_SEED="${LINUX_RNG_SEED}" QEMU_ACCEL=tcg,thread=single \
    QEMU_STOP_ON_TERMINAL=1 QEMU_TERMINAL_MARKER="${TERMINAL_MARKER}" \
    QEMU_MARKER_WATCHDOG_SECONDS="${QEMU_MARKER_WATCHDOG_SECONDS}" \
    QEMU_TERMINAL_DRAIN_SECONDS=1 QEMU_UNBOUNDED_CAPTURE=1 \
    MAX_QEMU_EVENTS=0 MAX_QEMU_STATES=0 MAX_QEMU_CAPTURE_BYTES=0 \
    REQUIRE_SMOKE_OUTPUT=0 RTL_TRACE="${rtl_trace}" \
    TRACE_COMPARE_ALLOW_GOLDEN_PREFIX=0 TRACE_COMPARE_GOLDEN_TO_RTL=0 \
    TRACE_COMPARE_GOLDEN_LIMIT= \
    TRACE_COMPARE_ALIGN_FIRST_PC="$(readelf -h "${KERNEL}" | sed -n 's/^[[:space:]]*Entry point address:[[:space:]]*0x//p')" \
    TRACE_COMPARE_STREAM=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

qemu_trace="${RUN_DIR}/qemu/qemu_retire.jsonl"
qemu_status="${RUN_DIR}/qemu/qemu_capture_status.txt"
[[ -s "${qemu_trace}" && -s "${qemu_status}" ]]
grep -q '^terminal_marker=flushed ' "${qemu_status}"
grep -q '^TRACE_COMPARE_PASS ' "${RUN_DIR}/qemu/trace_compare.log"
qemu_records=$(wc -l <"${qemu_trace}")
compared_records=$(sed -n 's/^TRACE_COMPARE_PASS records=\([0-9][0-9]*\).*/\1/p' \
    "${RUN_DIR}/qemu/trace_compare.log")
[[ -n "${compared_records}" && "${compared_records}" -gt 0 ]]

validator="${ROOT_DIR}/scripts/validate_linux_differential.py"
source_identity="${RUN_DIR}/source_identity.txt"
git -C "${ROOT_DIR}" status --short --untracked-files=all | sha256sum | awk '{print $1}' >"${source_identity}"
seed_id=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
python3 "${validator}" create --output "${RUN_DIR}/differential_manifest.json" \
    --file kernel_sha256="${KERNEL}" \
    --file dtb_sha256="${DTB}" \
    --file image_manifest_sha256="${image_dir}/image_manifest.txt" \
    --file bootrom_sha256="${image_dir}/bootrom.hex" \
    --file ddr_image_sha256="${image_dir}/ddr.hex" \
    --set root_image_sha256="not-applicable:no-independent-rootfs" \
    --file qemu_sha256="${QEMU_BIN}" \
    --file qemu_plugin_sha256="${RUN_DIR}/qemu/libqemu_retire.so" \
    --file rtl_simulator_sha256="${RUN_DIR}/rtl/sim/simv" \
    --file rtl_source_identity_sha256="${source_identity}" \
    --set git_commit="$(git -C "${ROOT_DIR}" rev-parse HEAD)" \
    --set git_dirty_status_hash="$(cat "${source_identity}")" \
    --set entropy_mode=deterministic \
    --set entropy_seed_id="${seed_id}" \
    --set entropy_seed_width="$(( ${#LINUX_RNG_SEED} * 4 ))" \
    --set entropy_contract_version=uhi-rng-v1 \
    --set qemu_machine=mips32-soc-ref \
    --set qemu_memory="${QEMU_MEMORY}" \
    --set cp0_identity="rtl-cp0-identity=on,linux-guest=on" \
    --set rtl_image_dir="${image_dir}" \
    --set rtl_defines="SOC_LINUX_BOOT_ENABLE=1,SOC_MMU_ENABLE=1" \
    --set linux_cmdline="${QEMU_APPEND}" \
    --set retire_bound="${RTL_WATCHDOG_CYCLES}" \
    --set cycle_bound="${RTL_WATCHDOG_CYCLES}" \
    --set timeout_bound="${HOST_TIMEOUT}" \
    --set terminal_condition=terminal_marker \
    --set terminal_marker="${TERMINAL_MARKER}" \
    --set rtl_records="${rtl_records}" \
    --set qemu_records="${qemu_records}" \
    --set compared_records="${compared_records}" \
    --set qemu_terminal_status="$(grep '^terminal_marker=' "${qemu_status}")"
python3 "${validator}" validate-manifest "${RUN_DIR}/differential_manifest.json" \
    >"${RUN_DIR}/manifest_validate.log"
python3 "${validator}" validate-trace "${rtl_trace}" \
    --max-records "${rtl_records}" --exact-records "${rtl_records}" \
    >"${RUN_DIR}/rtl_trace_validate.log"
python3 "${validator}" validate-trace "${qemu_trace}" \
    --max-records "${qemu_records}" --exact-records "${qemu_records}" \
    >"${RUN_DIR}/qemu_trace_validate.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# Full QEMU Linux RTL Closure

- Result: PASS (terminal-marker full workload)
- Kernel/DTB/image: ${KERNEL} / ${DTB} / ${image_dir}
- Deterministic entropy seed id: ${seed_id}
- RTL trace records: ${rtl_records}
- QEMU trace records: ${qemu_records}
- Strict compared records: ${compared_records}
- RTL terminal markers: ${rtl_terminal_count}
- QEMU terminal status: $(grep '^terminal_marker=' "${qemu_status}")
- Differential manifest: ${RUN_DIR}/differential_manifest.json
- Producer evidence: rtl_gate.log, qemu_gate.log, qemu/trace_compare.log
- Watchdogs: RTL cycles=${RTL_WATCHDOG_CYCLES}, host=${HOST_TIMEOUT}, QEMU marker=${QEMU_MARKER_WATCHDOG_SECONDS}s
- Boundary: the declared generic Linux image through its terminal userspace
  marker; this is not unrestricted Linux or full ISA/product signoff.
EOF
echo "full QEMU closure: PASS (compared records=${compared_records})"
