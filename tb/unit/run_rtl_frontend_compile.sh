#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/unit_tb/rtl_frontend_compile"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

mkdir -p "${RUN_ROOT}"
RTL_FILES=(
    "${ROOT_DIR}"/rtl/clock/*.v
    "${ROOT_DIR}"/rtl/cpu/*.v
    "${ROOT_DIR}"/rtl/axi/*.v
    "${ROOT_DIR}"/rtl/perips/*.v
    "${ROOT_DIR}"/rtl/cache/*.v
    "${ROOT_DIR}"/rtl/soc_fabric.v
    "${ROOT_DIR}"/rtl/soc_core_subsystem.v
    "${ROOT_DIR}"/rtl/soc_memory_subsystem.v
    "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v
    "${ROOT_DIR}"/rtl/soc_debug_subsystem.v
    "${ROOT_DIR}"/rtl/mips_soc_impl.v
    "${ROOT_DIR}"/rtl/mips_soc.v
    "${ROOT_DIR}"/rtl/soc_top.v
)

run_soc_compile() {
    local name="$1"
    shift
    local dir="${RUN_ROOT}/${name}"
    mkdir -p "${dir}"
    echo "--- RTL frontend compile: ${name} ---"
    (
        cd "${dir}"
        vcs -full64 -sverilog -timescale=1ns/1ps \
            -top soc_top \
            +incdir+"${ROOT_DIR}/rtl/include" \
            +incdir+"${ROOT_DIR}/rtl/cpu" \
            +incdir+"${ROOT_DIR}/rtl/axi" \
            +incdir+"${ROOT_DIR}/rtl/perips" \
            "$@" "${RTL_FILES[@]}" -l compile.log
    )
    test -x "${dir}/simv"
    echo "${name}: PASS"
}

run_ddr4_compile() {
    local dir="${RUN_ROOT}/ddr4_controller"
    mkdir -p "${dir}"
    echo "--- RTL frontend compile: ddr4_controller ---"
    (
        cd "${dir}"
        vcs -full64 -sverilog -timescale=1ns/1ps \
            -top tb_axi_ddr4_controller \
            +incdir+"${ROOT_DIR}/rtl/include" \
            "${ROOT_DIR}/rtl/perips/axi_ddr4_controller.v" \
            "${ROOT_DIR}/rtl/perips/ecc_secded_32.v" \
            "${ROOT_DIR}/tb/unit/ddr4/tb_axi_ddr4_controller.sv" \
            -l compile.log
    )
    test -x "${dir}/simv"
    echo "ddr4_controller: PASS"
}

run_soc_compile default
run_soc_compile product_mmu +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1
run_soc_compile micro_tlb +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1 +define+SOC_MICRO_TLB_ENABLE=1
run_soc_compile l2_nonblocking +define+SOC_USE_L2_CACHE=1 +define+SOC_L2_CACHING=1 +define+SOC_L2_NONBLOCKING=1
run_soc_compile l1_nonblocking +define+SOC_L1_NONBLOCKING_ENABLE=1
run_soc_compile cpu_nonblocking +define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1
run_soc_compile fpu_opt_in +define+SOC_FPU_ENABLE=1
if [[ "${SOC_BPU_ENABLE:-0}" == "1" ]]; then
    run_soc_compile bpu_opt_in +define+SOC_BPU_ENABLE=1
fi
run_ddr4_compile

FRONTEND_CONFIGS="default,product_mmu,micro_tlb,l2_nonblocking,l1_nonblocking,cpu_nonblocking,fpu_opt_in,ddr4_controller"
FRONTEND_COUNT=8
if [[ "${SOC_BPU_ENABLE:-0}" == "1" ]]; then
    FRONTEND_CONFIGS="default,product_mmu,micro_tlb,l2_nonblocking,l1_nonblocking,cpu_nonblocking,fpu_opt_in,bpu_opt_in,ddr4_controller"
    FRONTEND_COUNT=9
fi

cat > "${RUN_ROOT}/rtl_frontend_compile_report.md" <<EOF
# RTL Frontend Compile Report

- Status: \`RTL_FRONTEND_COMPILE_READY\`
- Configurations: ${FRONTEND_CONFIGS}
- Run root: \`${RUN_ROOT}\`
- Evidence: each configuration produced a VCS elaborated \`simv\`; see \`*/compile.log\`.
- Scope: RTL parsing/elaboration only; no synthesis, STA, PPA, lint, CDC/RDC or formal.
EOF

echo "RTL frontend compile gate: PASS (${FRONTEND_COUNT}/${FRONTEND_COUNT})"
