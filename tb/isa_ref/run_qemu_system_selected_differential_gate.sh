#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_selected_differential"}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-60}
export QEMU_TIMEOUT
mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md"

run_gate() {
    local name=$1
    shift
    echo "== ${name} ==" | tee "${RUN_DIR}/${name}.log"
    "$@" >>"${RUN_DIR}/${name}.log" 2>&1
}

# Keep this list serial: every child may invoke the shared QEMU build helper,
# and each child has an independent firmware/trace directory.
run_gate isa_implementation_audit make -C "${ROOT_DIR}" isa-implementation-audit
run_gate isa_r2 make -C "${ROOT_DIR}" qemu-system-isa-r2-differential-gate
run_gate mdu make -C "${ROOT_DIR}" qemu-system-mdu-differential-gate
run_gate branch_likely make -C "${ROOT_DIR}" qemu-system-branch-likely-differential-gate
run_gate exceptions make -C "${ROOT_DIR}" qemu-system-exception-differential-gate
run_gate break make -C "${ROOT_DIR}" qemu-system-break-differential-gate
run_gate traps make -C "${ROOT_DIR}" qemu-system-trap-differential-gate qemu-system-trap-imm-differential-gate
run_gate privileged make -C "${ROOT_DIR}" qemu-system-di-ei-differential-gate qemu-system-wait-differential-gate
run_gate bd_exception make -C "${ROOT_DIR}" qemu-system-bd-exception-differential-gate
run_gate unaligned make -C "${ROOT_DIR}" qemu-system-unaligned-gate qemu-system-unaligned-differential-gate
run_gate peripheral make -C "${ROOT_DIR}" qemu-system-peripheral-differential-gate
run_gate vic make -C "${ROOT_DIR}" qemu-system-vic-differential-gate qemu-system-vic-cpu-differential-gate
run_gate fpu_single make -C "${ROOT_DIR}" qemu-system-fpu-single-differential-gate
run_gate fpu_double make -C "${ROOT_DIR}" qemu-system-fpu-double-differential-gate
run_gate fpu_rounding make -C "${ROOT_DIR}" qemu-system-fpu-rounding-differential-gate
run_gate fpu_cu1 make -C "${ROOT_DIR}" qemu-system-fpu-cu1-exception-differential-gate
run_gate fpu_branch make -C "${ROOT_DIR}" qemu-system-fpu-branch-differential-gate
run_gate fpu_fpe_boundary make -C "${ROOT_DIR}" \
    qemu-system-fpu-fpe-boundary-differential-gate
run_gate dma_sg make -C "${ROOT_DIR}" qemu-system-dma-sg-differential-gate
run_gate dma_fault_reset make -C "${ROOT_DIR}" \
    qemu-system-dma-fault-gate qemu-system-dma-reset-inflight-gate
run_gate vic_full_sources make -C "${ROOT_DIR}" \
    qemu-system-vic-full-sources-differential-gate
run_gate mmu_ipi make -C "${ROOT_DIR}" qemu-system-mmu-ipi-contract-gate
run_gate mmu_contract make -C "${ROOT_DIR}" qemu-system-mmu-contract-gate
run_gate mmu_refill make -C "${ROOT_DIR}" qemu-system-mmu-refill-differential-gate
run_gate mmu_pagemask make -C "${ROOT_DIR}" qemu-system-mmu-pagemask-gate
run_gate mmu_process_pressure make -C "${ROOT_DIR}" \
    qemu-system-mmu-process-pressure-gate
run_gate mmu_os_pressure make -C "${ROOT_DIR}" \
    qemu-system-mmu-os-pressure-gate
run_gate l1_l2_nonblocking make -C "${ROOT_DIR}" \
    qemu-system-l1-l2-nonblocking-differential-gate
run_gate llsc make -C "${ROOT_DIR}" qemu-system-llsc-differential-gate

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Selected Differential Gate

- Result: PASS
- Machine: mips32-soc-ref
- Sub-gates: ISA R2, CPU-visible MDU, branch-likely, exceptions, break/traps, DI/EI/WAIT,
  BD/EPC, unaligned memory, peripheral/VIC, opt-in FPU single/double/rounding/CU1,
  bounded DMA v2 SG/fault/reset, 32-source VIC arbitration, MMU context/IPI/
  refill/PageMask/process-pressure/OS-pressure contract differentials,
  FPU branch/FPE boundaries and LL/SC reservation differential, plus the opt-in
  L1/CPU-ROB/DDR/L2 nonblocking combined-path differential.
- Evidence: child logs in this directory and child completion reports under
  build/isa_ref/qemu_system_*.
- Scope: selected bare-metal RTL/QEMU retire corpora through mailbox boundaries.
- Non-claim: this is not full MIPS32 ISA compliance, complete privileged/MMU
  differential, complete IEEE-754/OS FPU ABI, Linux boot, or physical device
  signoff. DMA physical fault/reset timing, unrestricted MMU demand paging,
  OS-owned page tables, full cache coherency and Linux cache ABI remain
  separate residuals.
EOF
echo "QEMU system selected differential gate: PASS"
