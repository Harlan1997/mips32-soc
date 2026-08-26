#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_differential"}
FW_TEST=${FW_TEST:-qemu_system_lockstep_min}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/${FW_TEST}"}
FW_HEX=${FW_HEX:-"${FW_DIR}/firmware.hex"}
FW_ELF=${FW_ELF:-"${FW_DIR}/firmware.elf"}
FLASH_IMAGE=${FLASH_IMAGE:-}
QEMU_QSPI_IMAGE=${QEMU_QSPI_IMAGE:-${FLASH_IMAGE}}
QEMU_CPU=${QEMU_CPU:-}
RTL_DIR=${RTL_DIR:-"${RUN_DIR}/rtl"}
RTL_TRACE=${RTL_TRACE:-"${RTL_DIR}/rtl_retire.jsonl"}
RTL_IRQ_REPLAY=${RTL_IRQ_REPLAY:-0}
RTL_VCS_EXTRA_ARGS=${RTL_VCS_EXTRA_ARGS:-}
QEMU_CAPTURE_TMPDIR=${QEMU_CAPTURE_TMPDIR:-0}

# Normalize caller-provided relative paths before passing RETIRE_TRACE through
# the UVM wrapper, which resolves its own run directory relative to the repo.
RUN_DIR=$(realpath -m "${RUN_DIR}")
FW_DIR=$(realpath -m "${FW_DIR}")
FW_HEX=$(realpath -m "${FW_HEX}")
FW_ELF=$(realpath -m "${FW_ELF}")
RTL_DIR=$(realpath -m "${RTL_DIR}")
RTL_TRACE=$(realpath -m "${RTL_TRACE}")

mkdir -p "${RUN_DIR}" "${RTL_DIR}"
# Never leave a previous PASS report behind when a new run fails before it can
# replace the report.  The trace comparator and current artifacts remain the
# authoritative result for this invocation.
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/qemu_gate.log"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/${FW_TEST}" \
    OUT_DIR="$(realpath -m "${FW_DIR}")" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
sha256sum "${FW_HEX}" "${FW_ELF}" >"${RUN_DIR}/firmware.sha256"

# The base test leaves the CPU as the only bus initiator; mailbox success ends
# the simulation, so its trace corresponds only to the guest execution.
rtl_env=(FW_HEX="${FW_HEX}" TESTNAME=soc_base_test SEED=1 RUN_DIR="${RTL_DIR}"
         RETIRE_TRACE="${RTL_TRACE}")
if [[ -n "${RTL_VCS_EXTRA_ARGS}" ]]; then
    rtl_env+=(VCS_EXTRA_ARGS="${RTL_VCS_EXTRA_ARGS}")
fi
if [[ -n "${FLASH_IMAGE}" ]]; then
    rtl_env+=(FLASH_IMAGE="${FLASH_IMAGE}")
fi
# VCS compile/elaboration is part of this command and can consume most of the
# historical 30-second budget on a cold run. Keep the limit overridable while
# preventing a valid retire corpus from being killed during compilation.
timeout "${RTL_TIMEOUT:-120}" env "${rtl_env[@]}" "${ROOT_DIR}/tb/uvm_tb/run_uvm.sh" \
    >"${RUN_DIR}/rtl_gate.log" 2>&1

if [[ ! -s "${RTL_TRACE}" ]]; then
    echo "QEMU system differential: FAIL (empty RTL retire trace)" >&2
    exit 1
fi

irq_replay_args=()
if [[ "${RTL_IRQ_REPLAY}" == "1" ]]; then
    IRQ_SCHEDULE="${RUN_DIR}/rtl_irq_schedule.txt"
    schedule_args=()
    if [[ -n "${RTL_IRQ_SCHEDULE_OFFSET:-}" ]]; then
        schedule_args+=(--offset "${RTL_IRQ_SCHEDULE_OFFSET}")
    fi
    python3 "${SCRIPT_DIR}/rtl_irq_schedule.py" "${RTL_TRACE}" "${IRQ_SCHEDULE}" "${schedule_args[@]}"
    irq_replay_args=(IRQ_SCHEDULE="${IRQ_SCHEDULE}")
fi

qemu_run_dir="${RUN_DIR}/qemu"
qemu_tmp_dir=""
if [[ "${QEMU_CAPTURE_TMPDIR}" == "1" ]]; then
    qemu_tmp_dir=$(mktemp -d /tmp/mips32-qemu-capture.XXXXXX)
    qemu_run_dir="${qemu_tmp_dir}"
fi
env RUN_DIR="${qemu_run_dir}" FW_ELF="${FW_ELF}" RTL_TRACE="${RTL_TRACE}" QEMU_CPU="${QEMU_CPU}" \
REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=1 QSPI_IMAGE="${QEMU_QSPI_IMAGE}" \
"${irq_replay_args[@]}" \
"${ROOT_DIR}/tb/isa_ref/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

if [[ -n "${qemu_tmp_dir}" ]]; then
    mkdir -p "${RUN_DIR}/qemu"
    cp -a "${qemu_tmp_dir}/." "${RUN_DIR}/qemu/"
    rm -rf "${qemu_tmp_dir}"
fi

if ! grep -q '^TRACE_COMPARE_PASS ' "${RUN_DIR}/qemu/trace_compare.log"; then
    cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System RTL Retire Differential

- Result: FAIL
- Firmware: ${FW_ELF}
- RTL trace: ${RTL_TRACE}
- QEMU trace: ${RUN_DIR}/qemu/qemu_retire.jsonl
- Evidence: firmware_build.log, firmware.sha256, rtl_gate.log, qemu/qemu_build_identity.txt, qemu/qemu_trace_capture.log, qemu/trace_compare.log
EOF
    cat "${RUN_DIR}/qemu/trace_compare.log" >&2
    exit 1
fi
cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System RTL Retire Differential

- Result: PASS
- Firmware: ${FW_ELF}
- RTL trace: ${RTL_TRACE}
- QEMU trace: ${RUN_DIR}/qemu/qemu_retire.jsonl
- Evidence: firmware_build.log, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_build_identity.txt, qemu/qemu_trace_capture.log, qemu/trace_compare.log
- Scope: ${FW_TEST} guest, compared through the mailbox-store retirement boundary; the selected guest defines whether CP0, exceptions, and device accesses are covered.
- Residual risk: CP0, exceptions, delay slots, interrupt schedule replay, QSPI command/FIFO, DMA error/reset, and broader device corpus remain separate gates.
EOF
echo "QEMU system RTL retire differential: PASS"
