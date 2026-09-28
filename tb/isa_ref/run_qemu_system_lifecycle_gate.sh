#!/usr/bin/env bash
set -euo pipefail

# Validate the QEMU/plugin boundary independently of RTL comparison.  Every
# case owns a fresh directory so a timeout or failed plugin cannot reuse a
# previous capture and appear successful.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-/data/disk/tmp/mips32-soc/qemu-system-lifecycle}
QEMU_BIN=${QEMU_BIN:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel}
QEMU_BUILD=${QEMU_BUILD:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu}
FW_ELF=${FW_ELF:-${ROOT_DIR}/build/firmware/qemu_system_smoke/firmware.elf}
PLUGIN_SOURCE=${PLUGIN_SOURCE:-${ROOT_DIR}/tb/isa_ref/qemu_retire_plugin.c}
FOCUS_SOURCE=${FOCUS_SOURCE:-${ROOT_DIR}/tb/isa_ref/qemu_gpr_focus_plugin.c}
PLUGIN_INCLUDE=${PLUGIN_INCLUDE:-${QEMU_BUILD}/qemu-bundle/usr/local/include}

[[ -x "${QEMU_BIN}" ]]
[[ -s "${FW_ELF}" ]]
[[ -s "${PLUGIN_SOURCE}" && -s "${FOCUS_SOURCE}" ]]
[[ -s "${PLUGIN_INCLUDE}/qemu-plugin.h" ]]

rm -rf "${RUN_DIR}"
mkdir -p "${RUN_DIR}"
RETIRE_PLUGIN="${RUN_DIR}/libqemu_retire.so"
FOCUS_PLUGIN="${RUN_DIR}/libqemu_focus.so"
cc -shared -fPIC -O2 -Wall -Wextra -Werror -I"${PLUGIN_INCLUDE}" \
    $(pkg-config --cflags glib-2.0) "${PLUGIN_SOURCE}" -o "${RETIRE_PLUGIN}" \
    $(pkg-config --libs glib-2.0) >"${RUN_DIR}/retire_plugin_compile.log" 2>&1
cc -shared -fPIC -O2 -Wall -Wextra -Werror -I"${PLUGIN_INCLUDE}" \
    $(pkg-config --cflags glib-2.0) "${FOCUS_SOURCE}" -o "${FOCUS_PLUGIN}" \
    $(pkg-config --libs glib-2.0) >"${RUN_DIR}/focus_plugin_compile.log" 2>&1

base_cmd=("${QEMU_BIN}" -M mips32-soc-ref -cpu 24Kc -accel tcg,thread=single
          -m 64K -kernel "${FW_ELF}" -nographic -monitor none)

run_retire_case() {
    local name=$1 timeout_value=$2 max_records=$3 plugin_extra=$4
    local dir="${RUN_DIR}/${name}"
    mkdir -p "${dir}"
    local trace="${dir}/events.jsonl" state="${dir}/state.jsonl" regs="${dir}/registers.txt"
    local -a cmd=("${base_cmd[@]}" -plugin
        "file=${RETIRE_PLUGIN},trace=${trace},state=${state},status=${dir}/status.txt,registers=${regs},max-records=${max_records},max-bytes=1048576")
    if [[ -n "${plugin_extra}" ]]; then
        cmd[-1]="${cmd[-1]},${plugin_extra}"
    fi
    printf '%q ' "${cmd[@]}" >"${dir}/command.txt"
    printf '\n' >>"${dir}/command.txt"
    set +e
    timeout --foreground "${timeout_value}" "${cmd[@]}" </dev/null \
        >"${dir}/stdout.log" 2>"${dir}/stderr.log"
    local rc=$?
    set -e
    printf '%s\n' "${rc}" >"${dir}/exit_status.txt"
    if grep -Eiq 'assertion failed|SIGABRT|SIGSEGV|Segmentation fault|core dumped' \
        "${dir}/stdout.log" "${dir}/stderr.log"; then
        echo "${name}: fatal diagnostic" >&2
        return 1
    fi
}

check_complete_capture() {
    local dir=$1
    local events states
    events=$(wc -l <"${dir}/events.jsonl")
    states=$(wc -l <"${dir}/state.jsonl")
    (( events > 0 && states >= events + 1 ))
    [[ -s "${dir}/registers.txt" ]]
    for reg in r1 pc status cause epc; do grep -qx "${reg}" "${dir}/registers.txt"; done
    printf 'events=%s states=%s\n' "${events}" "${states}" >"${dir}/capture_summary.txt"
}

