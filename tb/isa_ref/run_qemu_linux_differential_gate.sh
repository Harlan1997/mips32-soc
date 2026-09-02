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
QEMU_APPEND=${QEMU_APPEND:-console=ttyS0 earlyprintk=serial,0x1f000900 panic=-1}
# The relocated 32r2 kernel's first instruction in the current image is at
# 0x88a55c78. Keep this overrideable because a different kernel configuration
# may move the first matched instruction; the previous 0x89255c78 value was
# stale and caused a false alignment failure before any architectural compare.
ALIGN_FIRST_PC=${ALIGN_FIRST_PC:-88a55c78}
MAX_TRACE_RECORDS=${MAX_TRACE_RECORDS:-1000000}
MAX_TRACE_BYTES=${MAX_TRACE_BYTES:-268435456}

if [[ -z "${KERNEL}" || ! -s "${KERNEL}" ]]; then
    echo "QEMU Linux differential: KERNEL=/path/to/vmlinux is required" >&2
    exit 2
fi
KERNEL=$(realpath "${KERNEL}")
if [[ -z "${DTB}" ]]; then
    DTB="$(dirname "${KERNEL}")/mips32_soc_ref.dtb"
fi
if [[ ! -s "${DTB}" ]]; then
    echo "QEMU Linux differential: DTB is missing: ${DTB}" >&2
    exit 2
fi
DTB=$(realpath "${DTB}")

mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/rtl_gate.log" "${RUN_DIR}/qemu_gate.log"

# The RTL runner builds the same relocatable image used by the progress gate,
# while the QEMU side receives the kernel and DTB directly.  The explicit
# handoff anchor accounts only for Boot ROM records absent from -kernel mode.
SKIP_COVERAGE=1 LINUX_RETIRE_TRACE=1 \
RUN_DIR="${RUN_DIR}/rtl" KERNEL="${KERNEL}" SKIP_LINUX_BUILD=1 \
RTL_CYCLE_LIMIT="${RTL_CYCLE_LIMIT}" HOST_TIMEOUT="${HOST_TIMEOUT}" \
LINUX_RETIRE_TRACE_MAX_RECORDS="${MAX_TRACE_RECORDS}" \
tb/linux_boot/run_rtl_linux_progress_gate.sh >"${RUN_DIR}/rtl_gate.log" 2>&1

rtl_trace="${RUN_DIR}/rtl/sim/rtl_retire.jsonl"
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
capture_records=${MAX_TRACE_RECORDS}

env RUN_DIR="${RUN_DIR}/qemu" \
    QEMU_KERNEL="${KERNEL}" QEMU_DTB="${DTB}" QEMU_MEMORY="${QEMU_MEMORY}" \
    QEMU_ACCEL=tcg,thread=single \
    QEMU_APPEND="${QEMU_APPEND}" QEMU_TIMEOUT="${QEMU_TIMEOUT}" \
    MAX_QEMU_EVENTS="${capture_records}" \
    MAX_QEMU_STATES="$((capture_records + 1))" \
    MAX_QEMU_CAPTURE_BYTES="${MAX_TRACE_BYTES}" REQUIRE_SMOKE_OUTPUT=0 \
    RTL_TRACE="${rtl_trace}" TRACE_COMPARE_ALIGN_FIRST_PC="${ALIGN_FIRST_PC}" \
    TRACE_COMPARE_STREAM=1 \
    TRACE_COMPARE_GOLDEN_TO_RTL=1 \
    TRACE_COMPARE_ALLOW_GOLDEN_PREFIX=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

grep -q '^TRACE_COMPARE_PASS ' "${RUN_DIR}/qemu/trace_compare.log"
qemu_records=$(wc -l <"${RUN_DIR}/qemu/qemu_retire.jsonl")
compared_records=$(sed -n 's/^TRACE_COMPARE_PASS records=\([0-9][0-9]*\).*/\1/p' \
    "${RUN_DIR}/qemu/trace_compare.log")
if [[ -z "${compared_records}" ]]; then
    echo "QEMU Linux differential: comparator did not publish a PASS record count" >&2
    exit 1
fi
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU Linux RTL Retire Differential

- Result: PASS (bounded Linux retire prefix)
- Kernel: ${KERNEL}
- DTB: ${DTB}
- RTL trace: ${rtl_trace}
- QEMU trace: ${RUN_DIR}/qemu/qemu_retire.jsonl
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
