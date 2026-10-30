#!/usr/bin/env bash
set -euo pipefail

# Full closure is deliberately a separate entry point from the historical
# bounded differential gate.  It has one successful terminal condition: the
# complete Linux userspace marker reaches both UART producers.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
# Keep the aggregate RTL + QEMU + streaming-comparator scope below this host's
# physical RAM while leaving headroom for the OS and unrelated processes.
QEMU_CLOSURE_MEMORY_MAX=${QEMU_CLOSURE_MEMORY_MAX:-2G}
QEMU_CLOSURE_SWAP_MAX=${QEMU_CLOSURE_SWAP_MAX:-512M}
QEMU_CLOSURE_MIN_FREE_KIB=${QEMU_CLOSURE_MIN_FREE_KIB:-2097152}
if [[ "${QEMU_FULL_CLOSURE_CGROUP_ACTIVE:-0}" != "1" ]]; then
    if ! systemctl --user show-environment >/dev/null 2>&1; then
        echo "full QEMU closure: user systemd cgroup unavailable; refusing an unbounded RTL/QEMU run" >&2
        exit 69
    fi
    script_path=$(realpath "${BASH_SOURCE[0]}")
    exec systemd-run --user --scope --quiet \
        --unit="qemu-full-closure-${BASHPID}" \
        --property="MemoryMax=${QEMU_CLOSURE_MEMORY_MAX}" \
        --property="MemorySwapMax=${QEMU_CLOSURE_SWAP_MAX}" \
        env QEMU_FULL_CLOSURE_CGROUP_ACTIVE=1 bash "${script_path}" "$@"
fi
RUN_DIR=$(realpath -m "${RUN_DIR:-/data/disk/tmp/mips32-soc/full-qemu-closure-$(date +%Y%m%d-%H%M%S)}")
TMPDIR=$(realpath -m "${TMPDIR:-/data/disk/tmp/mips32-soc/tmp}")
[[ "${QEMU_CLOSURE_MIN_FREE_KIB}" =~ ^[1-9][0-9]*$ ]] || {
    echo "full QEMU closure: QEMU_CLOSURE_MIN_FREE_KIB must be a positive integer" >&2
    exit 2
}
free_kib_for_path() {
    local path=$1
    while [[ ! -e "${path}" ]]; do
        local parent
        parent=$(dirname "${path}")
        [[ "${parent}" != "${path}" ]] || break
        path=${parent}
    done
    df -Pk "${path}" | awk 'NR == 2 { print $4 }'
}
run_free_kib=$(free_kib_for_path "${RUN_DIR}")
tmp_free_kib=$(free_kib_for_path "${TMPDIR}")
if ! [[ "${run_free_kib}" =~ ^[0-9]+$ &&
        "${tmp_free_kib}" =~ ^[0-9]+$ ]] ||
   (( run_free_kib < QEMU_CLOSURE_MIN_FREE_KIB ||
      tmp_free_kib < QEMU_CLOSURE_MIN_FREE_KIB )); then
    echo "full QEMU closure: insufficient free space; run filesystem=${run_free_kib:-unknown} KiB, TMPDIR filesystem=${tmp_free_kib:-unknown} KiB, required=${QEMU_CLOSURE_MIN_FREE_KIB} KiB" >&2
    exit 69
fi
KERNEL=${KERNEL:-}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-}
REUSE_LINUX_IMAGE=${REUSE_LINUX_IMAGE:-1}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}
QEMU_BIN=${QEMU_BIN:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel}
QEMU_SRC=${QEMU_SRC:-/data/disk/tmp/mips32-soc/qemu-9.2.0}
QEMU_BUILD=${QEMU_BUILD:-${QEMU_SRC}/build-mipsel-softmmu}
QEMU_MEMORY=${QEMU_MEMORY:-128M}
QEMU_APPEND=${QEMU_APPEND:-console=ttyS0,115200 earlycon=uart8250,mmio32,0x40000000 lpj=624128 rdinit=/init}
# tb_mips_soc pulls up the otherwise-undriven GPIO input bus.
QEMU_MACHINE_PROPERTIES=${QEMU_MACHINE_PROPERTIES:-rtl-cp0-identity=on,linux-guest=on,cp0-retire-clock=on,gpio-input=4294967295,uart-modem-inputs=8}
HOST_TIMEOUT=${HOST_TIMEOUT:-6h}
QEMU_MARKER_WATCHDOG_SECONDS=${QEMU_MARKER_WATCHDOG_SECONDS:-21600}
QEMU_TERMINAL_DRAIN_SECONDS=${QEMU_TERMINAL_DRAIN_SECONDS:-1}
RTL_WATCHDOG_CYCLES=${RTL_WATCHDOG_CYCLES:-1000000000}
LINUX_VCS_EXTRA_ARGS=${LINUX_VCS_EXTRA_ARGS:-}
CPU_CYCLE_SCHEDULE_INTERVAL=${CPU_CYCLE_SCHEDULE_INTERVAL:-8}
REUSE_IRQ_SCHEDULE=${REUSE_IRQ_SCHEDULE:-}
REUSE_CP0_COUNT_SCHEDULE=${REUSE_CP0_COUNT_SCHEDULE:-}
REUSE_CP0_RANDOM_SCHEDULE=${REUSE_CP0_RANDOM_SCHEDULE:-}
REUSE_CPU_CYCLE_SCHEDULE=${REUSE_CPU_CYCLE_SCHEDULE:-}
REUSE_UART_APB_SCHEDULE=${REUSE_UART_APB_SCHEDULE:-}
TERMINAL_MARKER=MIPS32_SOC_LINUX_TERMINAL
IRQ_SCHEDULE=${RUN_DIR}/rtl_irq_schedule.txt
CP0_COUNT_SCHEDULE=${RUN_DIR}/rtl_cp0_count_schedule.txt
CP0_RANDOM_SCHEDULE=${RUN_DIR}/rtl_cp0_random_schedule.txt
CPU_CYCLE_SCHEDULE=${RUN_DIR}/rtl_cpu_cycle_schedule.txt
UART_APB_SCHEDULE=${RUN_DIR}/rtl_uart_apb_schedule.txt

