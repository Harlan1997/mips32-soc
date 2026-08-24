#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/uvm/single"}
TESTNAME=${TESTNAME:-soc_bus_stress_test}
SEED=${SEED:-1}

if [ -z "${FW_HEX:-}" ]; then
    echo "ERROR: FW_HEX must point to the firmware hex artifact."
    exit 1
fi

if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: FW_HEX does not exist: $FW_HEX"
    exit 1
fi

FW_HEX_ABS=$(realpath "$FW_HEX")
FLASH_IMAGE_ABS=""
if [ -n "${FLASH_IMAGE:-}" ]; then
    if [ ! -f "$FLASH_IMAGE" ]; then
        echo "ERROR: FLASH_IMAGE does not exist: $FLASH_IMAGE"
        exit 1
    fi
    FLASH_IMAGE_ABS=$(realpath "$FLASH_IMAGE")
fi
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "Firmware: $FW_HEX_ABS"
echo "Firmware SHA256: $(sha256sum "$FW_HEX_ABS" | awk '{print $1}')"
if [ -n "$FLASH_IMAGE_ABS" ]; then
    echo "Flash image: $FLASH_IMAGE_ABS"
    echo "Flash image SHA256: $(sha256sum "$FLASH_IMAGE_ABS" | awk '{print $1}')"
fi
echo "UVM test: $TESTNAME"
echo "Seed: $SEED"
echo "Run directory: $RUN_DIR"

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

# Opt-in L2 write-back selection. Default (unset/0) keeps the reset-safe
# write-through impl (l2_cache_wt). L2_WRITEBACK=1 appends +define+SOC_L2_WRITEBACK
# so l2_cache.v selects the write-back/write-allocate impl (l2_cache_caching).
l2_define_args=()
if [ "${L2_WRITEBACK:-0}" = "1" ]; then
    l2_define_args=(+define+SOC_L2_WRITEBACK)
    echo "L2 policy: write-back (SOC_L2_WRITEBACK)"
else
    echo "L2 policy: write-through (default)"
fi

vcs_extra_args=()
if [ -n "${VCS_EXTRA_ARGS:-}" ]; then
    read -r -a vcs_extra_args <<< "${VCS_EXTRA_ARGS}"
fi

trace_define_args=()
trace_sim_args=()
if [ -n "${RETIRE_TRACE:-}" ]; then
    trace_define_args=(+define+SOC_RETIRE_TRACE_ENABLE=1)
    trace_sim_args=(+RETIRE_TRACE="$(realpath -m "$RETIRE_TRACE")")
    echo "Retirement trace: ${RETIRE_TRACE}"
fi

# Optional simulator-only arguments used by focused debug probes.  Keep the
# default invocation unchanged; callers may provide a shell-word list such as
# SIM_EXTRA_ARGS='+VIC_DEBUG'.
extra_sim_args=()
if [ -n "${SIM_EXTRA_ARGS:-}" ]; then
    read -r -a extra_sim_args <<< "${SIM_EXTRA_ARGS}"
fi

echo "Compiling UVM Testbench with VCS..."
vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
    "${l2_define_args[@]}" \
    "${vcs_extra_args[@]}" \
    "${trace_define_args[@]}" \
    +incdir+"${ROOT_DIR}"/rtl/include +incdir+"${ROOT_DIR}"/rtl/cpu +incdir+"${ROOT_DIR}"/rtl/axi +incdir+"${ROOT_DIR}"/rtl/perips +incdir+"${ROOT_DIR}"/rtl/cache \
    +incdir+"${SCRIPT_DIR}"/agents +incdir+"${SCRIPT_DIR}"/env +incdir+"${SCRIPT_DIR}"/tests +incdir+"${SCRIPT_DIR}"/seqs +incdir+"${SCRIPT_DIR}"/checkers +incdir+"${SCRIPT_DIR}"/tb_top \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/axi/*.v "${ROOT_DIR}"/rtl/perips/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${ROOT_DIR}"/rtl/soc_fabric.v "${ROOT_DIR}"/rtl/soc_core_subsystem.v "${ROOT_DIR}"/rtl/soc_memory_subsystem.v "${ROOT_DIR}"/rtl/soc_peripheral_subsystem.v "${ROOT_DIR}"/rtl/soc_debug_subsystem.v "${ROOT_DIR}"/rtl/mips_soc_impl.v "${ROOT_DIR}"/rtl/mips_soc.v "${ROOT_DIR}"/rtl/soc_top.v \
    "${SCRIPT_DIR}"/tb_top/soc_verif_top.sv "${SCRIPT_DIR}"/tb_top/tb_top.sv \
    -l vcs_uvm_compile.log

echo "Running UVM Simulation..."
set +e
sim_args=(+UVM_TESTNAME="$TESTNAME" +ntb_random_seed="$SEED" +FW_HEX="$FW_HEX_ABS" "${trace_sim_args[@]}" "${extra_sim_args[@]}")
if [ -n "$FLASH_IMAGE_ABS" ]; then
    sim_args+=(+FLASH_IMAGE="$FLASH_IMAGE_ABS")
fi
./simv "${sim_args[@]}" 2>&1 | tee vcs_uvm.log
sim_status=${PIPESTATUS[0]}
set -e

if [ "$sim_status" -ne 0 ]; then
    echo "ERROR: UVM simulation exited with status $sim_status"
    exit "$sim_status"
fi

uvm_errors=$(awk '/UVM_ERROR[[:space:]]*:/ {value=$3} END {print value}' vcs_uvm.log)
uvm_fatals=$(awk '/UVM_FATAL[[:space:]]*:/ {value=$3} END {print value}' vcs_uvm.log)

if [ -n "$uvm_errors" ] || [ -n "$uvm_fatals" ]; then
    if [ "${uvm_errors:-1}" != "0" ] || [ "${uvm_fatals:-1}" != "0" ]; then
        echo "ERROR: UVM reported errors=$uvm_errors fatals=$uvm_fatals"
        exit 1
    fi
fi

if grep -Eq '^(Error:|Error-\[|Fatal:|Fatal-\[)' vcs_uvm.log; then
    echo "ERROR: simulator log contains SystemVerilog/VCS errors"
    exit 1
fi

if grep -Eq '^UVM_(ERROR|FATAL)[[:space:]]+(@|/)' vcs_uvm.log; then
    echo "ERROR: simulator log contains direct UVM error/fatal messages"
    exit 1
fi
