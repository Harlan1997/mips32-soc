#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/cpu_mmu_complete"}

mkdir -p -- "${RUN_ROOT}"
REPORT="${RUN_ROOT}/cpu_mmu_completion_report.md"
LOG="${RUN_ROOT}/cpu_mmu_completion.log"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

cat > "${REPORT}" <<EOF
# CPU/MMU RTL Functional Completion Report

- Scope: current single-core MIPS32 RTL contract and standalone dual-core IPI/TLB/exception contract
- Not covered by this report: Linux/OS boot, complete OS scheduler semantics, ECC and production EIC/VEIC. Real PHY/backend sign-off remains outside the RTL/simulation phase.
- Run root: \`${RUN_ROOT}\`

## Gate Results

EOF

run_gate() {
    local gate=$1
    echo "[CPU/MMU] ${gate}" | tee -a "${LOG}"
    if make "${gate}" 2>&1 | tee -a "${LOG}"; then
        printf -- "- \`%s\`: PASS\n" "${gate}" >> "${REPORT}"
    else
        printf -- "- \`%s\`: FAIL\n" "${gate}" >> "${REPORT}"
        exit 1
    fi
}

rm -f -- "${LOG}"

for gate in \
    cpu-cp0-gate \
    mmu-active-gate \
    tlb-asid-policy-gate \
    tlb-os-context-gate \
    tlb-invalidate-gate \
    tlb-asid-allocator-gate \
    mmu-context-contract-gate \
    tlb-shootdown-mailbox-gate \
    mmu-ipi-shootdown-gate \
    apb-mmu-ipi-status-gate \
    mmu-context-status-gate \
    product-mmu-boot-gate \
    product-mmu-ebase-modified-gate \
    product-mmu-asid-context-gate \
    product-mmu-process-pressure-gate \
    product-mmu-context-cpu-gate \
    product-cacheerr-gate \
    cpu-cache-error-gate \
    cpu-cache-op-gate \
    cpu-cache-tag-gate \
    product-vectored-interrupt-gate \
    cpu-scheduler-integration-gate \
    cpu-hardware-walker-gate \
    mdu-cpu-gate \
    llsc-gate; do
    run_gate "${gate}"
done

cat >> "${REPORT}" <<'EOF'

## Unresolved Scope Requiring Architecture Freeze

The following are not implemented by this report, and are not approved exclusions:

- complete OS/runtime page-table and scheduler semantics;
- physical multi-core CPU integration and cache coherency;
- ECC and production EIC/VEIC policy;
- full ISA compliance and kernel/Linux boot.

EOF

echo "SUCCESS: CPU/MMU RTL FUNCTIONAL GATE PASSED"
echo "Report: ${REPORT}"
