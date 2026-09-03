#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/verification_foundation"}
mkdir -p "${RUN_ROOT}"

# Tool inventory must reflect the environment used by the gates.  In this
# project VCS and other EDA tools are module-managed, so probing PATH before
# initializing modules can incorrectly turn an available tool into a
# "missing" result.  Module setup is best-effort: the fallback/static gate
# remains runnable on hosts without an EDA installation.
module_init_status="unavailable"
module_load_status="not-requested"
if [[ -r /etc/profile.d/modules.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/modules.sh
    module_init_status="ready"
    if command -v module >/dev/null 2>&1; then
        module use /tool/module >/dev/null 2>&1 || true
        if module load vcs >/dev/null 2>&1; then
            module_load_status="vcs-loaded"
        else
            module_load_status="vcs-unavailable"
        fi
    fi
fi
inventory="${RUN_ROOT}/tool_inventory.tsv"
report="${RUN_ROOT}/verification_foundation_report.md"
static_audit="${RUN_ROOT}/formal_static_audit.log"
python3 "${ROOT_DIR}/scripts/check_formal_assets.py" | tee "${static_audit}"
bind_compile="${RUN_ROOT}/formal_bind_compile"
RUN_ROOT="${bind_compile}" bash "${ROOT_DIR}/scripts/run_formal_bind_compile_gate.sh" > "${RUN_ROOT}/formal_bind_compile.log"
printf 'tool\tstatus\tpath\tnote\n' > "${inventory}"

probe() {
    local name="$1" path
    if path=$(command -v "$name" 2>/dev/null); then
        printf '%s\tavailable\t%s\tusable from PATH\n' "$name" "$path" >> "${inventory}"
    else
        printf '%s\tmissing\t-\tinstall or load a licensed tool before signoff\n' "$name" >> "${inventory}"
    fi
}

for tool in vcs verilator yosys sby verilator_coverage spyglass questa_cdc vc_static jaspergold; do
    probe "${tool}"
done

required=(
    "${ROOT_DIR}/tb/sva/axi4_protocol_props.sv"
    "${ROOT_DIR}/tb/sva/apb_protocol_props.sv"
    "${ROOT_DIR}/tb/sva/reset_sync_props.sv"
    "${ROOT_DIR}/tb/sva/cache_state_props.sv"
    "${ROOT_DIR}/tb/sva/tlb_lookup_props.sv"
    "${ROOT_DIR}/tb/formal/arb_fairness.sva"
    "${ROOT_DIR}/tb/formal/reset_sync_invariants.sva"
    "${ROOT_DIR}/tb/formal/axi_sram_invariants.sva"
    "${ROOT_DIR}/tb/formal/README.md"
    "${ROOT_DIR}/docs/cdc_waivers.md"
)
for file in "${required[@]}"; do
    test -s "${file}" || { echo "missing verification asset: ${file}" >&2; exit 1; }
done

waiver_count=0
for file in "${ROOT_DIR}/tb/coverage"/*.el; do
    [[ -f "${file}" ]] || continue
    waiver_count=$((waiver_count + 1))
    # MODULE: <name> is a scoped section emitted by the coverage tool and is
    # not a blanket waiver. Reject only explicit all-metric directives or
    # wildcard module/metric selectors.
    if rg -n -i '(^|[[:space:]])(all[_ -]?metrics|all metrics)([[:space:]]|$)|\*.*(module|metric)' "${file}"; then
        echo "broad waiver pattern found in ${file}" >&2
        exit 1
    fi
done

available_count=$(awk -F '\t' '$2 == "available" { count++ } END { print count + 0 }' "${inventory}")
total_count=$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "${inventory}")
cat > "${report}" <<EOF
# Verification Foundation Gate

- Status: FOUNDATION_READY_WITH_EXPLICIT_TOOL_STATUS
- Tool probes: ${available_count}/${total_count} available; see tool_inventory.tsv.
- Module initialization: ${module_init_status}; VCS module: ${module_load_status}.
- SVA assets: AXI/APB/reset/cache property sources present.
- Formal bind assets: reset synchronizer and AXI SRAM response properties are
  attached to real DUTs by the 7-target compile gate.
- Formal assets: static content audit passed; this is not a formal proof.
- CDC/RDC/lint: availability is recorded; missing tools are deferred explicitly.
- Waiver audit: ${waiver_count} waiver files checked; broad exclusions rejected.
- Evidence root: ${RUN_ROOT}
- Static audit log: ${static_audit}
- DUT bind compile log: ${RUN_ROOT}/formal_bind_compile.log
EOF
echo "verification foundation gate: PASS (tool availability is reported, not overstated)"
