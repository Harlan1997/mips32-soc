#!/bin/bash
# =============================================================================
# run_mmu_refill.sh — Phase B.3.d/B.3.4 proof-of-concept gate.
#
# Compiles the full SoC TB with +define+SOC_MMU_ENABLE=1 (project default
# stays 0; this is opt-in via the ifndef guard in soc_config.vh) and runs the
# mmu_refill firmware (tb/soc_test/fw/tests/mmu_refill), which owns a bounded
# two-level 4KB page table, allocates four backing PFNs on first touch, installs
# the faulting TLB pair half via a real refill handler, and retries with ERET.
# This is an execution-level firmware OS contract, not Linux/page allocator or
# multi-process ASID/shootdown signoff.
# =============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/soc_test/mmu_refill"}
FW_SOURCE_DIR=${FW_SOURCE_DIR:-"${ROOT_DIR}/tb/soc_test/fw/tests/mmu_refill"}
FW_DIR=${FW_DIR:-"${RUN_DIR}/firmware"}
FW_HEX="${FW_DIR}/firmware.hex"
HW_WALKER=${HW_WALKER:-0}
OS_PRESSURE=${OS_PRESSURE:-0}
TB_RETIRE_TRACE=${TB_RETIRE_TRACE:-0}
RETIRE_TRACE=${RETIRE_TRACE:-}

export MODULES_PAGER=cat PAGER=cat TERM=dumb
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

echo "--- Building mmu_refill firmware ---"
if [ "${HW_WALKER}" = 1 ]; then
    make -C "${FW_SOURCE_DIR}" OUT_DIR="${FW_DIR}" FW_BASE=firmware \
        EXTRA_CFLAGS=-DSOC_HW_WALKER clean all
elif [ "${OS_PRESSURE}" = 1 ]; then
    make -C "${FW_SOURCE_DIR}" OUT_DIR="${FW_DIR}" FW_BASE=firmware \
        EXTRA_CFLAGS='-DSOC_MMU_REFILL -DSOC_MMU_OS_PRESSURE' clean all
else
    make -C "${FW_SOURCE_DIR}" OUT_DIR="${FW_DIR}" FW_BASE=firmware \
        EXTRA_CFLAGS=-DSOC_MMU_REFILL clean all
fi

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: firmware build did not produce ${FW_HEX}"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "Run directory: $RUN_DIR"
echo "Firmware: $FW_HEX_ABS"

VCS_DEFINES=(+define+SOC_MMU_ENABLE=1 +define+SOC_MMU_BOOTSTRAP_ENABLE=1 +define+TB_SKIP_UART_PIN_CHECK +define+TB_MMU_REFILL)
if [ "${TB_RETIRE_TRACE}" = 1 ]; then
    VCS_DEFINES+=(+define+TB_RETIRE_TRACE)
fi
if [ "${HW_WALKER}" = 1 ]; then
    VCS_DEFINES+=(+define+SOC_HARDWARE_WALKER_ENABLE=1 +define+SOC_HW_WALKER=1 +define+TB_MMU_HW_WALKER)
fi
if [ "${OS_PRESSURE}" = 1 ]; then
    VCS_DEFINES+=(+define+SOC_MMU_OS_PRESSURE=1)
fi

vcs -full64 -sverilog -timescale=1ns/1ps "${VCS_DEFINES[@]}" \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu \
    +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips \
    +incdir+"${ROOT_DIR}"/tb/soc_test \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v \
    "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${ROOT_DIR}"/tb/soc_test/tb_mips_soc.v -l vcs.log

SIM_ARGS=(+FW_HEX="$FW_HEX_ABS")
if [ -n "${RETIRE_TRACE}" ]; then
    RETIRE_TRACE_ABS=$(realpath -m "${RETIRE_TRACE}")
    mkdir -p "$(dirname "${RETIRE_TRACE_ABS}")"
    SIM_ARGS+=(+RETIRE_TRACE="${RETIRE_TRACE_ABS}")
fi
./simv "${SIM_ARGS[@]}" -l sim.log

if [ "${HW_WALKER}" = 1 ]; then
    PASS_MARKER="mmu_hw_walker: PASS"
elif [ "${OS_PRESSURE}" = 1 ]; then
    PASS_MARKER="mmu_os_pressure: PASS"
else
    PASS_MARKER="mmu_refill: PASS"
fi
if grep -q "REGRESSION_TEST_SUCCESS" sim.log && \
   { [ "${HW_WALKER}" = 1 ] || grep -q "${PASS_MARKER}" sim.log; } && \
   { [ "${HW_WALKER}" = 1 ] || grep -q "MMU_REFILL_MARKER_PASS" sim.log; }; then
    echo "SUCCESS: MMU REFILL GATE PASSED"
    exit 0
else
    echo "ERROR: mmu_refill gate did not pass"
    grep -E "mmu_refill:|REGRESSION_TEST" sim.log || true
    exit 1
fi
