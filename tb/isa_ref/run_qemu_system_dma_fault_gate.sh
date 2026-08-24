#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_dma_fault"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
mkdir -p "${RUN_DIR}"

[[ -x "${QEMU_BIN}" ]]

run_case() {
    local name=$1
    local mode=$2
    local expected=$3
    local fw_dir="${RUN_DIR}/${name}/firmware"
    local log_dir="${RUN_DIR}/${name}"
    mkdir -p "${log_dir}"

    make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_axi_error" \
        OUT_DIR="${fw_dir}" FW_BASE=firmware \
        EXTRA_CFLAGS="-DDMA_EXPECT_ERR_CODE=${expected}" \
        >"${log_dir}/firmware_build.log" 2>&1

    timeout "${QEMU_TIMEOUT:-30}" "${QEMU_BIN}" \
        -M "mips32-soc-ref,dma-fault-mode=${mode}" \
        -cpu "${QEMU_CPU:-24Kc}" \
        -m 64K -kernel "${fw_dir}/firmware.elf" -nographic -monitor none \
        >"${log_dir}/qemu_stdout.log" 2>"${log_dir}/qemu_stderr.log"
    grep -q 'dma_axi_error: REGRESSION_TEST_SUCCESS' \
        "${log_dir}/qemu_stdout.log"
}

run_case read_error 1 2
run_case write_error 2 3

cat >"${RUN_DIR}/completion_report.md" <<'EOF'
# QEMU System DMA Fault Gate

- Result: PASS
- Read case: `dma-fault-mode=1` -> `ERR_AXI_READ=2`, IRQ and W1C
- Write case: `dma-fault-mode=2` -> `ERR_AXI_WRITE=3`, IRQ and W1C
- Scope: opt-in vendor-neutral reference-machine response fault model.
- Default behavior: `dma-fault-mode=0` preserves normal DMA copies.
- Residual risk: this is not physical DDR/AXI fault-signoff and does not
  model board-level reset or device failure timing.
EOF
echo "QEMU system DMA fault gate: PASS"
