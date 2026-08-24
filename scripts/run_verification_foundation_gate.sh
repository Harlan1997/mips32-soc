#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/verification_foundation"}
mkdir -p "${RUN_ROOT}"
inventory="${RUN_ROOT}/tool_inventory.tsv"
report="${RUN_ROOT}/verification_foundation_report.md"
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
    "${ROOT_DIR}/tb/formal/arb_fairness.sva"
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
- SVA assets: AXI/APB/reset/cache property sources present.
- Formal assets: harness and fairness property present; this is not a formal proof.
- CDC/RDC/lint: availability is recorded; missing tools are deferred explicitly.
- Waiver audit: ${waiver_count} waiver files checked; broad exclusions rejected.
- Evidence root: ${RUN_ROOT}
EOF
echo "verification foundation gate: PASS (tool availability is reported, not overstated)"
