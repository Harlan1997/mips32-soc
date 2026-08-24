#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/qemu_system_unaligned"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_unaligned"}
FW_HEX=${FW_DIR}/firmware.hex
mkdir -p "${RUN_DIR}"

make -C "${ROOT_DIR}/tb/soc_test/fw/tests/qemu_system_unaligned" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1
SKIP_URG_EXCLUSION_CHECK=1 FW_HEX="${FW_HEX}" RUN_DIR="${RUN_DIR}/rtl" \
    "${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1
grep -q 'REGRESSION_TEST_SUCCESS' "${RUN_DIR}/rtl/sim.log"
echo "QEMU system unaligned RTL gate: PASS"
