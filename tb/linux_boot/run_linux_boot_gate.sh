#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/real"}
QEMU_SYSTEM_BIN=${QEMU_SYSTEM_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
mkdir -p "${RUN_DIR}"
BUILD_DIR="${RUN_DIR}" "${SCRIPT_DIR}/build_linux_boot.sh" >"${RUN_DIR}/build.log" 2>&1
test -x "${QEMU_SYSTEM_BIN}"
set +e
# Use the architectural SC-consumes-reservation behavior for the Linux guest
# as well. Keeping the opt-in compatibility policy here leaves wait4's LL/SC
# retry loop with a stale reservation and can strand the parent after the
# protected-page child exits.
"${QEMU_SYSTEM_BIN}" \
    -accel tcg,thread=single \
    -M mips32-soc-ref -m 64M -cpu 24Kc \
    -kernel "${RUN_DIR}/kernel/vmlinux" -dtb "${RUN_DIR}/mips32_soc_ref.dtb" \
    -display none -monitor none >"${RUN_DIR}/qemu_stdout.log" \
    2>"${RUN_DIR}/qemu_stderr.log" &
qemu_pid=$!
qemu_timeout="${QEMU_TIMEOUT:-120s}"
qemu_timeout_seconds="${qemu_timeout%s}"
if ! [[ "${qemu_timeout_seconds}" =~ ^[0-9]+$ ]]; then
    echo "Linux boot gate: QEMU_TIMEOUT must be an integer number of seconds or Ns" >&2
    kill -TERM "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true
    exit 2
fi
deadline=$((SECONDS + qemu_timeout_seconds))
success_marker='MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS'
while kill -0 "${qemu_pid}" 2>/dev/null; do
    if rg -q "${success_marker}" "${RUN_DIR}/qemu_stdout.log"; then
        # The guest has emitted every required marker. Stop before Linux kills
        # init and enters its expected no-panic console shutdown path.
        kill -TERM "${qemu_pid}" 2>/dev/null || true
        break
    fi
    if (( SECONDS >= deadline )); then
        kill -TERM "${qemu_pid}" 2>/dev/null || true
        break
    fi
    sleep 1
done
wait "${qemu_pid}"
status=$?
set -e

fail_gate() {
    local reason=$1
    local markers
    markers=$(rg -o 'MIPS32_SOC_LINUX_[A-Z_]+' "${RUN_DIR}/qemu_stdout.log" |
        sort -u | tr '\n' ' ' || true)
    cat >"${RUN_DIR}/completion_report.md" <<EOF
# MIPS32 SoC Linux Boot Gate

- Result: FAIL
- Reason: ${reason}
- QEMU exit status: ${status}
- Kernel: ${RUN_DIR}/kernel/vmlinux
- Device tree: ${RUN_DIR}/mips32_soc_ref.dtb
- Observed userspace markers: ${markers:-none}
- QEMU stdout: ${RUN_DIR}/qemu_stdout.log
- QEMU stderr: ${RUN_DIR}/qemu_stderr.log
- Scope: this report replaces any earlier result from the same run directory.
EOF
    echo "Linux boot gate: ${reason} (status ${status})" >&2
}

if rg -q "MIPS32_SOC_LINUX_(MMAP|MPROTECT|BRK|SLEEP|YIELD|FORK_WAIT)_FAILURE" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "userspace failure marker was observed"
    exit 1
fi
if ! rg -q "Run /init as init process" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "kernel did not reach initramfs /init"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_BOOT_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "kernel reached /init but userspace marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_MMAP_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "anonymous/file-backed mmap marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_MPROTECT_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "mprotect marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_MPROTECT_FAULT_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "protected-write SIGSEGV marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_BRK_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "heap brk marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_SLEEP_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "nanosleep wakeup marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_YIELD_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "sched_yield marker was not observed"
    exit 1
fi
exec_count=$(rg -c "MIPS32_SOC_LINUX_EXEC_SUCCESS" "${RUN_DIR}/qemu_stdout.log" || true)
if [[ "${exec_count}" -lt 2 ]]; then
    fail_gate "expected two exec child markers, observed ${exec_count}"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "parent wait4 marker was not observed"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_WAIT_STATUS_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "child wait status marker was not observed"
    exit 1
fi
cat >"${RUN_DIR}/completion_report.md" <<EOF
# MIPS32 SoC Linux Boot Gate

- Result: PASS (kernel-to-userspace marker)
- Kernel: ${RUN_DIR}/kernel/vmlinux
- Device tree: ${RUN_DIR}/mips32_soc_ref.dtb
- Boot protocol: MIPS UHI with an opaque DTB
- TCG execution: single-threaded for the single-vCPU Linux contract
- Evidence: Linux printed its version, registered/enabled ttyS0, reached the
  initramfs /init process, touched one word on each of four page-spaced user
  stack locations, faulted in five anonymous mmap2 pages, mapped and read one
  file-backed /bin/vm_child page, changed the anonymous mapping read-only and
  back to read/write with mprotect while reading all five pages, verified a
  child write terminated with SIGSEGV, unmapped both
  regions, expanded the process heap by five pages with brk, faulted in each
  heap page, restored the original break, slept for 1 ms through nanosleep and
  woke normally, explicitly yielded once with sched_yield, forked two children,
  execve'd /bin/vm_child in each child, observed two new-image markers, reaped
  both with wait4 and verified normal exit status 0 for each child, and then
  emitted the
  boot and fork/wait success markers through the modeled UART.
- Linux console log: $([[ -s "${RUN_DIR}/qemu_stdout.log" ]] && rg -q "Linux version" "${RUN_DIR}/qemu_stdout.log" && echo present || echo absent)
- Scope: generic MIPS kernel boot and UART/initramfs execution on the QEMU
  reference machine; U-Boot, real QSPI/DDR devices, Linux drivers beyond the
  UART console, and RTL system-mode Linux differential remain open.
EOF
echo "Linux boot gate: PASS"
