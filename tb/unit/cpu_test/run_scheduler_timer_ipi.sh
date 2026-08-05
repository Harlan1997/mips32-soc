#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/scheduler_timer_ipi"}; mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
source /etc/profile.d/modules.sh; module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/apb_timer.v" "${ROOT_DIR}/rtl/cpu/cpu_scheduler.v" "${ROOT_DIR}/tb/unit/cpu_test/tb_scheduler_timer_ipi.sv" -top tb_scheduler_timer_ipi -l compile.log
timeout 10s ./simv -l sim.log; grep -q "REGRESSION_TEST_SUCCESS scheduler_timer_ipi" sim.log
echo "scheduler timer/IPI integration: PASS"
