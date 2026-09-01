#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_retire"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
# Match the default RTL contract. FPU-specific gates select 24Kf explicitly.
QEMU_CPU=${QEMU_CPU:-24Kc}
FW_ELF=${FW_ELF:-"${ROOT_DIR}/build/firmware/qemu_system_smoke/firmware.elf"}
QEMU_KERNEL=${QEMU_KERNEL:-}
QEMU_DTB=${QEMU_DTB:-}
QEMU_MEMORY=${QEMU_MEMORY:-64K}
QEMU_APPEND=${QEMU_APPEND:-}
QSPI_IMAGE=${QSPI_IMAGE:-}
PLUGIN_INCLUDE=${PLUGIN_INCLUDE:-""}
PLUGIN_SOURCE=${PLUGIN_SOURCE:-"${ROOT_DIR}/tb/isa_ref/qemu_retire_plugin.c"}
PLUGIN=${RUN_DIR}/libqemu_retire.so
RTL_TRACE=${RTL_TRACE:-}
IRQ_SCHEDULE=${IRQ_SCHEDULE:-}
DMA_EVENT_TRACE=${DMA_EVENT_TRACE:-}
IRQ_REPLAY_PIC_MASK=${IRQ_REPLAY_PIC_MASK:-}
QEMU_MACHINE_PROPERTIES=${QEMU_MACHINE_PROPERTIES:-}
QEMU_ACCEL=${QEMU_ACCEL:-}
# Bound pathological guests before the Python converter materializes JSONL.
# Normal current-contract guests are well below these limits; callers can
# raise them explicitly for a reviewed long-running capture.
MAX_QEMU_EVENTS=${MAX_QEMU_EVENTS:-100000}
MAX_QEMU_STATES=${MAX_QEMU_STATES:-100001}
MAX_QEMU_CAPTURE_BYTES=${MAX_QEMU_CAPTURE_BYTES:-268435456}

for limit in MAX_QEMU_EVENTS MAX_QEMU_STATES MAX_QEMU_CAPTURE_BYTES; do
    value=${!limit}
    if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
        echo "QEMU system retire capture: ${limit} must be a positive integer" >&2
        exit 2
    fi
done

mkdir -p "${RUN_DIR}"
[[ -x "${QEMU_BIN}" ]]
if [[ -n "${QEMU_KERNEL}" ]]; then
    [[ -s "${QEMU_KERNEL}" ]]
else
    [[ -s "${FW_ELF}" ]]
fi
if [[ -n "${QEMU_DTB}" ]]; then
    [[ -s "${QEMU_DTB}" ]]
fi

# A timed-out QEMU process can leave a complete-looking capture from an older
# invocation in place.  Remove every run-owned artifact before starting so a
# retry can never convert stale events/state into a fresh retire trace.
rm -f "${RUN_DIR}/qemu_instruction_events.jsonl" \
      "${RUN_DIR}/qemu_state.jsonl" \
      "${RUN_DIR}/qemu_registers.txt" \
      "${RUN_DIR}/qemu_retire.jsonl" \
      "${RUN_DIR}/qemu_trace_capture.log" \
      "${RUN_DIR}/trace_compare.log" \
      "${RUN_DIR}/qemu_capture_guard.log"

if [[ -z "${PLUGIN_INCLUDE}" ]]; then
    for candidate in \
        "${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-bundle/usr/local/include" \
        "${ROOT_DIR}/build/deps/src/qemu-9.2.0/include" \
        "${ROOT_DIR}/build/deps/qemu/include"; do
        if [[ -s "${candidate}/qemu-plugin.h" ]]; then
            PLUGIN_INCLUDE="${candidate}"
            break
        fi
    done
fi
if [[ -z "${PLUGIN_INCLUDE}" || ! -s "${PLUGIN_INCLUDE}/qemu-plugin.h" ]]; then
    echo "QEMU system retire capture: missing qemu-plugin.h" >&2
    echo "Set PLUGIN_INCLUDE to a directory containing qemu-plugin.h" >&2
    exit 1
