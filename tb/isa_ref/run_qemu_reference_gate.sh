#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-linux-user/qemu-mipsel"}
QEMU_VERSION=${QEMU_VERSION:-9.2.0}
QEMU_ELF=${QEMU_ELF:-}
RTL_TRACE=${RTL_TRACE:-"${RUN_DIR}/rtl_retire.jsonl"}
QEMU_EVENT_TRACE=${QEMU_EVENT_TRACE:-"${RUN_DIR}/qemu_instruction_events.jsonl"}
QEMU_CPU_LOG=${QEMU_CPU_LOG:-"${RUN_DIR}/qemu_cpu.log"}
GOLDEN_TRACE=${GOLDEN_TRACE:-"${RUN_DIR}/qemu_retire.jsonl"}
QEMU_PLUGIN=${QEMU_PLUGIN:-"${RUN_DIR}/libqemu_retire.so"}
PLUGIN_SOURCE=${PLUGIN_SOURCE:-"${ROOT_DIR}/tb/isa_ref/qemu_retire_plugin.c"}
PLUGIN_INCLUDE=${PLUGIN_INCLUDE:-"${ROOT_DIR}/build/deps/qemu/include"}
QEMU_EXPECTED_EXIT=${QEMU_EXPECTED_EXIT:-0}

mkdir -p "${RUN_DIR}"

cat > "${RUN_DIR}/qemu_reference_report.md" <<EOF
# QEMU-MIPS Retire Differential Gate

- Requested version: ${QEMU_VERSION}
- Binary: ${QEMU_BIN}
- Guest ELF: ${QEMU_ELF:-<unset>}
- RTL trace: ${RTL_TRACE}
- QEMU event trace: ${QEMU_EVENT_TRACE}
- QEMU CPU snapshot log: ${QEMU_CPU_LOG}
- Golden retire trace: ${GOLDEN_TRACE}
- Expected guest exit: ${QEMU_EXPECTED_EXIT}
- Scope: one-insn-per-TB, single-vCPU QEMU retire trace plus RTL JSONL
  differential compare.
EOF

if [[ ! -x "${QEMU_BIN}" ]]; then
    cat >> "${RUN_DIR}/qemu_reference_report.md" <<'EOF'
- Result: BLOCKED
- Reason: the configured QEMU binary is not available. Build the pinned
  project-local dependency or pass QEMU_BIN=/path/to/qemu-mipsel.
- No ISA signoff is claimed.
EOF
    echo "QEMU-MIPS retire differential gate: BLOCKED (missing ${QEMU_BIN})" >&2
    exit 2
fi

if ! "${QEMU_BIN}" --version > "${RUN_DIR}/qemu_version.txt" 2>&1; then
    echo "QEMU-MIPS retire differential gate: failed to execute QEMU" >&2
    exit 1
fi

if [[ -z "${QEMU_ELF}" || ! -s "${QEMU_ELF}" ]]; then
    cat >> "${RUN_DIR}/qemu_reference_report.md" <<'EOF'
- Result: BLOCKED
- Reason: QEMU_ELF must identify the exact guest image used for the RTL run.
EOF
    echo "QEMU-MIPS retire differential gate: BLOCKED (missing QEMU_ELF)" >&2
    exit 2
fi

if [[ ! -s "${PLUGIN_SOURCE}" || ! -s "${PLUGIN_INCLUDE}/qemu-plugin.h" ]]; then
    cat >> "${RUN_DIR}/qemu_reference_report.md" <<EOF
- Result: BLOCKED
- Reason: QEMU plugin source or qemu-plugin.h is unavailable.
- Source: ${PLUGIN_SOURCE}
- Include: ${PLUGIN_INCLUDE}/qemu-plugin.h
EOF
    echo "QEMU-MIPS retire differential gate: BLOCKED (missing plugin inputs)" >&2
    exit 2
fi

cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    -I"${PLUGIN_INCLUDE}" $(pkg-config --cflags glib-2.0) \
    "${PLUGIN_SOURCE}" -o "${QEMU_PLUGIN}" \
    $(pkg-config --libs glib-2.0) >"${RUN_DIR}/plugin_compile.log" 2>&1

set +e
"${QEMU_BIN}" -one-insn-per-tb \
    -plugin "file=${QEMU_PLUGIN},trace=${QEMU_EVENT_TRACE}" \
    -d cpu,nochain -D "${QEMU_CPU_LOG}" \
    "${QEMU_ELF}" >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
qemu_status=$?
set -e
if [[ "${qemu_status}" -ne "${QEMU_EXPECTED_EXIT}" ]]; then
    cat >> "${RUN_DIR}/qemu_reference_report.md" <<'EOF'
- Result: FAIL
- Reason: QEMU guest execution failed; see qemu_stderr.log.
EOF
    echo "QEMU-MIPS retire differential gate: FAIL (guest exit ${qemu_status})" >&2
    exit 1
fi

python3 "${SCRIPT_DIR}/qemu_cpu_trace_to_jsonl.py" \
    "${QEMU_EVENT_TRACE}" "${QEMU_CPU_LOG}" "${GOLDEN_TRACE}" \
    >"${RUN_DIR}/qemu_trace_capture.log" 2>&1

if [[ ! -s "${RTL_TRACE}" ]]; then
    cat >> "${RUN_DIR}/qemu_reference_report.md" <<EOF
- Result: BLOCKED
- Reason: RTL retire trace is unavailable at ${RTL_TRACE}.
- QEMU capture is complete; no differential result is claimed.
EOF
    echo "QEMU-MIPS retire differential gate: BLOCKED (missing RTL trace)" >&2
    exit 2
fi

python3 "${SCRIPT_DIR}/trace_compare.py" "${RTL_TRACE}" "${GOLDEN_TRACE}" \
    >"${RUN_DIR}/trace_compare.log" 2>&1
cat >> "${RUN_DIR}/qemu_reference_report.md" <<'EOF'
- Result: PASS
- Evidence: plugin_compile.log, qemu_trace_capture.log, trace_compare.log
EOF
echo "QEMU-MIPS retire differential gate: PASS"
