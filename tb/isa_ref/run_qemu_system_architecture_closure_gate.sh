#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_architecture_closure"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
export BUILD_DIR
mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md"

run_gate() {
    local name=$1
    shift
    echo "== ${name} ==" | tee "${RUN_DIR}/${name}.log"
    "$@" >>"${RUN_DIR}/${name}.log" 2>&1
}

# Keep all children serial. They share the project QEMU build and the EDA
# license, while each child writes independent evidence below build/.
run_gate current_contract \
    make -C "${ROOT_DIR}" qemu-system-current-contract-gate
run_gate selected_differential \
    make -C "${ROOT_DIR}" qemu-system-selected-differential-gate
run_gate mmu_refill_differential \
    make -C "${ROOT_DIR}" qemu-system-mmu-refill-differential-gate
run_gate mmu_pagemask_differential \
    make -C "${ROOT_DIR}" qemu-system-mmu-pagemask-gate
run_gate mmu_os_pressure \
    make -C "${ROOT_DIR}" qemu-system-mmu-os-pressure-gate
run_gate fpu_fpe_boundary_differential \
    make -C "${ROOT_DIR}" qemu-system-fpu-fpe-boundary-differential-gate
run_gate fpu_fpe_double_differential \
    make -C "${ROOT_DIR}" qemu-system-fpu-fpe-double-differential-gate
run_gate llsc_differential \
    make -C "${ROOT_DIR}" qemu-system-llsc-differential-gate
run_gate linux_userspace_marker \
    make -C "${ROOT_DIR}" linux-boot-build-gate

QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
{
    "${QEMU_BIN}" --version
    sha256sum "${QEMU_BIN}"
} >"${RUN_DIR}/qemu_build_identity.txt"

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Architecture Closure Gate

- Result: PASS
- Machine: mips32-soc-ref
- Sub-gates: current peripheral contract, selected ISA/FPU/privileged and
  peripheral retire differential, FPU precise exception boundary differential,
  MMU refill/PageMask/OS-pressure differential, LL/SC reservation differential,
  and generic Linux kernel-to-userspace marker boot.
- Evidence: child logs in this directory, QEMU build identity, and child
  reports under build/isa_ref/ and build/linux_boot/real/.
- Boundary: this is a bounded architecture integration gate. It does not claim
  full MIPS32 ISA compliance, complete IEEE-754/OS FPU ABI, unrestricted Linux
  VM/page-table ownership or multicore shootdown, full RTL system-mode Linux
  differential, physical DDR/QSPI timing, or formal/CDC/RDC/lint signoff.
EOF
echo "QEMU system architecture closure gate: PASS"
