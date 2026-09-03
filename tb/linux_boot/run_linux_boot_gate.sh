#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/real"}
QEMU_SYSTEM_BIN=${QEMU_SYSTEM_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
KERNEL_INPUT=${KERNEL:-}
DTB_INPUT=${DTB:-}
mkdir -p "${RUN_DIR}"
if [[ "${SKIP_LINUX_BUILD:-0}" == "1" ]]; then
    if [[ -z "${KERNEL_INPUT}" || -z "${DTB_INPUT}" ]]; then
        echo "Linux boot gate: SKIP_LINUX_BUILD=1 requires KERNEL= and DTB=" >&2
        exit 2
    fi
    test -s "${KERNEL_INPUT}" && test -s "${DTB_INPUT}"
    KERNEL_INPUT=$(realpath "${KERNEL_INPUT}")
    DTB_INPUT=$(realpath "${DTB_INPUT}")
    printf 'Linux boot build: SKIPPED\nKERNEL=%s\nDTB=%s\n' \
        "${KERNEL_INPUT}" "${DTB_INPUT}" >"${RUN_DIR}/build.log"
else
    BUILD_DIR="${RUN_DIR}" "${SCRIPT_DIR}/build_linux_boot.sh" >"${RUN_DIR}/build.log" 2>&1
    KERNEL_INPUT="${RUN_DIR}/kernel/vmlinux"
    DTB_INPUT="${RUN_DIR}/mips32_soc_ref.dtb"
fi
test -x "${QEMU_SYSTEM_BIN}"
set +e
# The generic Linux userspace image exercises the kernel's wait4 LL/SC retry
# path.  The custom machine exposes an opt-in Linux guest policy for that
# path; bare-metal RTL/QEMU differential gates continue to use the strict
# architectural SC-consumes-reservation contract.
"${QEMU_SYSTEM_BIN}" \
    -accel tcg,thread=single \
    -M mips32-soc-ref,linux-guest=on -m 64M -cpu 24Kc \
    -kernel "${KERNEL_INPUT}" -dtb "${DTB_INPUT}" \
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
linux_gpio_only=${LINUX_GPIO_ONLY:-0}
if [[ "${linux_gpio_only}" == "1" ]]; then
    success_marker='MIPS32_SOC_LINUX_GPIO_SUCCESS'
else
    success_marker='MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS'
fi
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
- Kernel: ${KERNEL_INPUT}
- Device tree: ${DTB_INPUT}
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
if rg -q "MIPS32_SOC_LINUX_GPIO_FAILURE" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "Linux GPIO userspace failure marker was observed"
    exit 1
fi
if ! rg -q "Run /init as init process" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "kernel did not reach initramfs /init"
    exit 1
fi
if ! rg -q "mips32-soc-vic: 32-source cascaded controller on IRQ 2" \
    "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "Linux did not initialize the SoC VIC cascade on CPU IP2"
    exit 1
fi
if ! rg -q "40000000\.serial: ttyS0 at MMIO .* \(irq = [0-9]+," \
    "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "UART did not bind through the SoC VIC child IRQ domain"
    exit 1
fi
if ! rg -q "MIPS32_SOC_LINUX_BOOT_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
    fail_gate "kernel reached /init but userspace marker was not observed"
    exit 1
fi
if [[ "${linux_gpio_only}" == "1" ]]; then
    if ! rg -q "MIPS32_SOC_LINUX_GPIO_SUCCESS" "${RUN_DIR}/qemu_stdout.log"; then
        fail_gate "Linux GPIO userspace marker was not observed"
        exit 1
    fi
    cat >"${RUN_DIR}/completion_report.md" <<EOF
# MIPS32 SoC Linux GPIO Userspace Gate

- Result: PASS
- Kernel: ${KERNEL_INPUT}
- Device tree: ${DTB_INPUT}
- GPIO ABI: Linux gpio-mmio legacy sysfs, dynamic base 512
- Evidence: Linux mounted sysfs, exported GPIO512, changed its direction to
  output, wrote the value 1 through the value attribute, read the value back
  and emitted MIPS32_SOC_LINUX_GPIO_SUCCESS.
- Scope: QEMU Linux GPIO binding and userspace read/write contract. Physical
  GPIO pads, pinmux, interrupts and RTL Linux userspace remain outside this
  bounded gate.
EOF
    echo "Linux GPIO userspace gate: PASS"
    exit 0
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
- Kernel: ${KERNEL_INPUT}
- Device tree: ${DTB_INPUT}
- Boot protocol: MIPS UHI with an opaque DTB
- IRQ path: Linux SoC VIC cascade on CPU IP2; UART is a VIC child IRQ
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