# 1. Normal guest terminal path. QEMU may return 0 or 124 on this machine:
# the machine can remain in its idle loop after the mailbox, but capture must
# still be complete and the UART/mailbox markers must be present.
run_retire_case normal 5s 500 ""
grep -q 'QEMU_SYSTEM_SMOKE: UART_PASS' "${RUN_DIR}/normal/stdout.log"
grep -q 'QEMU_SYSTEM_SMOKE: SRAM_PASS' "${RUN_DIR}/normal/stdout.log"
check_complete_capture "${RUN_DIR}/normal"
grep -q '^capture_complete records=' "${RUN_DIR}/normal/status.txt"
normal_rc=$(<"${RUN_DIR}/normal/exit_status.txt")
[[ "${normal_rc}" == 0 || "${normal_rc}" == 124 ]]

# 2. Deliberately too-short host timeout. No partial artifact is accepted as
# a pass; this case only proves the runner preserves and classifies 124.
run_retire_case expected_timeout 0.001s 500 ""
timeout_rc=$(<"${RUN_DIR}/expected_timeout/exit_status.txt")
[[ "${timeout_rc}" == 124 ]]

# 3. Source-side record bound. The plugin must report the limit and emit an
# exact bounded prefix; the host timeout is expected because the guest keeps
# running after capture has stopped.
run_retire_case record_limit 3s 8 ""
grep -q '^capture_limit=records records=8$' "${RUN_DIR}/record_limit/status.txt"
check_complete_capture "${RUN_DIR}/record_limit"
limit_events=$(sed -n 's/^events=\([0-9][0-9]*\) .*/\1/p' "${RUN_DIR}/record_limit/capture_summary.txt")
[[ "${limit_events}" == 8 ]]
limit_rc=$(<"${RUN_DIR}/record_limit/exit_status.txt")
[[ "${limit_rc}" == 0 || "${limit_rc}" == 124 ]]

# 4. A valid QEMU run with a target PC that cannot occur. QEMU itself must
# remain healthy; the strict checker must reject the empty/missing target trace.
missing_dir="${RUN_DIR}/missing_target_pc"
mkdir -p "${missing_dir}"
missing_log="${missing_dir}/focus.log"
set +e
timeout --foreground 5s "${base_cmd[@]}" -plugin \
    "file=${FOCUS_PLUGIN},out=${missing_log},target-only=1,pc-list=deadbeef,max-records=8" \
    </dev/null >"${missing_dir}/stdout.log" 2>"${missing_dir}/stderr.log"
missing_qemu_rc=$?
set -e
printf '%s\n' "${missing_qemu_rc}" >"${missing_dir}/qemu_exit_status.txt"
[[ "${missing_qemu_rc}" == 0 || "${missing_qemu_rc}" == 124 ]]
set +e
python3 "${ROOT_DIR}/scripts/check_qemu_focus_trace.py" "${missing_log}" \
    >"${missing_dir}/checker.log" 2>&1
missing_checker_rc=$?
set -e
printf '%s\n' "${missing_checker_rc}" >"${missing_dir}/checker_status.txt"
[[ "${missing_checker_rc}" -ne 0 ]]

# 5. Invalid plugin option must fail QEMU/plugin startup and must never be
# reclassified as a timeout or as a successful empty capture.
forced_dir="${RUN_DIR}/forced_plugin_failure"
mkdir -p "${forced_dir}"
set +e
timeout --foreground 5s "${base_cmd[@]}" -plugin \
    "file=${RETIRE_PLUGIN},trace=${forced_dir}/events.jsonl,forced-failure=1" \
    </dev/null >"${forced_dir}/stdout.log" 2>"${forced_dir}/stderr.log"
forced_rc=$?
set -e
printf '%s\n' "${forced_rc}" >"${forced_dir}/exit_status.txt"
[[ "${forced_rc}" -ne 0 && "${forced_rc}" -ne 124 ]]
grep -Eiq 'plugin|expected trace|forced-failure|error' \
    "${forced_dir}/stdout.log" "${forced_dir}/stderr.log"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System-Mode Lifecycle Gate

- Result: PASS
- Machine: mips32-soc-ref
- Firmware: ${FW_ELF}
- QEMU: ${QEMU_BIN}
- Normal terminal capture: PASS (exit ${normal_rc}, complete event/state boundary)
- Expected timeout: PASS (exit ${timeout_rc}, classified as timeout)
- Record limit: PASS (exactly ${limit_events} events, plugin limit diagnostic present)
- Missing target PC: PASS (QEMU exit ${missing_qemu_rc}; strict checker rejected absent target)
- Forced plugin failure: PASS (exit ${forced_rc}; non-timeout failure preserved)
- Boundary: this gate proves lifecycle and capture integrity; it does not prove
  generic Linux boot or RTL/QEMU architectural equivalence.
EOF
echo "QEMU system-mode lifecycle gate: PASS"
