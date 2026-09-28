#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=$(realpath -m "${RUN_DIR:-${ROOT_DIR}/build/isa_ref/qemu_linux_differential}")
KERNEL=${KERNEL:-}
DTB=${DTB:-}
RTL_CYCLE_LIMIT=${RTL_CYCLE_LIMIT:-100000}
HOST_TIMEOUT=${HOST_TIMEOUT:-180s}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-2s}
QEMU_MEMORY=${QEMU_MEMORY:-128M}
QEMU_SRC=${QEMU_SRC:-}
QEMU_BUILD=${QEMU_BUILD:-}
QEMU_APPEND=${QEMU_APPEND:-console=ttyS0 earlyprintk=serial,0x1f000900 panic=-1}
# The first QEMU retire is the kernel ELF entry. Keep an explicit override for
# unusual boot wrappers, but derive the default from the supplied artifact so
# a different kernel configuration cannot fail before any architectural
# comparison merely because its relocated entry moved.
ALIGN_FIRST_PC=${ALIGN_FIRST_PC:-}
MAX_TRACE_RECORDS=${MAX_TRACE_RECORDS:-1000000}
MAX_TRACE_BYTES=${MAX_TRACE_BYTES:-268435456}
QEMU_BIN=${QEMU_BIN:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel}
# Optional prebuilt RTL image handoff.  This is required when the supplied
# kernel/DTB artifact bundle already contains bootrom.hex and ddr.hex but does
# not contain the Linux build tree or DTC used to regenerate them.
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-}
REUSE_LINUX_IMAGE=${REUSE_LINUX_IMAGE:-0}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-}
LINUX_RETIRE_TRACE_PATH=${LINUX_RETIRE_TRACE_PATH:-}

if [[ "${FULL_QEMU_CLOSURE:-0}" == "1" ]]; then
    exec "${SCRIPT_DIR}/run_qemu_linux_terminal_closure_gate.sh"
fi

if [[ -z "${KERNEL}" || ! -s "${KERNEL}" ]]; then
    echo "QEMU Linux differential: KERNEL=/path/to/vmlinux is required" >&2
    exit 2
fi
if [[ ! -x "${QEMU_BIN}" ]]; then
    echo "QEMU Linux differential: executable QEMU_BIN is required: ${QEMU_BIN}" >&2
    exit 2
fi
KERNEL=$(realpath "${KERNEL}")

# Reused image bundles are validated before starting either producer.  A
# generated bundle is validated again after the RTL child creates it below.
if [[ -n "${LINUX_IMAGE_DIR}" && "${REUSE_LINUX_IMAGE}" == "1" ]]; then
    preflight_image_dir=$(realpath -m "${LINUX_IMAGE_DIR}")
    preflight_identity_args=(--image-dir "${preflight_image_dir}" --kernel "${KERNEL}")
    if [[ -n "${DTB}" ]]; then
        preflight_identity_args+=(--dtb "${DTB}")
    fi
    python3 "${ROOT_DIR}/scripts/validate_linux_image_identity.py" \
        "${preflight_identity_args[@]}" >"${RUN_DIR}/image_identity_preflight.log"
fi

