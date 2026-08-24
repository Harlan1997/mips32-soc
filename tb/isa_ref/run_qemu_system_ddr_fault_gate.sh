#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_ddr_fault"}
QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
QEMU_BIN=$(realpath -m "${QEMU_BIN}")
mkdir -p "${RUN_DIR}"
[[ -x "${QEMU_BIN}" ]]

run_case() {
    local name=$1
    local mode=$2
    local expected=$3
    local case_dir="${RUN_DIR}/${name}"
    local fw_dir="${case_dir}/firmware"
    mkdir -p "${case_dir}"
    make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_ddr" \
        OUT_DIR="${fw_dir}" FW_BASE=firmware \
        EXTRA_CFLAGS="-DQEMU_DDR_FAULT_TEST -DQEMU_DDR_EXPECTED_ERROR=${expected}" \
        >"${case_dir}/firmware_build.log" 2>&1
    timeout "${QEMU_TIMEOUT:-10}" "${QEMU_BIN}" \
        -M "mips32-soc-ref,ddr-fault-mode=${mode}" -m 64K \
        -kernel "${fw_dir}/firmware.elf" -nographic -monitor none \
        >"${case_dir}/qemu_stdout.log" 2>"${case_dir}/qemu_stderr.log"
    grep -q 'QEMU_SYSTEM_DDR: FAULT_WINDOW_PASS' "${case_dir}/qemu_stdout.log"
    grep -q 'QEMU_SYSTEM_DDR: FAULT_W1C_PASS' "${case_dir}/qemu_stdout.log"
}

run_case axi_error 1 0x00040004
run_case geometry_error 2 0x00040005

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DDR Fault Gate

- Result: PASS
- Cases: ddr-fault-mode=1 AXI error and ddr-fault-mode=2 geometry error.
- Contract: sticky DDR ERROR/status classification, W1C clear and continued
  cached/uncached DDR window access.
- Default behavior: ddr-fault-mode=0 preserves READY/no-error operation.
- Residual risk: no physical PHY/JEDEC failure timing, ECC injection or board signoff.
EOF
echo "QEMU system DDR fault gate: PASS"
