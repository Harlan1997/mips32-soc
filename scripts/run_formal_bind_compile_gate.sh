#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/verification_foundation/formal_bind_compile"}
mkdir -p "${RUN_ROOT}"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

compile_target() {
    local name="$1" top="$2" bind_define="$3"
    shift 3
    local dir="${RUN_ROOT}/${name}"
    mkdir -p "${dir}"
    echo "--- formal bind compile: ${name} ---"
    (
        cd "${dir}"
        vcs -full64 -sverilog -timescale=1ns/1ps -top "${top}" \
            "+define+FORMAL_ENABLE" "+define+${bind_define}" \
            +incdir+"${ROOT_DIR}/rtl/include" "$@" -l compile.log
    )
    test -x "${dir}/simv"
    echo "${name}: PASS"
}

compile_target dcache dcache FORMAL_BIND_DCACHE \
    "${ROOT_DIR}/rtl/cache/dcache.v" \
    "${ROOT_DIR}/tb/formal/dcache_invariants.sva" \
    "${ROOT_DIR}/tb/formal/formal_bind.sv"
compile_target tlb mips_tlb FORMAL_BIND_TLB \
    "${ROOT_DIR}/rtl/cpu/mips_micro_tlb.v" "${ROOT_DIR}/rtl/cpu/mips_tlb.v" \
    "${ROOT_DIR}/tb/formal/tlb_invariants.sva" "${ROOT_DIR}/tb/formal/formal_bind.sv"
compile_target vic apb_vic FORMAL_BIND_VIC \
    "${ROOT_DIR}/rtl/perips/apb_vic.v" \
    "${ROOT_DIR}/tb/formal/interrupt_priority.sva" \
    "${ROOT_DIR}/tb/formal/formal_bind.sv"
compile_target fabric soc_fabric FORMAL_BIND_FABRIC \
    "${ROOT_DIR}/rtl/axi/axi2apb_bridge.v" "${ROOT_DIR}/rtl/axi/axi_crossbar.v" \
    "${ROOT_DIR}/rtl/axi/axi_id_tracker.v" "${ROOT_DIR}/rtl/axi/axi_read_timeout_guard.v" \
    "${ROOT_DIR}/rtl/soc_fabric.v" "${ROOT_DIR}/tb/formal/arb_fairness.sva" \
    "${ROOT_DIR}/tb/formal/formal_bind.sv"
compile_target bpu mips_bpu FORMAL_BIND_BPU \
    "${ROOT_DIR}/rtl/cpu/mips_bpu.v" \
    "${ROOT_DIR}/tb/formal/bpu_invariants.sva" \
    "${ROOT_DIR}/tb/formal/formal_bind.sv"

cat > "${RUN_ROOT}/formal_bind_compile_report.md" <<EOF
# Formal DUT Binding Compile Gate

- Result: PASS
- Targets: dcache, mips_tlb, apb_vic, soc_fabric, mips_bpu
- Define: FORMAL_ENABLE plus target-specific FORMAL_BIND_*
- Evidence: each target directory contains a VCS compile.log and elaborated simv.
- Boundary: syntax/elaboration only; no formal engine proof is claimed.
EOF
echo "formal bind compile gate: PASS (5/5)"