if [[ -z "${ALIGN_FIRST_PC}" ]]; then
    readelf_bin=${READELF:-readelf}
    if ! command -v "${readelf_bin}" >/dev/null 2>&1; then
        echo "QEMU Linux differential: readelf is required to derive kernel entry (set ALIGN_FIRST_PC to override)" >&2
        exit 2
    fi
    entry_line=$("${readelf_bin}" -h "${KERNEL}" 2>/dev/null |
        sed -n 's/^[[:space:]]*Entry point address:[[:space:]]*//p')
    if [[ ! "${entry_line}" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "QEMU Linux differential: unable to derive ELF entry from ${KERNEL}; set ALIGN_FIRST_PC" >&2
        exit 2
    fi
    ALIGN_FIRST_PC=${entry_line#0x}
fi
ALIGN_FIRST_PC=${ALIGN_FIRST_PC#0x}
ALIGN_FIRST_PC=${ALIGN_FIRST_PC#0X}
if [[ ! "${ALIGN_FIRST_PC}" =~ ^[0-9a-fA-F]+$ ]]; then
    echo "QEMU Linux differential: ALIGN_FIRST_PC must be hexadecimal: ${ALIGN_FIRST_PC}" >&2
    exit 2
fi

mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/rtl_gate.log" "${RUN_DIR}/qemu_gate.log"

# The RTL runner builds the same relocatable image used by the progress gate,
# while the QEMU side receives the kernel and DTB directly.  The explicit
# handoff anchor accounts only for Boot ROM records absent from -kernel mode.
echo "QEMU Linux differential: starting RTL child" \
    "cycle_limit=${RTL_CYCLE_LIMIT} run_dir=${RUN_DIR}/rtl" >&2
set +e
SKIP_COVERAGE=1 LINUX_RETIRE_TRACE=1 \
RUN_DIR="${RUN_DIR}/rtl" KERNEL="${KERNEL}" SKIP_LINUX_BUILD=1 \
LINUX_IMAGE_DIR="${LINUX_IMAGE_DIR}" REUSE_LINUX_IMAGE="${REUSE_LINUX_IMAGE}" \
LINUX_RNG_SEED="${LINUX_RNG_SEED}" \
RTL_CYCLE_LIMIT="${RTL_CYCLE_LIMIT}" HOST_TIMEOUT="${HOST_TIMEOUT}" \
LINUX_RETIRE_TRACE_MAX_RECORDS="${MAX_TRACE_RECORDS}" \
LINUX_RETIRE_TRACE_STOP_AT_MAX=1 \
  bash "${ROOT_DIR}/tb/linux_boot/run_rtl_linux_progress_gate.sh" \
  >"${RUN_DIR}/rtl_gate.log" 2>&1
rtl_status=$?
set -e
if [[ ${rtl_status} -ne 0 ]]; then
    {
        echo "QEMU Linux differential: RTL child failed with status ${rtl_status}"
        echo "RTL child log: ${RUN_DIR}/rtl_gate.log"
        tail -80 "${RUN_DIR}/rtl_gate.log" || true
    } >&2
    exit "${rtl_status}"
fi

# The joined gate owns one immutable RTL image bundle.  Never infer the QEMU
# DTB from the kernel directory: that path previously allowed two valid but
# different guest descriptions to enter the comparison.
image_dir="${LINUX_IMAGE_DIR:-${RUN_DIR}/rtl/image}"
image_dir=$(realpath -m "${image_dir}")
identity_args=(--image-dir "${image_dir}" --kernel "${KERNEL}")
if [[ -n "${DTB}" ]]; then
    identity_args+=(--dtb "${DTB}")
fi
python3 "${ROOT_DIR}/scripts/validate_linux_image_identity.py" \
    "${identity_args[@]}" >"${RUN_DIR}/image_identity.log"
DTB=$(sed -n 's/.* dtb=\([^ ]*\).*/\1/p' "${RUN_DIR}/image_identity.log")
[[ -n "${DTB}" && -s "${DTB}" ]] || {
    echo "QEMU Linux differential: image identity did not return a DTB" >&2
    exit 2
}

rtl_trace="${LINUX_RETIRE_TRACE_PATH:-${RUN_DIR}/rtl/sim/rtl_retire.jsonl}"
[[ -s "${rtl_trace}" ]]
rtl_records=$(wc -l <"${rtl_trace}")
if (( rtl_records <= 0 )); then
    echo "QEMU Linux differential: RTL trace is empty" >&2
    exit 1
fi
# The RTL run is cycle-bounded, so it can retire fewer instructions than the
# reference would execute during its wall-clock capture window. Limit QEMU
# to the exact available RTL prefix; otherwise the strict comparator reports
# a length mismatch after an otherwise valid common prefix.
# QEMU only needs the prefix that the cycle-bounded RTL run actually retired.
# This is also the primary resource bound: a timed-out reference guest must
# not continue materializing states after the RTL comparison window ends.
capture_records=${rtl_records}

env RUN_DIR="${RUN_DIR}/qemu" \
    QEMU_KERNEL="${KERNEL}" QEMU_DTB="${DTB}" QEMU_MEMORY="${QEMU_MEMORY}" \
    QEMU_SRC="${QEMU_SRC}" QEMU_BUILD="${QEMU_BUILD}" \
    QEMU_MACHINE_PROPERTIES="rtl-cp0-identity=on" \
    QEMU_LINUX_RNG_SEED="${LINUX_RNG_SEED}" \
    QEMU_ACCEL=tcg,thread=single \
    QEMU_APPEND="${QEMU_APPEND}" QEMU_TIMEOUT="${QEMU_TIMEOUT}" \
    MAX_QEMU_EVENTS="${capture_records}" \
    MAX_QEMU_STATES="$((capture_records + 1))" \
    MAX_QEMU_CAPTURE_BYTES="${MAX_TRACE_BYTES}" REQUIRE_SMOKE_OUTPUT=0 \
    RTL_TRACE="${rtl_trace}" TRACE_COMPARE_ALIGN_FIRST_PC="${ALIGN_FIRST_PC}" \
    TRACE_COMPARE_STREAM=1 \
    TRACE_COMPARE_GOLDEN_TO_RTL=1 \
    TRACE_COMPARE_ALLOW_GOLDEN_PREFIX=1 SKIP_COMPARE=1 QEMU_BIN="${QEMU_BIN}" \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

qemu_records=$(wc -l <"${RUN_DIR}/qemu/qemu_retire.jsonl")
[[ "${qemu_records}" -eq "${rtl_records}" ]] || {
    echo "QEMU Linux differential: capture length differs before manifest validation" >&2
    exit 1
}

validator="${ROOT_DIR}/scripts/validate_linux_differential.py"
manifest="${RUN_DIR}/differential_manifest.json"
source_identity="${RUN_DIR}/source_identity.txt"
{
    git -C "${ROOT_DIR}" status --short --untracked-files=all
} | sha256sum | awk '{print $1}' >"${source_identity}"
seed_id=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
python3 "${validator}" create --output "${manifest}" \
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
    --set entropy_mode="$([[ -n "${LINUX_RNG_SEED}" ]] && echo deterministic || echo default)" \
    --set entropy_seed_id="${seed_id}" \
    --set entropy_seed_width="$(( ${#LINUX_RNG_SEED} * 4 ))" \
    --set entropy_contract_version="uhi-rng-v1" \
    --set qemu_machine="mips32-soc-ref" \
    --set qemu_memory="${QEMU_MEMORY}" \
    --set cp0_identity="rtl-cp0-identity=on" \
    --set rtl_image_dir="${image_dir}" \
    --set rtl_defines="SOC_LINUX_BOOT_ENABLE=1,SOC_MMU_ENABLE=1" \
    --set linux_cmdline="${QEMU_APPEND}" \
    --set retire_bound="${capture_records}" \
    --set cycle_bound="${RTL_CYCLE_LIMIT}" \
    --set timeout_bound="${HOST_TIMEOUT}" \
    --set terminal_condition="bounded_retire_prefix"
python3 "${validator}" validate-manifest "${manifest}" >"${RUN_DIR}/manifest_validate.log"
python3 "${validator}" validate-trace "${rtl_trace}" \
    --max-records "${capture_records}" --exact-records "${rtl_records}" \
    >"${RUN_DIR}/rtl_trace_validate.log"
python3 "${validator}" validate-trace "${RUN_DIR}/qemu/qemu_retire.jsonl" \
    --max-records "${capture_records}" --exact-records "${qemu_records}" \
    >"${RUN_DIR}/qemu_trace_validate.log"

compare_args=(--align-first-pc "${ALIGN_FIRST_PC}" --allow-golden-prefix
              --truncate-golden-to-rtl --stream)
python3 "${SCRIPT_DIR}/trace_compare.py" "${compare_args[@]}" \
    "${rtl_trace}" "${RUN_DIR}/qemu/qemu_retire.jsonl" \
    >"${RUN_DIR}/trace_compare.log" 2>&1
grep -q '^TRACE_COMPARE_PASS ' "${RUN_DIR}/trace_compare.log"
compared_records=$(sed -n 's/^TRACE_COMPARE_PASS records=\([0-9][0-9]*\).*/\1/p' \
    "${RUN_DIR}/trace_compare.log")
[[ -n "${compared_records}" ]]
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU Linux RTL Retire Differential

- Result: PASS (bounded Linux retire prefix)
- Kernel: ${KERNEL}
- DTB: ${DTB}
- RTL trace: ${rtl_trace}
- QEMU trace: ${RUN_DIR}/qemu/qemu_retire.jsonl
- Differential manifest: ${manifest}
- Manifest validation: PASS
- Trace validation: PASS (explicit retire_seq and exact bounded length)
- Compared records: ${compared_records} (aligned RTL/QEMU prefix)
- Captured records: ${rtl_records} (RTL, including the pre-handoff ROM prefix)
- Handoff anchor: PC ${ALIGN_FIRST_PC}, exact PC/instruction match
- QEMU capture timeout: ${QEMU_TIMEOUT}
- Evidence: rtl_gate.log, qemu_gate.log, qemu/trace_compare.log
- Scope: relocated kernel instructions compared one retire at a time after
  the explicit Boot ROM-to-kernel handoff, for the bounded QEMU capture.
- Boundary: this is not Linux userspace boot, full system-mode Linux
  differential, complete ISA/privileged/MMU compliance, or product signoff.
EOF
echo "QEMU Linux RTL retire differential: PASS (bounded prefix)"
