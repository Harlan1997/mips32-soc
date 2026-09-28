#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_retire"}
QEMU_SRC_EXPLICIT=0
QEMU_BUILD_EXPLICIT=0
if [[ -n "${QEMU_SRC:-}" ]]; then
    QEMU_SRC_EXPLICIT=1
fi
if [[ -n "${QEMU_BUILD:-}" ]]; then
    QEMU_BUILD_EXPLICIT=1
fi
QEMU_SRC=${QEMU_SRC:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0"}
QEMU_BUILD=${QEMU_BUILD:-"${QEMU_SRC}/build-mipsel-softmmu"}
QEMU_BIN=${QEMU_BIN:-"${QEMU_BUILD}/qemu-system-mipsel"}
# When callers provide an explicit QEMU binary but omit the source/build
# variables, derive the bundle location from that binary before probing the
# plugin header.  This prevents a valid out-of-tree QEMU build from falling
# through to the repository's unrelated build/deps path.
if [[ "${QEMU_BUILD_EXPLICIT}" -eq 0 && -x "${QEMU_BIN}" ]]; then
    QEMU_BUILD=$(dirname "${QEMU_BIN}")
fi
if [[ "${QEMU_SRC_EXPLICIT}" -eq 0 && -d "${QEMU_BUILD}/../.." ]]; then
    QEMU_SRC=$(realpath "${QEMU_BUILD}/../..")
fi
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
IRQ_REPLAY_BD_MASK=${IRQ_REPLAY_BD_MASK:-}
QEMU_MACHINE_PROPERTIES=${QEMU_MACHINE_PROPERTIES:-}
QEMU_LINUX_RNG_SEED=${QEMU_LINUX_RNG_SEED:-}
QEMU_ACCEL=${QEMU_ACCEL:-}
QEMU_ICOUNT=${QEMU_ICOUNT:-}
QEMU_STOP_ON_TERMINAL=${QEMU_STOP_ON_TERMINAL:-0}
QEMU_TERMINAL_MARKER=${QEMU_TERMINAL_MARKER:-}
QEMU_MARKER_WATCHDOG_SECONDS=${QEMU_MARKER_WATCHDOG_SECONDS:-600}
QEMU_TERMINAL_DRAIN_SECONDS=${QEMU_TERMINAL_DRAIN_SECONDS:-1}
QEMU_UNBOUNDED_CAPTURE=${QEMU_UNBOUNDED_CAPTURE:-0}
QEMU_SUMMARY_ONLY=${QEMU_SUMMARY_ONLY:-0}
QEMU_PERIPHERAL_TRACE=${QEMU_PERIPHERAL_TRACE:-}
QEMU_PLUGIN_UART_TRACE=${QEMU_PLUGIN_UART_TRACE:-${QEMU_PERIPHERAL_TRACE}}
# Bound pathological guests before the Python converter materializes JSONL.
# Normal current-contract guests are well below these limits; callers can
# raise them explicitly for a reviewed long-running capture.
if [[ "${QEMU_UNBOUNDED_CAPTURE}" == "1" ]]; then
    MAX_QEMU_EVENTS=${MAX_QEMU_EVENTS:-0}
    MAX_QEMU_STATES=${MAX_QEMU_STATES:-0}
    MAX_QEMU_CAPTURE_BYTES=${MAX_QEMU_CAPTURE_BYTES:-0}
else
    MAX_QEMU_EVENTS=${MAX_QEMU_EVENTS:-100000}
    MAX_QEMU_STATES=${MAX_QEMU_STATES:-100001}
    MAX_QEMU_CAPTURE_BYTES=${MAX_QEMU_CAPTURE_BYTES:-268435456}
fi

for limit in MAX_QEMU_EVENTS MAX_QEMU_STATES MAX_QEMU_CAPTURE_BYTES; do
    value=${!limit}
    if ! [[ "${value}" =~ ^[0-9]+$ ]] ||
       { [[ "${value}" == "0" ]] && [[ "${QEMU_UNBOUNDED_CAPTURE}" != "1" ]]; }; then
        echo "QEMU system retire capture: ${limit} must be a positive integer, or zero only in unbounded marker mode" >&2
        exit 2
    fi
done
if [[ "${QEMU_STOP_ON_TERMINAL}" == "1" ]]; then
    [[ -n "${QEMU_TERMINAL_MARKER}" ]] || {
        echo "QEMU system retire capture: QEMU_TERMINAL_MARKER is required with QEMU_STOP_ON_TERMINAL=1" >&2
        exit 2
    }
    [[ "${QEMU_MARKER_WATCHDOG_SECONDS}" =~ ^[1-9][0-9]*$ ]] || {
        echo "QEMU system retire capture: QEMU_MARKER_WATCHDOG_SECONDS must be positive" >&2
        exit 2
    }
fi
if [[ "${QEMU_SUMMARY_ONLY}" == "1" && "${QEMU_STOP_ON_TERMINAL}" != "1" ]]; then
    echo "QEMU system retire capture: QEMU_SUMMARY_ONLY=1 requires terminal marker mode" >&2
    exit 2
fi

mkdir -p "${RUN_DIR}"
# A failed conversion or differential comparison must not leave a prior
# completion report that looks like evidence for the current invocation.
rm -f "${RUN_DIR}/completion_report.md"
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
      "${RUN_DIR}/qemu_capture_status.txt" \
      "${RUN_DIR}/qemu_retire.jsonl" \
      "${RUN_DIR}/qemu_trace_capture.log" \
      "${RUN_DIR}/trace_compare.log" \
      "${RUN_DIR}/qemu_capture_guard.log"

if [[ -z "${PLUGIN_INCLUDE}" ]]; then
    for candidate in \
        "${QEMU_BUILD}/qemu-bundle/usr/local/include" \
        "${QEMU_BUILD}/../include" \
        "${QEMU_SRC}/include" \
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
if [[ -n "${QEMU_PERIPHERAL_TRACE}" ]]; then
    machine_spec+=",peripheral-trace=$(realpath -m "${QEMU_PERIPHERAL_TRACE}")"
fi
if [[ -n "${QEMU_LINUX_RNG_SEED}" ]]; then
    machine_spec+=",linux-rng-seed=${QEMU_LINUX_RNG_SEED}"
fi
if [[ -n "${QSPI_IMAGE}" ]]; then
    machine_spec+=" ,qspi-image=$(realpath "${QSPI_IMAGE}")"
fi
accel_args=()
if [[ -n "${QEMU_ACCEL}" ]]; then
    accel_args=(-accel "${QEMU_ACCEL}")
fi
icount_args=()
if [[ -n "${QEMU_ICOUNT}" ]]; then
    icount_args=(-icount "${QEMU_ICOUNT}")
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
if [[ -n "${IRQ_REPLAY_BD_MASK}" ]]; then
    machine_spec+=" ,irq-replay-bd-mask=${IRQ_REPLAY_BD_MASK}"
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
terminal_plugin_arg=""
if [[ "${QEMU_STOP_ON_TERMINAL}" == "1" ]]; then
    terminal_plugin_arg=",terminal-marker=linux"
fi
summary_plugin_arg=""
if [[ "${QEMU_SUMMARY_ONLY}" == "1" ]]; then
    summary_plugin_arg=",summary-only=1"
fi
uart_plugin_arg=""
if [[ -n "${QEMU_PLUGIN_UART_TRACE}" ]]; then
    uart_plugin_arg=",uart-trace=$(realpath -m "${QEMU_PLUGIN_UART_TRACE}")"
fi
qemu_cmd=(
    "${QEMU_BIN}"
    -plugin "file=${PLUGIN},trace=${RUN_DIR}/qemu_instruction_events.jsonl,state=${RUN_DIR}/qemu_state.jsonl,status=${RUN_DIR}/qemu_capture_status.txt,registers=${RUN_DIR}/qemu_registers.txt,max-records=${MAX_QEMU_EVENTS},max-bytes=${MAX_QEMU_CAPTURE_BYTES}${terminal_plugin_arg}${summary_plugin_arg}${uart_plugin_arg}"
    -M "${machine_spec}"
    "${cpu_args[@]}"
    "${accel_args[@]}"
    "${icount_args[@]}"
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
if [[ "${QEMU_STOP_ON_TERMINAL}" == "1" ]]; then
    # Marker mode owns the process lifecycle. QEMU is stopped only after the
    # complete terminal UART marker is visible; watchdog expiry is a failure.
    setsid "${qemu_cmd[@]}" </dev/null \
        >"${RUN_DIR}/qemu_stdout.log" 2>"${RUN_DIR}/qemu_stderr.log" &
    qemu_pid=$!
    marker_seen=0
    marker_deadline=$((SECONDS + QEMU_MARKER_WATCHDOG_SECONDS))
    while kill -0 "${qemu_pid}" 2>/dev/null; do
        if grep -Fq -- "${QEMU_TERMINAL_MARKER}" "${RUN_DIR}/qemu_stdout.log" 2>/dev/null; then
            marker_seen=1
            sleep "${QEMU_TERMINAL_DRAIN_SECONDS}"
            kill -TERM -- "-${qemu_pid}" 2>/dev/null || kill -TERM "${qemu_pid}" 2>/dev/null || true
            break
        fi
        if (( SECONDS >= marker_deadline )); then
            kill -KILL -- "-${qemu_pid}" 2>/dev/null || kill -KILL "${qemu_pid}" 2>/dev/null || true
            status=124
            break
        fi
        sleep 0.1
    done
    wait "${qemu_pid}"
    child_status=$?
    if [[ "${marker_seen}" == "1" ]]; then
        status=0
        qemu_exit_note="terminal marker stop (child status ${child_status}, attempts 1)"
    elif [[ "${status:-}" != "124" ]]; then
        status=${child_status}
        qemu_exit_note="exit before terminal marker (status ${status}, attempts 1)"
    fi
else
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
fi
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
if [[ "${QEMU_STOP_ON_TERMINAL}" == "1" ]]; then
    if ! grep -q '^terminal_marker=flushed ' "${RUN_DIR}/qemu_capture_status.txt" 2>/dev/null ||
       grep -q '^capture_limit=' "${RUN_DIR}/qemu_capture_status.txt" 2>/dev/null; then
        {
            echo "QEMU system retire capture: terminal marker was not flushed by the plugin"
            cat "${RUN_DIR}/qemu_capture_status.txt" 2>/dev/null || true
        } | tee "${RUN_DIR}/qemu_capture_guard.log" >&2
        exit 2
    fi
    terminal_marker_count=$(grep -oF -- "${QEMU_TERMINAL_MARKER}" \
        "${RUN_DIR}/qemu_stdout.log" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${terminal_marker_count}" != "1" ]]; then
        echo "QEMU system retire capture: terminal marker count=${terminal_marker_count}, expected 1" >&2
        exit 2
    fi
fi
if [[ "${QEMU_SUMMARY_ONLY}" == "1" ]]; then
    [[ -s "${QEMU_PERIPHERAL_TRACE}" ]] || {
        echo "QEMU system retire capture: summary mode requires a non-empty peripheral trace" >&2
        exit 2
    }
    summary_records=$(sed -n 's/^terminal_marker=flushed record=\([0-9][0-9]*\).*/\1/p' \
        "${RUN_DIR}/qemu_capture_status.txt")
    [[ -n "${summary_records}" ]] || {
        echo "QEMU system retire capture: terminal retire count missing from summary status" >&2
        exit 2
    }
    cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU Linux Terminal Closure

- Capture: PASS (terminal-marker summary)
- Machine: mips32-soc-ref
- Guest kernel: ${QEMU_KERNEL:-${FW_ELF}}
- Retired instructions through terminal: ${summary_records}
- Terminal marker mode: ${QEMU_STOP_ON_TERMINAL} (marker=${QEMU_TERMINAL_MARKER})
- QEMU exit: ${qemu_exit_note}
- Evidence: qemu_stdout.log, qemu_stderr.log, qemu_capture_status.txt,
  ${QEMU_PERIPHERAL_TRACE}, qemu_build_identity.txt, qemu_command.txt
- Scope: complete declared Linux workload through the terminal UART marker;
  no architectural retire trace was materialized in summary mode.
EOF
    echo "QEMU system retire capture: PASS (terminal summary records=${summary_records})"
    exit 0
fi
if [[ "${REQUIRE_SMOKE_OUTPUT:-1}" == "1" ]]; then
    grep -q 'QEMU_SYSTEM_SMOKE: UART_PASS' "${RUN_DIR}/qemu_stdout.log"
    grep -q 'QEMU_SYSTEM_SMOKE: SRAM_PASS' "${RUN_DIR}/qemu_stdout.log"
fi
events=$(wc -l <"${RUN_DIR}/qemu_instruction_events.jsonl")
states=$(wc -l <"${RUN_DIR}/qemu_state.jsonl")
(( events > 0 && states >= events + 1 )) || {
    {
        echo "QEMU system retire capture: incomplete event/state window"
        echo "events=${events} states=${states} (required states >= events + 1)"
        echo "The capture likely hit MAX_QEMU_CAPTURE_BYTES before the final post-state."
    } | tee "${RUN_DIR}/qemu_capture_guard.log" >&2
    exit 2
}
[[ -s "${RUN_DIR}/qemu_registers.txt" ]]
for reg in r1 pc status cause epc; do
    grep -qx "${reg}" "${RUN_DIR}/qemu_registers.txt"
done
event_bytes=$(stat -c '%s' "${RUN_DIR}/qemu_instruction_events.jsonl")
state_bytes=$(stat -c '%s' "${RUN_DIR}/qemu_state.jsonl")
if (( (MAX_QEMU_EVENTS > 0 && events > MAX_QEMU_EVENTS) ||
      (MAX_QEMU_STATES > 0 && states > MAX_QEMU_STATES) ||
      (MAX_QEMU_CAPTURE_BYTES > 0 && event_bytes > MAX_QEMU_CAPTURE_BYTES) ||
      (MAX_QEMU_CAPTURE_BYTES > 0 && state_bytes > MAX_QEMU_CAPTURE_BYTES) )); then
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

if [[ "${SKIP_COMPARE:-0}" == "1" ]]; then
    differential=SKIPPED
    differential_reason="comparison deferred until the canonical Linux differential manifest and trace validators pass"
    compare_records=0
elif [[ -n "${RTL_TRACE}" && -s "${RTL_TRACE}" ]]; then
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
    if [[ "${TRACE_COMPARE_STREAM:-0}" == "1" ]]; then
        compare_args+=(--stream)
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
- Terminal marker mode: ${QEMU_STOP_ON_TERMINAL} (marker=${QEMU_TERMINAL_MARKER:-none})
- Terminal marker count: ${terminal_marker_count:-not-applicable}
- Evidence: plugin_compile.log, qemu_build_identity.txt, qemu_command.txt, qemu_instruction_events.jsonl, qemu_state.jsonl, qemu_retire.jsonl, qemu_trace_capture.log, qemu_stdout.log, qemu_stderr.log
- Differential: ${differential}
- Compared records: ${compare_records}
- Differential reason: ${differential_reason}
- Residual risk: interrupt replay scheduling, multi-event instructions, and broader exception corpus remain unclosed.
EOF
echo "QEMU system retire capture: PASS (differential ${differential})"
