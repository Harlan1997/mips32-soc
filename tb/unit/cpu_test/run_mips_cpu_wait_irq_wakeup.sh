#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/cpu_wait_irq_wakeup"}
EDA_RUNNER=${EDA_RUNNER:-"${ROOT_DIR}/scripts/run_eda_cgroup.sh"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
"${EDA_RUNNER}" vcs -full64 -sverilog -timescale=1ns/1ps \
    +define+SOC_LINUX_GUEST_ENABLE=1 \
    +define+SOC_CPU_NONBLOCKING_ENABLE=1 \
    +define+SOC_L1_NONBLOCKING_ENABLE=1 \
    +define+SOC_ROB_FIFO_ENABLE=1 \
    +define+SOC_L1_NONBLOCKING_DDR_ENABLE=1 \
    +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
    "${ROOT_DIR}"/rtl/cpu/*.v "${ROOT_DIR}"/rtl/cache/*.v \
    "${SCRIPT_DIR}/tb_mips_cpu_wait_irq_wakeup.sv" \
    -top tb_mips_cpu_wait_irq_wakeup -l compile.log
"${EDA_RUNNER}" ./simv -no_save -l sim.log
grep -q '^WAIT_IRQ_TEST_PASS$' sim.log
echo "CPU WAIT/IRQ wakeup gate: PASS"