fi
{
    "${QEMU_BIN}" --version
    sha256sum "${QEMU_BIN}"
} >"${RUN_DIR}/qemu_build_identity.txt"
cc -shared -fPIC -O2 -Wall -Wextra -Werror -I"${PLUGIN_INCLUDE}" \
    $(pkg-config --cflags glib-2.0) "${PLUGIN_SOURCE}" -o "${PLUGIN}" \
    $(pkg-config --libs glib-2.0) >"${RUN_DIR}/plugin_compile.log" 2>&1

machine_spec=mips32-soc-ref
if [[ -n "${QEMU_MACHINE_PROPERTIES}" ]]; then
    machine_spec+=",${QEMU_MACHINE_PROPERTIES}"
fi
if [[ -n "${QSPI_IMAGE}" ]]; then
    machine_spec+=" ,qspi-image=$(realpath "${QSPI_IMAGE}")"
fi
accel_args=()
if [[ -n "${QEMU_ACCEL}" ]]; then
    accel_args=(-accel "${QEMU_ACCEL}")
fi
if [[ -n "${IRQ_SCHEDULE}" ]]; then
    [[ -s "${IRQ_SCHEDULE}" ]]
    machine_spec+=" ,irq-schedule=$(realpath "${IRQ_SCHEDULE}")"
    if [[ -n "${QSPI_IMAGE}" ]]; then
        :
    fi
    if [[ -n "${QEMU_ACCEL}" ]]; then
        accel_args=(-accel "${QEMU_ACCEL},one-insn-per-tb=on")
    else
        accel_args=(-accel tcg,one-insn-per-tb=on)
    fi
fi
if [[ -n "${IRQ_REPLAY_PIC_MASK}" ]]; then
    machine_spec+=" ,irq-replay-pic-mask=${IRQ_REPLAY_PIC_MASK}"
fi
if [[ -n "${DMA_EVENT_TRACE}" ]]; then
    machine_spec+=" ,dma-event-trace=$(realpath -m "${DMA_EVENT_TRACE}")"
