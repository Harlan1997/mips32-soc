#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
missing=0

# Explicit subsystem compilations must carry the APB status blocks. The
# wildcard-based UVM/SoC lists already include it and are intentionally exempt.
while IFS= read -r file; do
    if rg -q 'rtl/perips/\\*\\.v' "$file"; then
        continue
    fi
    if ! rg -q 'soc_peripheral_subsystem\\.v' "$file"; then
        continue
    fi
    for module in apb_perf_counters apb_mmu_context_status apb_ddr4_status; do
        if ! rg -q "${module}\\.v" "$file"; then
            echo "SOC_FILELIST_AUDIT_MISSING ${module}.v: $file" >&2
            missing=1
        fi
    done
done < <(rg -l 'soc_peripheral_subsystem\\.v' "$ROOT_DIR/tb" -g '*.sh')

if (( missing )); then
    exit 1
fi
echo "SOC_FILELIST_AUDIT_PASS"