# Full Linux closure must use the architectural cycle-based CP0 Count.  The
# retire-count differential mode intentionally freezes Count while the CPU is
# in WAIT, so Compare can never wake the idle kernel and the terminal marker is
# unreachable.  Keep that opt-in mode limited to the bounded differential gate.
case " ${LINUX_VCS_EXTRA_ARGS} " in
    *" +define+SOC_CP0_RETIRE_COUNT_ENABLE=1 "*)
        echo "full QEMU closure: SOC_CP0_RETIRE_COUNT_ENABLE=1 is incompatible with Linux WAIT/timer progress; remove it from LINUX_VCS_EXTRA_ARGS" >&2
        exit 2
        ;;
esac

[[ -n "${KERNEL}" && -s "${KERNEL}" ]] || {
    echo "full QEMU closure: KERNEL=/path/to/marker-bearing/vmlinux is required" >&2
    exit 2
}
[[ "${LINUX_RNG_SEED}" =~ ^[0-9a-fA-F]+$ && $(( ${#LINUX_RNG_SEED} % 2 )) -eq 0 ]] || {
    echo "full QEMU closure: LINUX_RNG_SEED must be even-length hexadecimal" >&2
    exit 2
}
[[ "${CPU_CYCLE_SCHEDULE_INTERVAL}" =~ ^[1-9][0-9]*$ ]] || {
    echo "full QEMU closure: CPU_CYCLE_SCHEDULE_INTERVAL must be a positive integer" >&2
    exit 2
}
[[ "${QEMU_TERMINAL_DRAIN_SECONDS}" =~ ^[0-9]+$ ]] || {
    echo "full QEMU closure: QEMU_TERMINAL_DRAIN_SECONDS must be a non-negative integer" >&2
    exit 2
}
if [[ "${QEMU_MACHINE_PROPERTIES}" == *cp0-count-schedule=* ]]; then
    echo "full QEMU closure: CP0 Count schedule is managed by this gate" >&2
    exit 2
fi
if [[ "${QEMU_MACHINE_PROPERTIES}" == *cp0-random-schedule=* ]]; then
    echo "full QEMU closure: CP0 Random schedule is managed by this gate" >&2
    exit 2
fi
KERNEL=$(realpath "${KERNEL}")
mkdir -p "${TMPDIR}"
export TMPDIR
mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/rtl_gate.log" "${RUN_DIR}/qemu_gate.log"
rm -f "${RUN_DIR}/rtl_irq_schedule_capture.log" "${RUN_DIR}/rtl_cp0_count_schedule_capture.log"
rm -f "${RUN_DIR}/rtl_cpu_cycle_schedule_capture.log"
rm -f "${RUN_DIR}/rtl_uart_apb_schedule_capture.log"
rm -f "${RUN_DIR}/rtl_cp0_random_schedule_capture.log"
expected_qemu_bin=$(realpath -m "${QEMU_BUILD}/qemu-system-mipsel")
actual_qemu_bin=$(realpath -m "${QEMU_BIN}")
[[ "${actual_qemu_bin}" == "${expected_qemu_bin}" ]] || {
    echo "full QEMU closure: QEMU_BIN must be QEMU_BUILD/qemu-system-mipsel so the current model can be rebuilt" >&2
    exit 2
}
if ! env QEMU_SRC="${QEMU_SRC}" QEMU_BUILD="${QEMU_BUILD}" \
    bash "${ROOT_DIR}/scripts/qemu/build_mips32_soc_ref.sh" \
    >"${RUN_DIR}/qemu_model_build.log" 2>&1; then
    tail -100 "${RUN_DIR}/qemu_model_build.log" >&2 || true
    echo "full QEMU closure: custom QEMU model build failed" >&2
    exit 1
fi
[[ -x "${QEMU_BIN}" ]] || {
    echo "full QEMU closure: QEMU model build did not produce ${QEMU_BIN}" >&2
    exit 1
}
if [[ -n "${REUSE_IRQ_SCHEDULE}" ]]; then
    REUSE_IRQ_SCHEDULE=$(realpath "${REUSE_IRQ_SCHEDULE}")
    [[ -s "${REUSE_IRQ_SCHEDULE}" ]] || {
        echo "full QEMU closure: REUSE_IRQ_SCHEDULE is empty or missing" >&2
        exit 2
    }
    [[ "${REUSE_IRQ_SCHEDULE}" != "${IRQ_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused schedule must be outside RUN_DIR" >&2
        exit 2
    }
    cp -- "${REUSE_IRQ_SCHEDULE}" "${IRQ_SCHEDULE}"
else
    rm -f "${IRQ_SCHEDULE}"
fi
if [[ -n "${REUSE_CP0_COUNT_SCHEDULE}" ]]; then
    REUSE_CP0_COUNT_SCHEDULE=$(realpath "${REUSE_CP0_COUNT_SCHEDULE}")
    [[ -s "${REUSE_CP0_COUNT_SCHEDULE}" ]] || {
        echo "full QEMU closure: REUSE_CP0_COUNT_SCHEDULE is empty or missing" >&2
        exit 2
    }
    [[ "${REUSE_CP0_COUNT_SCHEDULE}" != "${CP0_COUNT_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused Count schedule must be outside RUN_DIR" >&2
        exit 2
    }
    cp -- "${REUSE_CP0_COUNT_SCHEDULE}" "${CP0_COUNT_SCHEDULE}"
else
    rm -f "${CP0_COUNT_SCHEDULE}"
fi
if [[ -n "${REUSE_CP0_RANDOM_SCHEDULE}" ]]; then
    REUSE_CP0_RANDOM_SCHEDULE=$(realpath "${REUSE_CP0_RANDOM_SCHEDULE}")
    [[ -s "${REUSE_CP0_RANDOM_SCHEDULE}" ]] || {
        echo "full QEMU closure: REUSE_CP0_RANDOM_SCHEDULE is empty or missing" >&2
        exit 2
    }
    [[ "${REUSE_CP0_RANDOM_SCHEDULE}" != "${CP0_RANDOM_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused Random schedule must be outside RUN_DIR" >&2
        exit 2
    }
    cp -- "${REUSE_CP0_RANDOM_SCHEDULE}" "${CP0_RANDOM_SCHEDULE}"
else
    rm -f "${CP0_RANDOM_SCHEDULE}"
fi
if [[ -n "${REUSE_CPU_CYCLE_SCHEDULE}" ]]; then
    REUSE_CPU_CYCLE_SCHEDULE=$(realpath "${REUSE_CPU_CYCLE_SCHEDULE}")
    [[ -s "${REUSE_CPU_CYCLE_SCHEDULE}" ]] || {
        echo "full QEMU closure: REUSE_CPU_CYCLE_SCHEDULE is empty or missing" >&2
        exit 2
    }
    [[ "${REUSE_CPU_CYCLE_SCHEDULE}" != "${CPU_CYCLE_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused cycle schedule must be outside RUN_DIR" >&2
        exit 2
    }
    cp -- "${REUSE_CPU_CYCLE_SCHEDULE}" "${CPU_CYCLE_SCHEDULE}"
else
    rm -f "${CPU_CYCLE_SCHEDULE}"
fi
if [[ -n "${REUSE_UART_APB_SCHEDULE}" ]]; then
    REUSE_UART_APB_SCHEDULE=$(realpath "${REUSE_UART_APB_SCHEDULE}")
    [[ -s "${REUSE_UART_APB_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused UART APB schedule is empty or missing" >&2
        exit 2
    }
    [[ "${REUSE_UART_APB_SCHEDULE}" != "${UART_APB_SCHEDULE}" ]] || {
        echo "full QEMU closure: reused UART APB schedule must be outside RUN_DIR" >&2
        exit 2
    }
    cp -- "${REUSE_UART_APB_SCHEDULE}" "${UART_APB_SCHEDULE}"
else
    rm -f "${UART_APB_SCHEDULE}"
fi

# The complete workload is too large for JSONL files on the available disk.
# These FIFOs carry every producer record directly into the bounded-memory
# converter/comparator; only compact logs and manifests remain on disk.
stream_dir="${RUN_DIR}/streams"
mkdir -p "${stream_dir}"
for stream in rtl_retire qemu_events qemu_states qemu_retire; do
    rm -f "${stream_dir}/${stream}"
    mkfifo "${stream_dir}/${stream}"
done

image_dir=${LINUX_IMAGE_DIR:-${RUN_DIR}/rtl/image}
image_dir=$(realpath -m "${image_dir}")
identity_args=(--image-dir "${image_dir}" --kernel "${KERNEL}")
python3 "${ROOT_DIR}/scripts/validate_linux_image_identity.py" \
    "${identity_args[@]}" >"${RUN_DIR}/image_identity.log"
expected_rng_seed_id=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
image_rng_seed_id=$(sed -n 's/^RNG_SEED_ID=//p' "${image_dir}/image_manifest.txt")
if [[ -z "${image_rng_seed_id}" ]]; then
    echo "full QEMU closure: image manifest is missing RNG_SEED_ID" >&2
    exit 2
fi
if [[ "${image_rng_seed_id}" != "${expected_rng_seed_id}" ]]; then
    echo "full QEMU closure: image RNG seed identity mismatch" >&2
    echo "expected=${expected_rng_seed_id} actual=${image_rng_seed_id}" >&2
    echo "rebuild the RTL image with LINUX_RNG_SEED=${LINUX_RNG_SEED}" >&2
    exit 2
fi
DTB=$(sed -n 's/.* dtb=\([^ ]*\).*/\1/p' "${RUN_DIR}/image_identity.log")
[[ -s "${DTB}" ]]
ALIGN_FIRST_PC=$(readelf -h "${KERNEL}" |
    sed -n 's/^[[:space:]]*Entry point address:[[:space:]]*0x//p')
[[ "${ALIGN_FIRST_PC}" =~ ^[0-9a-fA-F]+$ ]]

rtl_env=(
    EDA_RUNNER=/usr/bin/env
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
    LINUX_VCS_EXTRA_ARGS="${LINUX_VCS_EXTRA_ARGS}"
    LINUX_TRACE_LIMIT=0
    LINUX_RETIRE_TRACE_MAX_RECORDS=0
    LINUX_RETIRE_TRACE_STOP_AT_MAX=0
    LINUX_OWNER_TRACE_SIM_ARGS="+RETIRE_TRACE_COMPACT_FPR=1 +RETIRE_TRACE_SCHEMA=00020000"
)
capture_required=0
[[ -n "${REUSE_IRQ_SCHEDULE}" ]] || capture_required=1
[[ -n "${REUSE_CP0_COUNT_SCHEDULE}" ]] || capture_required=1
[[ -n "${REUSE_CP0_RANDOM_SCHEDULE}" ]] || capture_required=1
[[ -n "${REUSE_CPU_CYCLE_SCHEDULE}" ]] || capture_required=1
[[ -n "${REUSE_UART_APB_SCHEDULE}" ]] || capture_required=1
if (( capture_required )); then
    echo "full QEMU closure: capturing RTL schedules, Count/RDHWR reads, cycle timebase, and UART APB events" >&2
    capture_env=("${rtl_env[@]}")
    capture_log="${RUN_DIR}/rtl_cp0_count_schedule_capture.log"
    if [[ -z "${REUSE_CP0_COUNT_SCHEDULE}" ]]; then
        capture_env+=(
            LINUX_RETIRE_TRACE=1
            LINUX_RETIRE_TRACE_PATH=/dev/null
            LINUX_RETIRE_TRACE_MAX_RECORDS=0
            LINUX_COUNT_SCHEDULE_PATH="${CP0_COUNT_SCHEDULE}"
            LINUX_COUNT_SCHEDULE_START_PC="${ALIGN_FIRST_PC}"
        )
    fi
    if [[ -z "${REUSE_IRQ_SCHEDULE}" ]]; then
        capture_env+=(LINUX_IRQ_SCHEDULE_PATH="${IRQ_SCHEDULE}")
        capture_env+=(LINUX_IRQ_SCHEDULE_START_PC="${ALIGN_FIRST_PC}")
        capture_log="${RUN_DIR}/rtl_irq_schedule_capture.log"
    fi
    if [[ -z "${REUSE_CPU_CYCLE_SCHEDULE}" ]]; then
        capture_env+=(
            LINUX_RETIRE_TRACE=1
            LINUX_RETIRE_TRACE_PATH=/dev/null
            LINUX_RETIRE_TRACE_MAX_RECORDS=0
        )
        capture_env+=(LINUX_CYCLE_SCHEDULE_PATH="${CPU_CYCLE_SCHEDULE}")
        capture_env+=(LINUX_CYCLE_SCHEDULE_START_PC="${ALIGN_FIRST_PC}")
        capture_env+=(LINUX_CYCLE_SCHEDULE_INTERVAL="${CPU_CYCLE_SCHEDULE_INTERVAL}")
        capture_log="${RUN_DIR}/rtl_cpu_cycle_schedule_capture.log"
    fi
    if [[ -z "${REUSE_UART_APB_SCHEDULE}" ]]; then
        capture_env+=(LINUX_UART_APB_SCHEDULE_PATH="${UART_APB_SCHEDULE}")
        capture_log="${RUN_DIR}/rtl_uart_apb_schedule_capture.log"
    fi
    if [[ -z "${REUSE_CP0_RANDOM_SCHEDULE}" ]]; then
        capture_env+=(LINUX_RANDOM_SCHEDULE_PATH="${CP0_RANDOM_SCHEDULE}")
        capture_env+=(LINUX_RANDOM_SCHEDULE_START_PC="${ALIGN_FIRST_PC}")
        capture_log="${RUN_DIR}/rtl_cp0_random_schedule_capture.log"
    fi
    set +e
    env "${capture_env[@]}" \
        RUN_DIR="${RUN_DIR}/rtl" \
        bash "${ROOT_DIR}/tb/linux_boot/run_rtl_linux_progress_gate.sh" \
        >"${capture_log}" 2>&1
    schedule_status=$?
    set -e
    if [[ ${schedule_status} -ne 0 ]] ||
       ! grep -q 'PASS (terminal-marker full workload)' \
           "${RUN_DIR}/rtl/completion_report.md" ||
       { [[ -z "${REUSE_IRQ_SCHEDULE}" ]] && [[ ! -s "${IRQ_SCHEDULE}" ]]; } ||
       { [[ -z "${REUSE_CP0_COUNT_SCHEDULE}" ]] && [[ ! -s "${CP0_COUNT_SCHEDULE}" ]]; } ||
       { [[ -z "${REUSE_CPU_CYCLE_SCHEDULE}" ]] && [[ ! -s "${CPU_CYCLE_SCHEDULE}" ]]; } ||
       { [[ -z "${REUSE_UART_APB_SCHEDULE}" ]] && [[ ! -s "${UART_APB_SCHEDULE}" ]]; } ||
       { [[ -z "${REUSE_CP0_RANDOM_SCHEDULE}" ]] && [[ ! -s "${CP0_RANDOM_SCHEDULE}" ]]; }; then
        tail -100 "${capture_log}" >&2 || true
        echo "full QEMU closure: RTL schedule capture failed" >&2
        exit 1
    fi
else
    echo "full QEMU closure: reusing IRQ, CP0 Count/Random, CPU cycle, and UART APB schedules" >&2
fi
irq_schedule_entries=$(wc -l <"${IRQ_SCHEDULE}" | tr -d ' ')
[[ "${irq_schedule_entries}" -gt 0 ]]
irq_schedule_precise_entries=$(awk 'NF == 3 { count++ } END { print count + 0 }' \
    "${IRQ_SCHEDULE}")
[[ "${irq_schedule_precise_entries}" == "${irq_schedule_entries}" ]] || {
    echo "full QEMU closure: IRQ schedule must include a precise EPC for every entry" >&2
    exit 1
}
cp0_count_schedule_entries=$(awk '$1 == "mfc0" || $1 == "rdhwr" { count++ } END { print count + 0 }' \
    "${CP0_COUNT_SCHEDULE}")
cp0_count_schedule_untyped_entries=$(awk '$1 != "mfc0" && $1 != "rdhwr" { count++ } END { print count + 0 }' \
    "${CP0_COUNT_SCHEDULE}")
rdhwr_count_schedule_entries=$(awk '$1 == "rdhwr" { count++ } END { print count + 0 }' \
    "${CP0_COUNT_SCHEDULE}")
[[ "${cp0_count_schedule_entries}" -gt 0 &&
   "${cp0_count_schedule_untyped_entries}" -eq 0 &&
   "${rdhwr_count_schedule_entries}" -gt 0 ]]
cp0_random_schedule_entries=$(awk 'NF == 4 && ($2 == "mfc0" || $2 == "tlbwr") { count++ } END { print count + 0 }' \
    "${CP0_RANDOM_SCHEDULE}")
cp0_random_schedule_noncomment_entries=$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' \
    "${CP0_RANDOM_SCHEDULE}")
cp0_random_schedule_start_pc=$(sed -n \
    's/^# cp0-random-schedule-v1 start_pc=\([0-9a-fA-F]\{8\}\) .*/\1/p' \
    "${CP0_RANDOM_SCHEDULE}" | head -n 1)
[[ "${cp0_random_schedule_entries}" -gt 0 &&
   "${cp0_random_schedule_entries}" == "${cp0_random_schedule_noncomment_entries}" &&
   "${cp0_random_schedule_start_pc,,}" == "${ALIGN_FIRST_PC,,}" ]]
cpu_cycle_schedule_entries=$(awk '$1 ~ /^[0-9]+$/ { count++ } END { print count + 0 }' \
    "${CPU_CYCLE_SCHEDULE}")
[[ "${cpu_cycle_schedule_entries}" -gt 2 ]]
uart_apb_schedule_entries=$(awk '$1 ~ /^[0-9]+$/ { count++ } END { print count + 0 }' \
    "${UART_APB_SCHEDULE}")
[[ "${uart_apb_schedule_entries}" -gt 0 ]]
cpu_cycle_schedule_file_interval=$(sed -n \
    's/^# cpu-cycle-schedule-v1 interval=\([1-9][0-9]*\) start_pc=.*/\1/p' \
    "${CPU_CYCLE_SCHEDULE}" | head -n 1)
cpu_cycle_schedule_start_pc=$(sed -n \
    's/^# cpu-cycle-schedule-v1 interval=[1-9][0-9]* start_pc=\([0-9a-fA-F]\{8\}\)$/\1/p' \
    "${CPU_CYCLE_SCHEDULE}" | head -n 1)
[[ "${cpu_cycle_schedule_file_interval}" == "${CPU_CYCLE_SCHEDULE_INTERVAL}" ]]
[[ "${cpu_cycle_schedule_start_pc,,}" == "${ALIGN_FIRST_PC,,}" ]]
cpu_cycle_schedule_final_seq=$(tail -n 1 "${CPU_CYCLE_SCHEDULE}" | awk '{print $1}')
[[ "${cpu_cycle_schedule_final_seq}" =~ ^[0-9]+$ ]]
uart_diff_timing_property=""
if [[ " ${LINUX_VCS_EXTRA_ARGS} " == *" +define+TB_LINUX_DIFF_UART_TIMING=1 "* ]]; then
    uart_diff_timing_property=",uart-diff-timing=on"
fi
qemu_machine_properties="${QEMU_MACHINE_PROPERTIES}${uart_diff_timing_property},stop-on-terminal-marker=on,cp0-count-schedule=${CP0_COUNT_SCHEDULE},cp0-random-schedule=${CP0_RANDOM_SCHEDULE},cpu-cycle-schedule=${CPU_CYCLE_SCHEDULE},uart-apb-schedule=${UART_APB_SCHEDULE}"

echo "full QEMU closure: starting strict FIFO differential with ${irq_schedule_entries} scheduled IRQs" >&2
compare_log="${RUN_DIR}/trace_compare.log"
set +e
python3 "${SCRIPT_DIR}/trace_compare.py" --stream \
    --align-first-pc "${ALIGN_FIRST_PC}" \
    "${stream_dir}/rtl_retire" "${stream_dir}/qemu_retire" \
    >"${compare_log}" 2>&1 &
compare_pid=$!
env RUN_DIR="${RUN_DIR}/qemu" \
    QEMU_BIN="${QEMU_BIN}" QEMU_SRC="${QEMU_SRC}" QEMU_BUILD="${QEMU_BUILD}" \
    IRQ_SCHEDULE="${IRQ_SCHEDULE}" \
    QEMU_KERNEL="${KERNEL}" QEMU_DTB="${DTB}" QEMU_MEMORY="${QEMU_MEMORY}" \
    QEMU_APPEND="${QEMU_APPEND}" QEMU_MACHINE_PROPERTIES="${qemu_machine_properties}" \
    QEMU_LINUX_RNG_SEED="${LINUX_RNG_SEED}" QEMU_ACCEL=tcg,thread=single \
    QEMU_STOP_ON_TERMINAL=1 QEMU_TERMINAL_MARKER="${TERMINAL_MARKER}" \
    QEMU_MARKER_WATCHDOG_SECONDS="${QEMU_MARKER_WATCHDOG_SECONDS}" \
    QEMU_TERMINAL_DRAIN_SECONDS="${QEMU_TERMINAL_DRAIN_SECONDS}" \
    QEMU_TERMINAL_WAIT_FOR_EXIT=1 \
    QEMU_UNBOUNDED_CAPTURE=1 \
    QEMU_STREAM_MODE=1 \
    QEMU_COMPACT_FPR=1 \
    QEMU_TRACE_SCHEMA=00020000 \
    QEMU_EVENT_STREAM="${stream_dir}/qemu_events" \
    QEMU_STATE_STREAM="${stream_dir}/qemu_states" \
    QEMU_RETIRE_STREAM="${stream_dir}/qemu_retire" \
    MAX_QEMU_EVENTS=0 MAX_QEMU_STATES=0 MAX_QEMU_CAPTURE_BYTES=0 \
    REQUIRE_SMOKE_OUTPUT=0 SKIP_COMPARE=1 \
    TRACE_COMPARE_ALLOW_GOLDEN_PREFIX=0 TRACE_COMPARE_GOLDEN_TO_RTL=0 \
    TRACE_COMPARE_GOLDEN_LIMIT= \
    TRACE_COMPARE_ALIGN_FIRST_PC="$(readelf -h "${KERNEL}" | sed -n 's/^[[:space:]]*Entry point address:[[:space:]]*0x//p')" \
    TRACE_COMPARE_STREAM=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1 &
qemu_pid=$!
setsid env "${rtl_env[@]}" RUN_DIR="${RUN_DIR}/rtl" \
    LINUX_RETIRE_TRACE=1 \
    LINUX_RETIRE_TRACE_PATH="${stream_dir}/rtl_retire" \
    bash "${ROOT_DIR}/tb/linux_boot/run_rtl_linux_progress_gate.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1 &
rtl_pid=$!
set -e

# A failed producer or comparator must stop its peers. Waiting only for the
# comparator can deadlock when a producer fails before opening its FIFO.
rtl_done=0
qemu_done=0
compare_done=0
rtl_status=0
qemu_status_code=0
compare_status=0
failure=0
while (( !rtl_done || !qemu_done || !compare_done )); do
    wait_targets=()
    (( rtl_done )) || wait_targets+=("${rtl_pid}")
    (( qemu_done )) || wait_targets+=("${qemu_pid}")
    (( compare_done )) || wait_targets+=("${compare_pid}")

    finished_pid=
    set +e
    wait -n -p finished_pid "${wait_targets[@]}"
    child_status=$?
    set -e
    if [[ -z "${finished_pid}" ]]; then
        echo "full QEMU closure: could not identify the completed child process" >&2
        failure=1
        break
    fi
    case "${finished_pid}" in
        "${rtl_pid}") rtl_done=1; rtl_status=${child_status}; child_name=RTL ;;
        "${qemu_pid}") qemu_done=1; qemu_status_code=${child_status}; child_name=QEMU ;;
        "${compare_pid}") compare_done=1; compare_status=${child_status}; child_name=comparator ;;
        *)
            echo "full QEMU closure: reaped unexpected child ${finished_pid}" >&2
            failure=1
            break
            ;;
    esac
    if [[ ${child_status} -ne 0 ]]; then
        echo "full QEMU closure: ${child_name} child failed (status ${child_status}); stopping peers" >&2
        failure=1
        break
    fi
done

if [[ ${failure} -ne 0 ]]; then
    if [[ ${rtl_done} -eq 0 ]]; then
        kill -TERM -- "-${rtl_pid}" 2>/dev/null || kill -TERM "${rtl_pid}" 2>/dev/null || true
    fi
    if [[ ${qemu_done} -eq 0 ]]; then
        kill -TERM "${qemu_pid}" 2>/dev/null || true
    fi
    if [[ ${compare_done} -eq 0 ]]; then
        kill -TERM "${compare_pid}" 2>/dev/null || true
    fi
    sleep 1
    if [[ ${rtl_done} -eq 0 ]]; then
        kill -KILL -- "-${rtl_pid}" 2>/dev/null || kill -KILL "${rtl_pid}" 2>/dev/null || true
    fi
    if [[ ${qemu_done} -eq 0 ]]; then
        kill -KILL "${qemu_pid}" 2>/dev/null || true
    fi
    if [[ ${compare_done} -eq 0 ]]; then
        kill -KILL "${compare_pid}" 2>/dev/null || true
    fi
    set +e
    if [[ ${rtl_done} -eq 0 ]]; then wait "${rtl_pid}"; rtl_status=$?; fi
    if [[ ${qemu_done} -eq 0 ]]; then wait "${qemu_pid}"; qemu_status_code=$?; fi
    if [[ ${compare_done} -eq 0 ]]; then wait "${compare_pid}"; compare_status=$?; fi
    set -e
fi
if [[ ${rtl_status} -ne 0 || ${qemu_status_code} -ne 0 ||
      ${compare_status} -ne 0 || ${failure} -ne 0 ]]; then
    tail -100 "${RUN_DIR}/rtl_gate.log" >&2 || true
    tail -100 "${RUN_DIR}/qemu_gate.log" >&2 || true
    cat "${compare_log}" >&2 || true
    echo "full QEMU closure: strict FIFO differential failed" >&2
    exit 1
fi

grep -q 'PASS (terminal-marker full workload)' "${RUN_DIR}/rtl/completion_report.md"
rtl_uart="${RUN_DIR}/rtl/sim/uart.transcript"
[[ -s "${rtl_uart}" ]]
rtl_terminal_count=$(rg -o "${TERMINAL_MARKER}" "${rtl_uart}" | wc -l | tr -d ' ')
[[ "${rtl_terminal_count}" == "1" ]]
qemu_status="${RUN_DIR}/qemu/qemu_capture_status.txt"
[[ -s "${qemu_status}" ]]
grep -q '^terminal_marker=flushed ' "${qemu_status}"
grep -q '^terminal_process_exit=clean child_status=0$' "${qemu_status}"
if grep -q '^qemu-system-mipsel: UART APB schedule exhausted at retire=' \
    "${RUN_DIR}/qemu/qemu_stderr.log"; then
    echo "full QEMU closure: QEMU made an unscheduled UART APB access" >&2
    tail -20 "${RUN_DIR}/qemu/qemu_stderr.log" >&2
    exit 1
fi
grep -q "^SOC_REF_IRQ_SCHEDULE released=${irq_schedule_entries} total=${irq_schedule_entries}$" \
    "${RUN_DIR}/qemu/qemu_stderr.log"
grep -q "^SOC_REF_CP0_COUNT_SCHEDULE consumed=${cp0_count_schedule_entries} total=${cp0_count_schedule_entries}$" \
    "${RUN_DIR}/qemu/qemu_stderr.log"
grep -q "^SOC_REF_CP0_RANDOM_SCHEDULE consumed=${cp0_random_schedule_entries} total=${cp0_random_schedule_entries}$" \
    "${RUN_DIR}/qemu/qemu_stderr.log"
grep -q '^SOC_REF_CPU_CYCLE_SCHEDULE .*total=' \
    "${RUN_DIR}/qemu/qemu_stderr.log"
grep -q '^SOC_REF_UART_APB_SCHEDULE consumed=' \
    "${RUN_DIR}/qemu/qemu_stderr.log"
cpu_cycle_schedule_report=$(rg '^SOC_REF_CPU_CYCLE_SCHEDULE ' \
    "${RUN_DIR}/qemu/qemu_stderr.log")
cpu_cycle_schedule_used=$(sed -n 's/.* used_through=\([0-9][0-9]*\).*/\1/p' \
    <<<"${cpu_cycle_schedule_report}")
cpu_cycle_schedule_report_total=$(sed -n 's/.* total=\([0-9][0-9]*\).*/\1/p' \
    <<<"${cpu_cycle_schedule_report}")
(( cpu_cycle_schedule_report_total == cpu_cycle_schedule_entries ))
(( cpu_cycle_schedule_used + CPU_CYCLE_SCHEDULE_INTERVAL >= cpu_cycle_schedule_final_seq ))
uart_apb_schedule_report=$(rg '^SOC_REF_UART_APB_SCHEDULE ' \
    "${RUN_DIR}/qemu/qemu_stderr.log")
uart_apb_schedule_used=$(sed -n 's/.* consumed=\([0-9][0-9]*\).*/\1/p' \
    <<<"${uart_apb_schedule_report}")
uart_apb_schedule_report_total=$(sed -n 's/.* total=\([0-9][0-9]*\).*/\1/p' \
    <<<"${uart_apb_schedule_report}")
(( uart_apb_schedule_used == uart_apb_schedule_entries &&
   uart_apb_schedule_report_total == uart_apb_schedule_entries ))
grep -q '^TRACE_COMPARE_PASS ' "${compare_log}"
compared_records=$(sed -n 's/^TRACE_COMPARE_PASS records=\([0-9][0-9]*\).*/\1/p' \
    "${compare_log}")
rtl_records=$(sed -n 's/^TRACE_COMPARE_PASS .* rtl_consumed=\([0-9][0-9]*\).*/\1/p' \
    "${compare_log}")
qemu_consumed_records=$(sed -n \
    's/^TRACE_COMPARE_PASS .* golden_consumed=\([0-9][0-9]*\).*/\1/p' \
    "${compare_log}")
rtl_unpaired_records=$(sed -n \
    's/^TRACE_COMPARE_PASS .* rtl_unpaired=\([0-9][0-9]*\).*/\1/p' \
    "${compare_log}")
qemu_unpaired_records=$(sed -n \
    's/^TRACE_COMPARE_PASS .* golden_unpaired=\([0-9][0-9]*\).*/\1/p' \
    "${compare_log}")
rtl_alignment_summary=$(sed -n \
    's/^TRACE_COMPARE_UNPAIRED_SUMMARY side=rtl total=[0-9][0-9]* reasons=//p' \
    "${compare_log}")
qemu_alignment_summary=$(sed -n \
    's/^TRACE_COMPARE_UNPAIRED_SUMMARY side=golden total=[0-9][0-9]* reasons=//p' \
    "${compare_log}")
qemu_records=$(sed -n 's/^QEMU_SYSTEM_RETIRE_STREAM_PASS records=\([0-9][0-9]*\)$/\1/p' \
    "${RUN_DIR}/qemu/qemu_trace_capture.log")
[[ "${compared_records}" =~ ^[0-9]+$ && "${compared_records}" -gt 0 &&
   "${rtl_records}" =~ ^[0-9]+$ && "${rtl_records}" -gt 0 &&
   "${qemu_consumed_records}" =~ ^[0-9]+$ &&
   "${rtl_unpaired_records}" =~ ^[0-9]+$ &&
   "${qemu_unpaired_records}" =~ ^[0-9]+$ &&
   "${qemu_records}" =~ ^[0-9]+$ &&
   "${qemu_records}" == "${qemu_consumed_records}" ]]
(( rtl_records == compared_records + rtl_unpaired_records &&
   qemu_records == compared_records + qemu_unpaired_records ))
[[ -n "${rtl_alignment_summary}" && -n "${qemu_alignment_summary}" ]]
sync_exception_transition_count=$(sed -n \
    's/^TRACE_COMPARE_SYNC_EXCEPTION_PASS count=\([0-9][0-9]*\)$/\1/p' \
    "${compare_log}")
rtl_sync_exception_redirects=$(tr ',' '\n' <<<"${rtl_alignment_summary}" |
    awk -F: '$1 == "rtl_sync_exception_redirect" { print $2 }')
rtl_sync_exception_redirects=${rtl_sync_exception_redirects:-0}
[[ "${sync_exception_transition_count}" =~ ^[0-9]+$ &&
   "${rtl_sync_exception_redirects}" =~ ^[0-9]+$ &&
   "${sync_exception_transition_count}" == "${rtl_sync_exception_redirects}" ]] || {
    echo "full QEMU closure: validated synchronous exception transitions do not match RTL redirects" >&2
    exit 1
}
validate_alignment_summary() {
    local side=$1 summary=$2 entry reason count
    local -a entries
    [[ "${summary}" == "none" ]] && return 0
    IFS=',' read -r -a entries <<<"${summary}"
    for entry in "${entries[@]}"; do
        [[ "${entry}" =~ ^([a-z0-9_]+):([0-9]+)$ ]] || return 1
        reason=${BASH_REMATCH[1]}
        count=${BASH_REMATCH[2]}
        (( count > 0 )) || return 1
        case "${side}:${reason}" in
            rtl:first_pc_prefix|rtl:rtl_sync_exception_redirect) ;;
            *) return 1 ;;
        esac
    done
}
validate_alignment_summary rtl "${rtl_alignment_summary}" || {
    echo "full QEMU closure: unreviewed RTL alignment reasons: ${rtl_alignment_summary}" >&2
    exit 1
}
[[ "${qemu_alignment_summary}" == "none" ]] || {
    echo "full QEMU closure: unreviewed QEMU alignment reasons: ${qemu_alignment_summary}" >&2
    exit 1
}

validator="${ROOT_DIR}/scripts/validate_linux_differential.py"
source_identity="${RUN_DIR}/source_identity.txt"
tracked_diff_hash=$(git -C "${ROOT_DIR}" diff --binary HEAD -- |
    sha256sum | awk '{print $1}')
untracked_content_hash=$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard -z |
    xargs -0 -r sha256sum | LC_ALL=C sort | sha256sum | awk '{print $1}')
printf 'tracked_diff=%s\nuntracked_content=%s\n' \
    "${tracked_diff_hash}" "${untracked_content_hash}" |
    sha256sum | awk '{print $1}' >"${source_identity}"
git_dirty_status_hash=$(git -C "${ROOT_DIR}" status --short --untracked-files=all |
    sha256sum | awk '{print $1}')
seed_id=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
python3 "${validator}" create --output "${RUN_DIR}/differential_manifest.json" \
    --file kernel_sha256="${KERNEL}" \
    --file dtb_sha256="${DTB}" \
    --file image_manifest_sha256="${image_dir}/image_manifest.txt" \
    --file bootrom_sha256="${image_dir}/bootrom.hex" \
    --file ddr_image_sha256="${image_dir}/ddr.hex" \
    --set root_image_sha256="not-applicable:no-independent-rootfs" \
    --file qemu_sha256="${QEMU_BIN}" \
    --file qemu_model_build_log_sha256="${RUN_DIR}/qemu_model_build.log" \
    --file qemu_plugin_sha256="${RUN_DIR}/qemu/libqemu_retire.so" \
    --file qemu_stream_converter_sha256="${SCRIPT_DIR}/qemu_system_state_to_jsonl_stream.py" \
    --file qemu_state_converter_sha256="${SCRIPT_DIR}/qemu_system_state_to_jsonl.py" \
    --file trace_comparator_sha256="${SCRIPT_DIR}/trace_compare.py" \
    --file rtl_retire_capture_sha256="${SCRIPT_DIR}/retire_trace_capture.sv" \
    --file rtl_retire_binding_sha256="${ROOT_DIR}/tb/soc_test/tb_mips_soc.v" \
    --file full_closure_gate_sha256="${SCRIPT_DIR}/run_qemu_linux_full_closure_gate.sh" \
    --file irq_schedule_sha256="${IRQ_SCHEDULE}" \
    --file cp0_count_schedule_sha256="${CP0_COUNT_SCHEDULE}" \
    --file cp0_random_schedule_sha256="${CP0_RANDOM_SCHEDULE}" \
    --file cpu_cycle_schedule_sha256="${CPU_CYCLE_SCHEDULE}" \
    --file uart_apb_schedule_sha256="${UART_APB_SCHEDULE}" \
    --file rtl_simulator_sha256="${RUN_DIR}/rtl/sim/simv" \
    --file differential_compare_sha256="${compare_log}" \
    --file qemu_capture_status_sha256="${qemu_status}" \
    --file rtl_source_identity_sha256="${source_identity}" \
    --set git_commit="$(git -C "${ROOT_DIR}" rev-parse HEAD)" \
    --set git_dirty_status_hash="${git_dirty_status_hash}" \
    --set git_worktree_content_hash="$(cat "${source_identity}")" \
    --set entropy_mode=deterministic \
    --set entropy_seed_id="${seed_id}" \
    --set entropy_seed_width="$(( ${#LINUX_RNG_SEED} * 4 ))" \
    --set entropy_contract_version=uhi-rng-v1 \
    --set qemu_machine=mips32-soc-ref \
    --set qemu_machine_properties="${qemu_machine_properties}" \
    --set qemu_memory="${QEMU_MEMORY}" \
    --set trace_schema=00020000 \
    --set trace_state_contract=full-gpr-hilo-v1 \
    --set comparator_mode=strict-stream \
    --set memory_scope=systemd-user-cgroup \
    --set memory_max="${QEMU_CLOSURE_MEMORY_MAX}" \
    --set memory_swap_max="${QEMU_CLOSURE_SWAP_MAX}" \
    --set min_free_kib="${QEMU_CLOSURE_MIN_FREE_KIB}" \
    --set tmpdir="${TMPDIR}" \
    --set cp0_identity="rtl-cp0-identity=on,linux-guest=on,cp0-retire-clock=on" \
    --set cp0_count_contract="rtl-mfc0-rdhwr-count-replay-v2" \
    --set cp0_count_schedule_entries="${cp0_count_schedule_entries}" \
    --set rdhwr_count_schedule_entries="${rdhwr_count_schedule_entries}" \
    --set cp0_random_schedule_contract="rtl-mfc0-random-tlbwr-retire-v1" \
    --set cp0_random_schedule_entries="${cp0_random_schedule_entries}" \
    --set cp0_random_schedule_consumed="${cp0_random_schedule_entries}" \
    --set cpu_cycle_schedule_contract="rtl-retire-cycle-linear-interpolation-v1" \
    --set cpu_cycle_schedule_interval="${CPU_CYCLE_SCHEDULE_INTERVAL}" \
    --set cpu_cycle_schedule_entries="${cpu_cycle_schedule_entries}" \
    --set uart_apb_schedule_contract="rtl-apb-uart-access-cycle-v1" \
    --set uart_apb_schedule_entries="${uart_apb_schedule_entries}" \
    --set uart_apb_schedule_consumed="${uart_apb_schedule_used}" \
    --set irq_schedule_source="${REUSE_IRQ_SCHEDULE:-captured-from-current-rtl-run}" \
    --set irq_schedule_contract=rtl-retire-cause-epc-v2 \
    --set irq_schedule_entries="${irq_schedule_entries}" \
    --set irq_schedule_precise_entries="${irq_schedule_precise_entries}" \
    --set irq_schedule_released="${irq_schedule_entries}" \
    --set rtl_image_dir="${image_dir}" \
    --set rtl_defines="SOC_LINUX_BOOT_ENABLE=1,SOC_MMU_ENABLE=1" \
    --set rtl_vcs_extra_args="${LINUX_VCS_EXTRA_ARGS}" \
    --set linux_cmdline="${QEMU_APPEND}" \
    --set retire_bound="${RTL_WATCHDOG_CYCLES}" \
    --set cycle_bound="${RTL_WATCHDOG_CYCLES}" \
    --set timeout_bound="${HOST_TIMEOUT}" \
    --set terminal_condition=terminal_marker \
    --set terminal_marker="${TERMINAL_MARKER}" \
    --set terminal_boundary_contract=uart-marker-clean-qemu-shutdown-v1 \
    --set sync_exception_transition_count="${sync_exception_transition_count}" \
    --set rtl_records="${rtl_records}" \
    --set qemu_records="${qemu_records}" \
    --set compared_records="${compared_records}" \
    --set rtl_unpaired_records="${rtl_unpaired_records}" \
    --set qemu_unpaired_records="${qemu_unpaired_records}" \
    --set rtl_alignment_summary="${rtl_alignment_summary}" \
    --set qemu_alignment_summary="${qemu_alignment_summary}" \
    --set qemu_terminal_drain_seconds="${QEMU_TERMINAL_DRAIN_SECONDS}" \
    --set qemu_terminal_status="$(grep '^terminal_marker=' "${qemu_status}")"
python3 "${validator}" validate-manifest "${RUN_DIR}/differential_manifest.json" \
    >"${RUN_DIR}/manifest_validate.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# Full QEMU Linux RTL Closure

- Result: PASS (terminal-marker full workload)
- Kernel/DTB/image: ${KERNEL} / ${DTB} / ${image_dir}
- Deterministic entropy seed id: ${seed_id}
- QEMU model build log: ${RUN_DIR}/qemu_model_build.log
- RTL trace records: ${rtl_records}
- QEMU trace records: ${qemu_records}
- Strict compared records: ${compared_records}
- Producer-specific aligned records: RTL=${rtl_unpaired_records}, QEMU=${qemu_unpaired_records}
- Alignment reasons: RTL=${rtl_alignment_summary}, QEMU=${qemu_alignment_summary}
- Trace transport: live FIFOs (no unbounded JSONL materialization)
- Comparator: strict streaming (`trace_schema=00020000`, full GPR and HI/LO state)
- Memory envelope: systemd user cgroup, RAM=${QEMU_CLOSURE_MEMORY_MAX}, swap=${QEMU_CLOSURE_SWAP_MAX}
- Minimum free space: ${QEMU_CLOSURE_MIN_FREE_KIB} KiB on the run and TMPDIR filesystems
- Temporary build directory: ${TMPDIR}
- Interrupt replay schedule entries: ${irq_schedule_entries}
- Interrupt replay contract: RTL retire boundary, Cause, and precise EPC (v2)
- QEMU interrupt replay entries released: ${irq_schedule_entries}
- RTL CP0 Count reads replayed: ${cp0_count_schedule_entries} (${rdhwr_count_schedule_entries} via RDHWR)
- RTL CP0 Random reads/TLBWR replacement indices replayed: ${cp0_random_schedule_entries}
- QEMU CP0 Random schedule events consumed: ${cp0_random_schedule_entries}
- RTL cycle-time samples replayed for peripheral timing: ${cpu_cycle_schedule_entries}
- RTL cycle-time sampling interval: ${CPU_CYCLE_SCHEDULE_INTERVAL} retirements
- QEMU cycle schedule usage: through retire ${cpu_cycle_schedule_used} of ${cpu_cycle_schedule_final_seq}
- RTL UART APB transfers replayed: ${uart_apb_schedule_used} of ${uart_apb_schedule_entries}
- Replay schedule epoch PC: ${ALIGN_FIRST_PC}
- Interrupt schedule source: ${REUSE_IRQ_SCHEDULE:-captured from RTL acceptance}
- RTL terminal markers: ${rtl_terminal_count}
- QEMU terminal status: $(grep '^terminal_marker=' "${qemu_status}")
- QEMU terminal process exit: $(grep '^terminal_process_exit=' "${qemu_status}")
- RTL synchronous exceptions checked against QEMU Cause/EPC/BD: ${sync_exception_transition_count}
- QEMU terminal drain: ${QEMU_TERMINAL_DRAIN_SECONDS}s
- RTL extra VCS defines: ${LINUX_VCS_EXTRA_ARGS:-none}
- Differential manifest: ${RUN_DIR}/differential_manifest.json
- Producer evidence: rtl_gate.log, qemu_gate.log, trace_compare.log,
  qemu/qemu_trace_capture.log
- Watchdogs: RTL cycles=${RTL_WATCHDOG_CYCLES}, host=${HOST_TIMEOUT}, QEMU marker=${QEMU_MARKER_WATCHDOG_SECONDS}s
- Boundary: the declared generic Linux image through its terminal userspace
  marker; this is not unrestricted Linux or full ISA/product signoff.
EOF
echo "full QEMU closure: PASS (compared records=${compared_records}, aligned RTL/QEMU=${rtl_unpaired_records}/${qemu_unpaired_records})"