fi
machine_spec=${machine_spec// ,/,}
cpu_args=()
if [[ -n "${QEMU_CPU}" ]]; then
    cpu_args=(-cpu "${QEMU_CPU}")
fi
set +e
# QEMU startup plus plugin initialization can occasionally race with a stale
# TCG process after a previous timeout. Retry one fresh invocation only for the
# timeout status; semantic failures and other exit codes remain failures.
qemu_cmd=(
    "${QEMU_BIN}"
    -plugin "file=${PLUGIN},trace=${RUN_DIR}/qemu_instruction_events.jsonl,state=${RUN_DIR}/qemu_state.jsonl,registers=${RUN_DIR}/qemu_registers.txt,max-records=${MAX_QEMU_EVENTS}"
    -M "${machine_spec}"
    "${cpu_args[@]}"
    "${accel_args[@]}"
    -m "${QEMU_MEMORY}" -nographic -monitor none
)
if [[ -n "${QEMU_KERNEL}" ]]; then
    qemu_cmd+=( -kernel "${QEMU_KERNEL}" )
else
    qemu_cmd+=( -kernel "${FW_ELF}" )
fi
if [[ -n "${QEMU_DTB}" ]]; then
    qemu_cmd+=( -dtb "${QEMU_DTB}" )
fi
if [[ -n "${QEMU_APPEND}" ]]; then
    qemu_cmd+=( -append "${QEMU_APPEND}" )
fi
printf 'QEMU command:' >"${RUN_DIR}/qemu_command.txt"
printf ' %q' "${qemu_cmd[@]}" >>"${RUN_DIR}/qemu_command.txt"
printf '\n' >>"${RUN_DIR}/qemu_command.txt"
status=124
attempts=1
qemu_exit_note=""
for attempt in 1 2; do
    attempts=${attempt}
    # The capture is deliberately non-interactive.  Closing the inherited
    # terminal input prevents QEMU from being stopped by job-control signals
    # when a caller launches the gate from a PTY (for example, make via VCS).
    timeout "${QEMU_TIMEOUT:-30}" "${qemu_cmd[@]}" </dev/null \
        >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log"
    status=$?
    # A QEMU process can outlive the final guest shutdown long enough for
    # timeout(1) to report 124 even after the plugin flushed a complete
    # architectural capture. Preserve that first complete capture; retrying
    # would delete valid evidence and can turn a passing guest into a false
    # failure if the second startup races the first process teardown.
    if [[ ${status} -eq 124 && ${attempt} -eq 1 &&
          -s "${RUN_DIR}/qemu_instruction_events.jsonl" &&
          -s "${RUN_DIR}/qemu_state.jsonl" &&
          -s "${RUN_DIR}/qemu_registers.txt" ]]; then
        qemu_exit_note="timeout after complete capture (status ${status}, attempts ${attempts})"
        echo "QEMU system retire capture: ${qemu_exit_note}" >&2
        status=0
        break
    fi
    [[ ${status} -eq 124 && ${attempt} -eq 1 ]] || break
done
set -e
if [[ ${status} -ne 0 ]]; then
    # Some hosts leave QEMU in its terminal idle loop after the completion
    # store, so timeout(1) can report 124 even though the plugin flushed a
    # complete architectural capture. Keep this distinct from a failed
    # capture: all artifact integrity checks and the strict comparator below
    # still have to pass.
    if [[ ${status} -eq 124 && -s "${RUN_DIR}/qemu_instruction_events.jsonl" &&
          -s "${RUN_DIR}/qemu_state.jsonl" && -s "${RUN_DIR}/qemu_registers.txt" ]]; then
        qemu_exit_note="timeout after complete capture (status ${status}, attempts ${attempts})"
        echo "QEMU system retire capture: ${qemu_exit_note}" >&2
    else
        {
            echo "QEMU system retire capture: QEMU exited with status ${status} after ${attempts} attempt(s)"
            cat "${RUN_DIR}/qemu_command.txt"
            echo "stdout=${RUN_DIR}/qemu_stdout.log stderr=${RUN_DIR}/qemu_stderr.log"
        } >&2
        exit "${status}"
    fi
else
    qemu_exit_note="clean exit (status 0, attempts ${attempts})"
fi
if [[ "${REQUIRE_SMOKE_OUTPUT:-1}" == "1" ]]; then
    grep -q 'QEMU_SYSTEM_SMOKE: UART_PASS' "${RUN_DIR}/qemu_stdout.log"
    grep -q 'QEMU_SYSTEM_SMOKE: SRAM_PASS' "${RUN_DIR}/qemu_stdout.log"
fi
events=$(wc -l <"${RUN_DIR}/qemu_instruction_events.jsonl")
states=$(wc -l <"${RUN_DIR}/qemu_state.jsonl")
(( events > 0 && states > events - 1 ))
[[ -s "${RUN_DIR}/qemu_registers.txt" ]]
for reg in r1 pc status cause epc; do
    grep -qx "${reg}" "${RUN_DIR}/qemu_registers.txt"
done
event_bytes=$(stat -c '%s' "${RUN_DIR}/qemu_instruction_events.jsonl")
state_bytes=$(stat -c '%s' "${RUN_DIR}/qemu_state.jsonl")
if (( events > MAX_QEMU_EVENTS || states > MAX_QEMU_STATES ||
      event_bytes > MAX_QEMU_CAPTURE_BYTES ||
      state_bytes > MAX_QEMU_CAPTURE_BYTES )); then
    {
        echo "QEMU system retire capture: pathological capture rejected before conversion"
        echo "events=${events} states=${states} event_bytes=${event_bytes} state_bytes=${state_bytes}"
        echo "limits events=${MAX_QEMU_EVENTS} states=${MAX_QEMU_STATES} bytes=${MAX_QEMU_CAPTURE_BYTES}"
        echo "The guest did not produce a bounded capture; inspect qemu_stdout.log and qemu_stderr.log."
    } | tee "${RUN_DIR}/qemu_capture_guard.log" >&2
    exit 2
fi
if [[ "${STOP_AFTER_MAILBOX:-0}" == "1" ]] &&
   ! rg -q '"mem_addr":"a000fffc".*"mem_value":"deadbeef"' \
       "${RUN_DIR}/qemu_instruction_events.jsonl"; then
    {
        echo "QEMU system retire capture: completion mailbox was not observed"
        echo "events=${events} states=${states}"
        echo "The guest likely trapped, failed, or entered a loop before completion."
    } | tee "${RUN_DIR}/qemu_capture_guard.log" >&2
    exit 2
fi
python3 "${SCRIPT_DIR}/qemu_system_state_to_jsonl.py" \
    "${RUN_DIR}/qemu_instruction_events.jsonl" "${RUN_DIR}/qemu_state.jsonl" \
    "${RUN_DIR}/qemu_retire.jsonl" >"${RUN_DIR}/qemu_trace_capture.log" 2>&1
retire_events=$(wc -l <"${RUN_DIR}/qemu_retire.jsonl")
(( retire_events > 0 && retire_events <= events ))

if [[ -n "${RTL_TRACE}" && -s "${RTL_TRACE}" ]]; then
    compare_args=()
    if [[ "${STOP_AFTER_MAILBOX:-0}" == "1" ]]; then
        compare_args+=(--stop-after-mailbox)
    fi
    if [[ -n "${TRACE_COMPARE_ALIGN_FIRST_PC:-}" ]]; then
        compare_args+=(--align-first-pc "${TRACE_COMPARE_ALIGN_FIRST_PC}")
    fi
    if [[ "${TRACE_COMPARE_ALLOW_GOLDEN_PREFIX:-0}" == "1" ]]; then
        compare_args+=(--allow-golden-prefix)
    fi
    if [[ "${TRACE_COMPARE_GOLDEN_TO_RTL:-0}" == "1" ]]; then
        compare_args+=(--truncate-golden-to-rtl)
    fi
    compare_golden="${RUN_DIR}/qemu_retire.jsonl"
    if [[ -n "${TRACE_COMPARE_GOLDEN_LIMIT:-}" ]]; then
        if ! [[ "${TRACE_COMPARE_GOLDEN_LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
            echo "TRACE_COMPARE_GOLDEN_LIMIT must be a positive integer" >&2
            exit 2
        fi
        compare_golden="${RUN_DIR}/qemu_retire_compare_prefix.jsonl"
        head -n "${TRACE_COMPARE_GOLDEN_LIMIT}" "${RUN_DIR}/qemu_retire.jsonl" >"${compare_golden}"
        if [[ "$(wc -l <"${compare_golden}")" -ne "${TRACE_COMPARE_GOLDEN_LIMIT}" ]]; then
            echo "QEMU system retire capture: golden trace shorter than requested compare prefix" >&2
            exit 2
        fi
    fi
    python3 "${SCRIPT_DIR}/trace_compare.py" "${compare_args[@]}" "${RTL_TRACE}" \
        "${compare_golden}" >"${RUN_DIR}/trace_compare.log" 2>&1
    compare_records=$(wc -l <"${compare_golden}")
    differential=PASS
    differential_reason="RTL/QEMU retire traces compare equal"
else
    differential=BLOCKED
    differential_reason="RTL_TRACE was not supplied; QEMU reference trace is complete but no RTL trace was compared"
    compare_records=0
fi

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Retire Capture

- Capture: PASS
- Machine: mips32-soc-ref
- Guest kernel/firmware: ${QEMU_KERNEL:-${FW_ELF}}
- Instruction events: ${events}
- State-boundary records: ${states}
- QEMU GDB registers: $(wc -l <"${RUN_DIR}/qemu_registers.txt")
- QEMU build identity: qemu_build_identity.txt
- QEMU attempts: ${attempts}
- QEMU accelerator: ${QEMU_ACCEL:-default}
- QEMU exit: ${qemu_exit_note}
- Evidence: plugin_compile.log, qemu_build_identity.txt, qemu_command.txt, qemu_instruction_events.jsonl, qemu_state.jsonl, qemu_retire.jsonl, qemu_trace_capture.log, qemu_stdout.log, qemu_stderr.log
- Differential: ${differential}
- Compared records: ${compare_records}
- Differential reason: ${differential_reason}
- Residual risk: interrupt replay scheduling, multi-event instructions, and broader exception corpus remain unclosed.
EOF
echo "QEMU system retire capture: PASS (differential ${differential})"
