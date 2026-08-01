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
    local dir="${RUN_ROOT}/ddr4_behavioral"
    mkdir -p "${dir}"
    echo "--- RTL frontend compile: ddr4_behavioral ---"
    (
        cd "${dir}"
        vcs -full64 -sverilog -timescale=1ns/1ps \
            -top tb_ddr4_phy_behavioral \
            "${ROOT_DIR}/rtl/perips/ddr4_phy_behavioral.v" \
            "${ROOT_DIR}/tb/unit/ddr4/tb_ddr4_phy_behavioral.sv" \
            -l compile.log
    )
    test -x "${dir}/simv"
    echo "ddr4_behavioral: PASS"
}

run_soc_compile default
run_soc_compile product_mmu +define+SOC_PRODUCT_BOOT_ENABLE=1 +define+SOC_MMU_ENABLE=1
run_ddr4_compile

cat > "${RUN_ROOT}/rtl_frontend_compile_report.md" <<EOF
# RTL Frontend Compile Report

- Status: \`RTL_FRONTEND_COMPILE_READY\`
- Configurations: default \`soc_top\`, product boot + MMU, DDR4 behavioral PHY
- Run root: \`${RUN_ROOT}\`
- Evidence: each configuration produced a VCS elaborated \`simv\`; see \`*/compile.log\`.
- Scope: RTL parsing/elaboration only; no synthesis, STA, PPA, lint, CDC/RDC or formal.
EOF

echo "RTL frontend compile gate: PASS (3/3)"
